import Combine
import ConnectIQ
import CoreData
import Foundation
import Swinject

// MARK: - GarminManager Protocol

/// Manages Garmin devices, allowing the app to select devices, update a known device list,
/// and send watch-state data to connected Garmin watch apps.
protocol GarminManager {
    /// Prompts the user to select Garmin devices, returning the chosen devices in a publisher.
    /// - Returns: A publisher that eventually outputs an array of selected `IQDevice` objects.
    func selectDevices() -> AnyPublisher<[IQDevice], Never>

    /// Updates the currently tracked device list. This typically persists the device list and
    /// triggers re-registration for any relevant ConnectIQ events.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice])

    /// Takes raw JSON-encoded watch-state data and dispatches it to any connected watch apps.
    /// - Parameter data: The JSON-encoded data representing the watch state.
    func sendWatchStateData(_ data: Data)

    /// The devices currently known to the app. May be loaded from disk or user selection.
    var devices: [IQDevice] { get }
}

// MARK: - BaseGarminManager

/// Concrete implementation of `GarminManager` that handles:
///  - Device registration/unregistration with Garmin ConnectIQ
///  - Data persistence for selected devices
///  - Generating & sending watch-state updates (glucose, IOB, COB, etc.) to Garmin watch apps.
final class BaseGarminManager: NSObject, GarminManager, Injectable {
    // MARK: - Dependencies & Properties

    /// Observes system-wide notifications, including `.openFromGarminConnect`.
    @Injected() private var notificationCenter: NotificationCenter!

    /// Broadcaster used for publishing or subscribing to global events (e.g., unit changes).
    @Injected() private var broadcaster: Broadcaster!

    /// APSManager containing insulin pump logic, e.g., for making bolus requests, reading basal info, etc.
    @Injected() private var apsManager: APSManager!

    /// Manages local user settings, such as glucose units (mg/dL or mmol/L).
    @Injected() private var settingsManager: SettingsManager!

    /// Stores, retrieves, and updates glucose data in CoreData.
    @Injected() private var glucoseStorage: GlucoseStorage!

    /// Stores, retrieves, and updates insulin dose determinations in CoreData.
    @Injected() private var determinationStorage: DeterminationStorage!

    @Injected() private var iobService: IOBService!

    /// Persists the user's device list between app launches.
    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    /// Router for presenting alerts or navigation flows (injected via Swinject).
    private let router: Router

    /// Garmin ConnectIQ shared instance for watch interactions.
    private let connectIQ = ConnectIQ.sharedInstance()

    /// Keeps references to watch apps (both watchface & data field) for each registered device.
    private var watchApps: [IQApp] = []

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

    /// Subject for debouncing watch state updates
    private let watchStateSubject = PassthroughSubject<Data, Never>()

    /// Current glucose units, either mg/dL or mmol/L, read from user settings.
    private var units: GlucoseUnits = .mgdL

    // MARK: - Debug Logging

    /// Enable/disable verbose debug logging for watch state preparation
    private let debugWatchState = true

    /// Enable/disable general Garmin debug logging (connections, sends, etc.)
    private let debugGarminEnabled = true

    /// Helper method for conditional Garmin debug logging.
    /// Logs messages only if debugGarminEnabled is true.
    /// - Parameter message: The debug message to log.
    private func debugGarmin(_ message: String) {
        guard debugGarminEnabled else { return }
        debug(.watchManager, message)
    }

    // MARK: - Deduplication

    /// Hash of last sent data to prevent duplicate broadcasts
    private var lastSentDataHash: Int?

    /// Hash of last prepared data to skip redundant preparation
    private var lastPreparedDataHash: Int?
    private var lastPreparedWatchState: [GarminWatchState]?

    // MARK: - Glucose/Determination Coordination

    /// Delay before sending glucose if determination hasn't arrived (seconds)
    /// Based on log analysis: avg delay ~5s, max ~24s, >15s occurs <1% of time
    private let glucoseFallbackDelay: TimeInterval = 20

    /// Pending glucose fallback task - cancelled if determination arrives first
    private var pendingGlucoseFallback: DispatchWorkItem?

    /// Queue for glucose fallback timer
    private let timerQueue = DispatchQueue(label: "BaseGarminManager.timerQueue", qos: .utility)

    /// Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)

    /// Publishes any changed CoreData objects that match our filters (e.g., OrefDetermination, GlucoseStored).
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?

    /// Additional local subscriptions (separate from `cancellables`) for CoreData events.
    private var subscriptions = Set<AnyCancellable>()

    /// Represents the context for background tasks in CoreData.
    let backgroundContext = CoreDataStack.shared.newTaskContext()

    /// Represents the main (view) context for CoreData, typically used on the main thread.
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    /// Array of Garmin `IQDevice` objects currently tracked.
    /// Changing this property triggers re-registration and updates persisted devices.
    private(set) var devices: [IQDevice] = [] {
        didSet {
            // Persist newly updated device list
            persistedDevices = devices.map(GarminDevice.init)
            // Re-register for events, app messages, etc.
            registerDevices(devices)
        }
    }

    // MARK: - Initialization

    /// Creates a new `BaseGarminManager`, injecting required services, restoring any persisted devices,
    /// and setting up watchers for data changes (e.g., glucose updates).
    /// - Parameter resolver: Swinject resolver for injecting dependencies like the Router.
    init(resolver: Resolver) {
        router = resolver.resolve(Router.self)!
        super.init()
        injectServices(resolver)

        connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)

        restoreDevices()

        subscribeToOpenFromGarminConnect()
        subscribeToWatchState()

        units = settingsManager.settings.units

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        // Glucose updates - start 20s fallback timer
        // When loop is working: determination arrives within ~5s, cancels timer, sends complete data
        // When loop is slow/failing: timer fires after 20s, sends glucose with stale loop data
        // This ensures watch gets fresh glucose even if loop doesn't complete
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                self?.handleGlucoseUpdate()
            }
            .store(in: &subscriptions)

        // IOB updates - also wait for determination like glucose does
        iobService.iobPublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                self?.handleIOBUpdate()
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    // MARK: - Settings Helpers

    /// Returns the currently configured Garmin watchface from settings
    private var currentWatchface: GarminWatchface {
        settingsManager.settings.garminSettings.watchface
    }

    /// Returns the currently configured Garmin datafield from settings
    private var currentDatafield: GarminDatafield {
        settingsManager.settings.garminSettings.datafield
    }

    /// Returns whether watchface data transmission is enabled in settings
    private var isWatchfaceDataEnabled: Bool {
        settingsManager.settings.garminSettings.isWatchfaceDataEnabled
    }

    /// SwissAlpine watchface uses historical glucose data (24 entries)
    /// Trio watchface only uses current reading
    private var needsHistoricalGlucoseData: Bool {
        currentWatchface == .swissalpine
    }

    /// Returns the display name for an app UUID (watchface or datafield).
    /// Use this for routine log messages where UUID adds noise.
    private func appDisplayName(for uuid: UUID) -> String {
        if uuid == currentWatchface.watchfaceUUID {
            return "watchface:\(currentWatchface.displayName)"
        } else if uuid == currentDatafield.datafieldUUID {
            return "datafield:\(currentDatafield.displayName)"
        } else {
            return "unknown app"
        }
    }

    /// Returns the detailed display name including UUID for an app.
    /// Use this for registration/connection messages and error scenarios where UUID identification is valuable.
    /// This helps with debugging when multiple versions/distributions exist (local, test, live builds).
    private func appDetailedName(for uuid: UUID) -> String {
        if uuid == currentWatchface.watchfaceUUID {
            return "watchface:\(currentWatchface.displayName) (\(uuid.uuidString))"
        } else if uuid == currentDatafield.datafieldUUID {
            return "datafield:\(currentDatafield.displayName) (\(uuid.uuidString))"
        } else {
            return "unknown app (\(uuid.uuidString))"
        }
    }

    // MARK: - Internal Setup / Handlers

    /// Sets up handlers for OrefDetermination and GlucoseStored entity changes in CoreData.
    /// When these change, we re-compute the Garmin watch state and send updates to the watch.
    private func registerHandlers() {
        // OrefDetermination changes - debounce at CoreData level
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.triggerWatchStateUpdate(triggeredBy: "Determination")
            }
            .store(in: &subscriptions)
    }

    /// Handles glucose updates with delayed fallback
    /// Waits up to 20 seconds for determination to arrive before sending glucose-only update
    /// This ensures we send complete data when loop is working, but still update watch if loop is slow/failing
    private func handleGlucoseUpdate() {
        guard !devices.isEmpty else { return }

        // Cancel any existing fallback timer
        pendingGlucoseFallback?.cancel()

        // Create new fallback task
        let fallback = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            Task {
                do {
                    self
                        .debugGarmin(
                            "Garmin: Glucose fallback timer fired (no determination in \(Int(self.glucoseFallbackDelay))s)"
                        )

                    let watchState = try await self.setupGarminWatchState(triggeredBy: "Glucose (fallback)")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.watchStateSubject.send(watchStateData)
                } catch {
                    debug(.watchManager, "Garmin: Error in glucose fallback: \(error)")
                }
            }
        }

        pendingGlucoseFallback = fallback
        timerQueue.asyncAfter(deadline: .now() + glucoseFallbackDelay, execute: fallback)

        debugGarmin("Garmin: Glucose received - waiting \(Int(glucoseFallbackDelay))s for determination")
    }

    /// Handles IOB updates with delayed fallback
    /// Also waits up to 20 seconds for determination to arrive, restarting the shared timer
    /// This prevents IOB changes from triggering premature watch updates before determination arrives
    private func handleIOBUpdate() {
        guard !devices.isEmpty else { return }

        // Cancel any existing fallback timer (restart the 20s window)
        pendingGlucoseFallback?.cancel()

        // Create new fallback task
        let fallback = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            Task {
                do {
                    self
                        .debugGarmin(
                            "Garmin: IOB fallback timer fired (no determination in \(Int(self.glucoseFallbackDelay))s)"
                        )

                    let watchState = try await self.setupGarminWatchState(triggeredBy: "IOB (fallback)")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.watchStateSubject.send(watchStateData)
                } catch {
                    debug(.watchManager, "Garmin: Error in IOB fallback: \(error)")
                }
            }
        }

        pendingGlucoseFallback = fallback
        timerQueue.asyncAfter(deadline: .now() + glucoseFallbackDelay, execute: fallback)

        debugGarmin("Garmin: IOB received - waiting \(Int(glucoseFallbackDelay))s for determination")
    }

    /// Triggers watch state preparation and sends to debounce subject
    /// If triggered by Determination, cancels pending glucose fallback timer
    private func triggerWatchStateUpdate(triggeredBy trigger: String) {
        guard !devices.isEmpty else { return }

        // If determination arrived, cancel the glucose fallback timer
        // Determination includes both fresh glucose and loop data
        if trigger == "Determination" {
            if pendingGlucoseFallback != nil {
                pendingGlucoseFallback?.cancel()
                pendingGlucoseFallback = nil
                debugGarmin("Garmin: Determination arrived - cancelled glucose fallback timer")
            }
        }

        Task {
            do {
                let watchState = try await setupGarminWatchState(triggeredBy: trigger)
                let watchStateData = try JSONEncoder().encode(watchState)
                watchStateSubject.send(watchStateData)
            } catch {
                debug(.watchManager, "Garmin: Error preparing watch state (\(trigger)): \(error)")
            }
        }
    }

    // MARK: - CoreData Fetch Methods

    /// Fetches recent glucose readings from CoreData, up to specified limit.
    /// - Parameter limit: Maximum number of glucose entries to fetch (default: 2)
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose(limit: Int = 2) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: limit
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Fetches the most recent temporary basal rate from CoreData pump history.
    /// - Returns: An array containing the NSManagedObjectID of the latest temp basal event, if any.
    private func fetchTempBasals() async throws -> [NSManagedObjectID] {
        let tempBasalPredicate = NSPredicate(format: "tempBasal != nil")
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.pumpHistoryLast24h,
            tempBasalPredicate
        ])

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: compoundPredicate,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return try await backgroundContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return pumpEvents.map(\.objectID)
        }
    }

    /// Fetches all determinations from the last 30 minutes (no fetch limit).
    /// Returns them sorted newest first, allowing us to find both enacted and suggested determinations.
    /// - Returns: An array of `NSManagedObjectID`s for all determinations in the 30-minute window.
    private func fetchDeterminations30Min() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 0 // No limit - get all determinations in 30min window
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [OrefDetermination] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    // MARK: - Watch State Setup

    /// Builds an array of GarminWatchState objects containing current glucose, trend, loop data, and historical readings.
    /// Historical data is included for watchfaces that support it (e.g., SwissAlpine).
    /// - Parameter triggeredBy: A string describing what triggered this update (for debugging/logging).
    /// - Returns: An array of `GarminWatchState` objects with the latest watch data.
    func setupGarminWatchState(triggeredBy: String = #function) async throws -> [GarminWatchState] {
        // Skip if no devices connected
        guard !devices.isEmpty else {
            return []
        }

        if debugWatchState {
            debug(.watchManager, "Garmin: Preparing watch state [Trigger: \(triggeredBy)]")
        }

        // Fetch glucose - SwissAlpine needs 24, Trio needs 2 (for delta calculation)
        let glucoseLimit = needsHistoricalGlucoseData ? 24 : 2
        let glucoseIds = try await fetchGlucose(limit: glucoseLimit)

        // Fetch all determinations from last 30 minutes (no limit)
        // This ensures we get both enacted and suggested determinations
        let allDeterminationIds = try await fetchDeterminations30Min()

        let tempBasalIds = try await fetchTempBasals()

        let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
            .getNSManagedObject(with: glucoseIds, context: backgroundContext)
        let allDeterminationObjects: [OrefDetermination] = try await CoreDataStack.shared
            .getNSManagedObject(with: allDeterminationIds, context: backgroundContext)
        let tempBasalObjects: [PumpEventStored] = try await CoreDataStack.shared
            .getNSManagedObject(with: tempBasalIds, context: backgroundContext)

        return await backgroundContext.perform {
            var watchStates: [GarminWatchState] = []

            let unitsHint = self.units == .mgdL ? "mgdl" : "mmol"

            // IOB with 1 decimal precision
            let iobValue = self.formatIOB(self.iobService.currentIOB ?? Decimal(0))

            // Find enacted determination for timestamp (when loop actually ran)
            // If no enacted determination exists in last 30 min, use a synthetic timestamp
            // of "31 minutes ago" so watchface can distinguish between:
            //   - nil = no data received yet (watch startup)
            //   - 31+ min old = loop is stale
            let enactedDetermination = allDeterminationObjects.first(where: { $0.enacted })
            let enactedTimestamp: Date = enactedDetermination?.timestamp ?? Date().addingTimeInterval(-31 * 60)

            // Extract data values from most recent determination (enacted or suggested)
            // Suggested sets provide latest calculations even if loop hasn't run yet
            var cobValue: Double?
            var sensRatioValue: Double?
            var isfValue: Int16?
            var eventualBGValue: Int16?

            if let latestDetermination = allDeterminationObjects.first {
                cobValue = Double(latestDetermination.cob)

                if let ratio = latestDetermination.autoISFratio {
                    sensRatioValue = Double(truncating: ratio)
                }

                if let isf = latestDetermination.insulinSensitivity {
                    isfValue = Int16(truncating: isf)
                }

                if let eventualBG = latestDetermination.eventualBG {
                    eventualBGValue = Int16(truncating: eventualBG)
                }
            }

            // TBR from temp basal or profile
            var tbrValue: Double?
            if let firstTempBasal = tempBasalObjects.first,
               let tempBasalData = firstTempBasal.tempBasal,
               let tempRate = tempBasalData.rate
            {
                tbrValue = Double(truncating: tempRate)
            } else {
                // Fall back to scheduled basal from profile
                let basalProfile = self.settingsManager.preferences.basalProfile as? [BasalProfileEntry] ?? []
                if !basalProfile.isEmpty {
                    let now = Date()
                    let calendar = Calendar.current
                    let currentTimeMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

                    for entry in basalProfile.reversed() {
                        if entry.minutes <= currentTimeMinutes {
                            tbrValue = Double(entry.rate)
                            break
                        }
                    }
                }
            }

            // Display configuration from settings
            let displayPrimaryChoice = self.settingsManager.settings.garminSettings.primaryAttributeChoice.rawValue
            let displaySecondaryChoice = self.settingsManager.settings.garminSettings.secondaryAttributeChoice.rawValue

            // Process glucose readings
            let entriesToSend = self.needsHistoricalGlucoseData ? glucoseObjects.count : 1

            for (index, glucose) in glucoseObjects.enumerated() {
                guard index < entriesToSend else { break }

                let glucoseValue = glucose.glucose

                var watchState = GarminWatchState()

                // Loop timestamp: Only use enacted determination timestamp (never glucose timestamp)
                // This shows when the loop actually executed, not when glucose was received
                if index == 0 {
                    watchState.date = UInt64(enactedTimestamp.timeIntervalSince1970 * 1000)
                } else {
                    watchState.date = glucose.date.map { UInt64($0.timeIntervalSince1970 * 1000) }
                }

                watchState.sgv = glucoseValue

                // Only add extended data for first entry
                if index == 0 {
                    watchState.direction = glucose.direction ?? "--"

                    // Delta calculation
                    if glucoseObjects.count > 1 {
                        watchState.delta = glucose.glucose - glucoseObjects[1].glucose
                    } else {
                        watchState.delta = 0
                    }

                    // Glucose timestamp: Used by watchface to determine if glucose is fresh
                    // Enables green coloring when: enacted loop is 6+ min old but glucose is <10 min old
                    watchState.glucoseDate = glucose.date.map { UInt64($0.timeIntervalSince1970 * 1000) }

                    watchState.units_hint = unitsHint
                    watchState.iob = iobValue
                    watchState.cob = cobValue
                    watchState.tbr = tbrValue
                    watchState.isf = isfValue
                    watchState.eventualBG = eventualBGValue
                    watchState.sensRatio = sensRatioValue
                    watchState.displayPrimaryAttributeChoice = displayPrimaryChoice
                    watchState.displaySecondaryAttributeChoice = displaySecondaryChoice
                }

                watchStates.append(watchState)
            }

            // Deduplicate: Check if data is unchanged from last preparation
            let currentHash = watchStates.hashValue
            if currentHash == self.lastPreparedDataHash {
                if self.debugWatchState {
                    debug(.watchManager, "Garmin: Skipping - data unchanged (hash: \(currentHash))")
                }
                return self.lastPreparedWatchState ?? watchStates
            }

            if self.debugWatchState {
                debug(
                    .watchManager,
                    "Garmin: Prepared \(watchStates.count) entries - sgv: \(watchStates.first?.sgv ?? 0), iob: \(watchStates.first?.iob ?? 0), cob: \(watchStates.first?.cob ?? 0), tbr: \(watchStates.first?.tbr ?? 0), eventualBG: \(watchStates.first?.eventualBG ?? 0), sensRatio: \(watchStates.first?.sensRatio ?? 0)"
                )
            }

            // Cache for deduplication
            self.lastPreparedDataHash = currentHash
            self.lastPreparedWatchState = watchStates

            return watchStates
        }
    }

    /// Formats IOB (Insulin On Board) value with 1 decimal precision for display.
    /// Prevents small values from rounding to zero by enforcing a minimum magnitude of 0.1.
    /// - Parameter value: The IOB value to format.
    /// - Returns: The formatted IOB value as a Double with 1 decimal place.
    private func formatIOB(_ value: Decimal) -> Double {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if doubleValue.magnitude < 0.1, doubleValue != 0 {
            return doubleValue > 0 ? 0.1 : -0.1
        }
        return (doubleValue * 10).rounded() / 10
    }

    // MARK: - Device & App Registration

    /// Registers the given devices for ConnectIQ events (device status changes) and watch app messages.
    /// It also creates and registers watch apps (watchface + data field) for each device.
    /// - Parameter devices: The devices to register.
    private func registerDevices(_ devices: [IQDevice]) {
        watchApps.removeAll()

        for device in devices {
            connectIQ?.register(forDeviceEvents: device, delegate: self)

            // Register watchface if enabled
            if isWatchfaceDataEnabled,
               let watchfaceUUID = currentWatchface.watchfaceUUID,
               let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
            {
                debugGarmin("Garmin: Registered \(appDetailedName(for: watchfaceUUID))")
                watchApps.append(watchfaceApp)
                connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
            } else if !isWatchfaceDataEnabled {
                debugGarmin("Garmin: Watchface data disabled - skipping watchface registration")
            }

            // Always register datafield (if configured)
            if let datafieldUUID = currentDatafield.datafieldUUID,
               let datafieldApp = IQApp(uuid: datafieldUUID, store: UUID(), device: device)
            {
                debugGarmin("Garmin: Registered \(appDetailedName(for: datafieldUUID))")
                watchApps.append(datafieldApp)
                connectIQ?.register(forAppMessages: datafieldApp, delegate: self)
            }
        }
    }

    /// Restores previously persisted devices from local storage into `devices`.
    private func restoreDevices() {
        devices = persistedDevices.map(\.iqDevice)
    }

    // MARK: - Simulator Support

    #if targetEnvironment(simulator)
        /// Mock IQDevice class for simulator testing
        /// Minimal implementation just for testing - no actual Garmin functionality
        class MockIQDevice: IQDevice {
            private let _uuid: UUID
            private let _friendlyName: String
            private let _modelName: String

            override var uuid: UUID { _uuid }
            override var friendlyName: String { _friendlyName }
            override var modelName: String { _modelName }
            var status: IQDeviceStatus { .connected }

            init(uuid: UUID, friendlyName: String, modelName: String) {
                _uuid = uuid
                _friendlyName = friendlyName
                _modelName = modelName
                super.init()
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) not implemented for mock device")
            }

            /// Shared simulated device UUID for consistency across the app
            static let simulatedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

            /// Creates the standard simulated Enduro 3 device
            static func createSimulated() -> MockIQDevice {
                MockIQDevice(
                    uuid: simulatedUUID,
                    friendlyName: "Enduro 3 Sim",
                    modelName: "Enduro 3"
                )
            }
        }
    #endif

    // MARK: - Combine Subscriptions

    /// Subscribes to the `.openFromGarminConnect` notification, parsing devices from the given URL
    /// and updating the device list accordingly.
    private func subscribeToOpenFromGarminConnect() {
        notificationCenter
            .publisher(for: .openFromGarminConnect)
            .sink { [weak self] notification in
                guard let self = self, let url = notification.object as? URL else { return }
                self.parseDevices(for: url)
            }
            .store(in: &cancellables)
    }

    /// Subscribes to watch state updates with debouncing
    private func subscribeToWatchState() {
        watchStateSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] data in
                self?.broadcastWatchStateData(data)
            }
            .store(in: &cancellables)
    }

    // MARK: - Parsing & Broadcasting

    /// Parses devices from a Garmin Connect URL and updates our `devices` property.
    /// - Parameter url: The URL provided by Garmin Connect containing device selection info.
    private func parseDevices(for url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        devices = parsed ?? []
        deviceSelectionPromise?(.success(devices))
        deviceSelectionPromise = nil
    }

    /// Broadcasts watch state data to all registered apps
    private func broadcastWatchStateData(_ data: Data) {
        // Deduplicate: Use stable content-based hash (sorted JSON bytes)
        let currentHash: Int
        if let sortedData = try? JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: data, options: []),
            options: [.sortedKeys]
        ) {
            currentHash = sortedData.base64EncodedString().hashValue
        } else {
            currentHash = data.count // Fallback
        }

        if currentHash == lastSentDataHash {
            debugGarmin("Garmin: Skipping broadcast - data unchanged")
            return
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            debug(.watchManager, "Garmin: Invalid JSON for watch-state data")
            return
        }

        watchApps.forEach { app in
            let appName = self.appDisplayName(for: app.uuid!)
            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    debug(.watchManager, "Garmin: App not installed: \(appName)")
                    return
                }
                self?.debugGarmin("Garmin: Sending to \(appName)")
                self?.sendMessage(jsonObject as Any, to: app, appName: appName)
            }
        }

        // Update last sent hash after initiating send
        lastSentDataHash = currentHash
    }

    // MARK: - GarminManager Conformance

    /// Prompts the user to select one or more Garmin devices, returning a publisher that emits
    /// the final array of selected devices once the user finishes selection.
    /// - Returns: An `AnyPublisher` emitting `[IQDevice]` on success, or empty array on error/timeout.
    func selectDevices() -> AnyPublisher<[IQDevice], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.success([]))
                return
            }
            self.deviceSelectionPromise = promise
            self.connectIQ?.showDeviceSelection()
        }
        .timeout(.seconds(120), scheduler: DispatchQueue.main)
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    /// Updates the manager's list of devices, typically after user selection or manual changes.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice]) {
        self.devices = devices
    }

    /// Sends the given watch state data to the debounce subject for eventual broadcast.
    /// - Parameter data: JSON-encoded data representing the latest watch state.
    func sendWatchStateData(_ data: Data) {
        watchStateSubject.send(data)
    }

    // MARK: - Helper: Sending Messages

    /// Sends a message to a given IQApp with optional progress and completion callbacks.
    /// - Parameters:
    ///   - msg: The data to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    ///   - appName: The display name of the app for logging.
    private func sendMessage(_ msg: Any, to app: IQApp, appName: String) {
        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in },
            completion: { result in
                switch result {
                case .success:
                    debug(.watchManager, "Garmin: Successfully sent to \(appName)")
                default:
                    debug(.watchManager, "Garmin: FAILED to send to \(appName)")
                }
            }
        )
    }
}

// MARK: - Extensions

extension BaseGarminManager: IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {
    // MARK: - IQUIOverrideDelegate

    /// Called if the Garmin Connect Mobile app is not installed or otherwise not available.
    /// Typically, you would show an alert or prompt the user to install the app from the store.
    func needsToInstallConnectMobile() {
        debug(.apsManager, "Garmin is not available")
        let messageCont = MessageContent(
            content: "The app Garmin Connect must be installed to use Trio.\nGo to the App Store to download it.",
            type: .warning,
            subtype: .misc,
            title: "Garmin is not available"
        )
        router.alertMessage.send(messageCont)
    }

    // MARK: - IQDeviceEventDelegate

    /// Called whenever the status of a registered Garmin device changes (e.g., connected, not found, etc.).
    /// - Parameters:
    ///   - device: The device whose status has changed.
    ///   - status: The new status for the device.
    func deviceStatusChanged(_: IQDevice, status: IQDeviceStatus) {
        // Always log connection state changes - critical for diagnosing SDK issues
        switch status {
        case .invalidDevice:
            debug(.watchManager, "Garmin: Device status -> invalidDevice")
        case .bluetoothNotReady:
            debug(.watchManager, "Garmin: Device status -> bluetoothNotReady")
        case .notFound:
            debug(.watchManager, "Garmin: Device status -> notFound")
        case .notConnected:
            debug(.watchManager, "Garmin: Device status -> notConnected")
        case .connected:
            debug(.watchManager, "Garmin: Device status -> connected")
        @unknown default:
            debug(.watchManager, "Garmin: Device status -> unknown(\(status.rawValue))")
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called when a message arrives from a Garmin watch app (watchface or data field).
    /// If the watch requests a "status" update, we call `setupGarminWatchState()` asynchronously
    /// and re-send the watch state data.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app sending the message.
    func receivedMessage(_ message: Any, from app: IQApp) {
        let appName = appDisplayName(for: app.uuid!)
        debugGarmin("Garmin: Received message '\(message)' from \(appName)")

        // If watch requests status update, send current data
        guard let statusString = message as? String, statusString == "status" else {
            return
        }

        Task {
            do {
                let watchState = try await setupGarminWatchState(triggeredBy: "WatchRequest")
                let watchStateData = try JSONEncoder().encode(watchState)
                sendWatchStateData(watchStateData)
            } catch {
                debug(.watchManager, "Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}

extension BaseGarminManager: SettingsObserver {
    /// Called whenever TrioSettings changes (e.g., user toggles mg/dL vs. mmol/L).
    /// - Parameter _: The updated TrioSettings instance.
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units

        // Re-register devices to pick up watchface/datafield changes
        if !devices.isEmpty {
            registerDevices(devices)
        }

        // Send updated state
        triggerWatchStateUpdate(triggeredBy: "Settings")
    }
}
