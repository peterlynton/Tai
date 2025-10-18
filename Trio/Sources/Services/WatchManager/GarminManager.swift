import Combine
import ConnectIQ
import CoreData
import Foundation
import os // For thread-safe OSAllocatedUnfairLock
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
final class BaseGarminManager: NSObject, GarminManager, Injectable, @unchecked Sendable {
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

    /// Enable/disable debug logging for watch state (SwissAlpine/Trio data being sent)
    private let debugWatchState = true // Set to false to disable debug logging

    /// Enable/disable general Garmin debug logging (connections, settings, throttling, etc.)
    private let debugGarmin = true // Set to false to disable verbose Garmin logging

    /// Enable simulated Garmin device for Xcode Simulator testing
    /// When true, creates a fake Garmin device so you can test the workflow in Simulator
    #if targetEnvironment(simulator)
        private let enableSimulatedDevice = true // Set to false to disable simulated device
    #else
        private let enableSimulatedDevice = false // Never enable on real device
    #endif

    /// Helper method for conditional Garmin debug logging
    private func debugGarmin(_ message: String) {
        guard debugGarmin else { return }
        debug(.watchManager, message)
    }

    /// Track when immediate sends happen to cancel throttled ones
    private var lastImmediateSendTime: Date?
    private var throttledUpdatePending = false

    /// Cache last determination data to avoid CoreData staleness on immediate sends
    private var cachedDeterminationData: Data?

    /// Track when watchface was last changed to prevent caching stale format data
    private var lastWatchfaceChangeTime: Date?

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

    /// Current glucose units, either mg/dL or mmol/L, read from user settings.
    private var units: GlucoseUnits = .mgdL

    /// Track previous watchface settings
    private var previousWatchface: GarminWatchface = .trio
    private var previousDataType1: GarminDataType1 = .cob
    private var previousDataType2: GarminDataType2 = .tbr
    private var previousDisableWatchfaceData: Bool = false

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

        // Add simulated device for Xcode Simulator testing
        #if targetEnvironment(simulator)
            if enableSimulatedDevice, devices.isEmpty {
                addSimulatedGarminDevice()
            }
        #endif

        subscribeToOpenFromGarminConnect()
        subscribeToDeterminationThrottle()
        // Note: Old subscribeToWatchState() removed - using manual timer management for 30s

        units = settingsManager.settings.units

        previousWatchface = settingsManager.settings.garminWatchface
        previousDataType1 = settingsManager.settings.garminDataType1
        previousDataType2 = settingsManager.settings.garminDataType2
        previousDisableWatchfaceData = settingsManager.settings.garminDisableWatchfaceData

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        // Glucose updates - only send immediately if loop is stale (> 8 minutes)
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Skip if no Garmin devices are connected (unless in simulator)
                #if targetEnvironment(simulator)
                // Allow processing in simulator even without devices
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        // Check loop age
                        let determinationIds = try await self.determinationStorage.fetchLastDeterminationObjectID(
                            predicate: NSPredicate.enactedDetermination
                        )

                        let loopAge = await self.getLoopAge(determinationIds)

                        // Only send if loop is stale (> 8 minutes)
                        // Handle infinity case (no loop data available)
                        if loopAge.isFinite, loopAge > 480 { // 8 minutes in seconds
                            let loopAgeMinutes = Int(loopAge / 60)
                            let watchface = self.currentWatchface
                            if watchface == .swissalpine {
                                let watchStates = try await self.setupGarminSwissAlpineWatchState()
                                let watchStateData = try JSONEncoder().encode(watchStates)
                                self.currentSendTrigger = "Glucose-Stale-Loop (\(loopAgeMinutes)m)"
                                self.sendWatchStateDataImmediately(watchStateData)
                                self.lastImmediateSendTime = Date()
                            } else {
                                let watchState = try await self.setupGarminTrioWatchState()
                                let watchStateData = try JSONEncoder().encode(watchState)
                                self.currentSendTrigger = "Glucose-Stale-Loop (\(loopAgeMinutes)m)"
                                self.sendWatchStateDataImmediately(watchStateData)
                                self.lastImmediateSendTime = Date()
                            }
                            debug(
                                .watchManager,
                                "[\(self.formatTimeForLog())] Garmin: Glucose sent immediately - loop age > 8 min (\(loopAgeMinutes)m)"
                            )
                        } else {
                            if loopAge.isInfinite {
                                debug(
                                    .watchManager,
                                    "[\(self.formatTimeForLog())] Garmin: Glucose skipped - no loop data available (infinite loop age)"
                                )
                            } else {
                                debug(
                                    .watchManager,
                                    "[\(self.formatTimeForLog())] Garmin: Glucose skipped - loop age \(Int(loopAge / 60))m < 8m"
                                )
                            }
                        }
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Error checking loop age: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        // IOB updates - publish to determinationSubject (same pipeline as determinations)
        // Since IOB and determinations fire simultaneously, this prevents duplicates
        iobService.iobPublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Skip if no Garmin devices are connected (unless in simulator)
                #if targetEnvironment(simulator)
                // Allow processing in simulator even without devices
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        let watchface = self.currentWatchface
                        if watchface == .swissalpine {
                            let watchStates = try await self.setupGarminSwissAlpineWatchState()
                            let watchStateData = try JSONEncoder().encode(watchStates)
                            self.currentSendTrigger = "IOB-Update"
                            // Use same throttled pipeline as determinations
                            self.determinationSubject.send(watchStateData)
                        } else {
                            let watchState = try await self.setupGarminTrioWatchState()
                            let watchStateData = try JSONEncoder().encode(watchState)
                            self.currentSendTrigger = "IOB-Update"
                            // Use same throttled pipeline as determinations
                            self.determinationSubject.send(watchStateData)
                        }
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Error updating watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    // MARK: - Helper Properties

    /// Safely gets the current Garmin watchface setting
    private var currentWatchface: GarminWatchface {
        // Direct access since it's not optional
        settingsManager.settings.garminWatchface
    }

    /// Safely gets the current Garmin data type setting
    private var currentDataType1: GarminDataType1 {
        // Direct access since it's not optional
        settingsManager.settings.garminDataType1
    }

    /// Safely gets the current Garmin data type setting
    private var currentDataType2: GarminDataType2 {
        // Direct access since it's not optional
        settingsManager.settings.garminDataType2
    }

    /// Check if watchface data is disabled
    private var isWatchfaceDataDisabled: Bool {
        settingsManager.settings.garminDisableWatchfaceData
    }

    // MARK: - Internal Setup / Handlers

    /// Sets up handlers for OrefDetermination and GlucoseStored entity changes in CoreData.
    /// When these change, we re-compute the Garmin watch state and send updates to the watch.
    private func registerHandlers() {
        // OrefDetermination - publish to determinationSubject for Combine throttling
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Skip if no Garmin devices are connected (unless in simulator)
                #if targetEnvironment(simulator)
                // Allow processing in simulator even without devices
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        let watchface = self.currentWatchface
                        if watchface == .swissalpine {
                            let watchStates = try await self.setupGarminSwissAlpineWatchState()
                            let watchStateData = try JSONEncoder().encode(watchStates)
                            self.currentSendTrigger = "Determination"
                            // Publish to subject for throttling - Combine will dedupe
                            self.determinationSubject.send(watchStateData)
                        } else {
                            let watchState = try await self.setupGarminTrioWatchState()
                            let watchStateData = try JSONEncoder().encode(watchState)
                            self.currentSendTrigger = "Determination"
                            // Publish to subject for throttling - Combine will dedupe
                            self.determinationSubject.send(watchStateData)
                        }
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Failed to update watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        // Note: Glucose deletion handler removed - new glucose entries were incorrectly
        // triggering this handler, causing duplicate sends before determination updates.
        // Deletions are rare and will be handled by the next regular update cycle.
    }

    /// Helper to get loop age in seconds
    private func getLoopAge(_ determinationIds: [NSManagedObjectID]) async -> TimeInterval {
        guard !determinationIds.isEmpty else { return .infinity }

        do {
            let determinations: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)

            return await backgroundContext.perform {
                guard let latest = determinations.first,
                      let timestamp = latest.timestamp
                else {
                    return TimeInterval.infinity
                }

                return Date().timeIntervalSince(timestamp)
            }
        } catch {
            return .infinity
        }
    }

    /// 30-second throttle for Status/Settings updates
    private func sendWatchStateDataWith30sThrottle(_ data: Data) {
        // Store the latest data (always keep the newest)
        pendingThrottledData30s = data

        // If timer is already running, just update data - DON'T restart timer
        if throttleTimer30s?.isValid == true {
            debug(
                .watchManager,
                "[\(formatTimeForLog())] Garmin: 30s throttle timer running, data updated [Trigger: \(currentSendTrigger)]"
            )
            return
        }

        // Start new 30s timer ONLY if none exists
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.throttleTimer30s = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                guard let self = self,
                      let dataToSend = self.pendingThrottledData30s
                else {
                    return
                }

                // Check if immediate send (determination/IOB) happened while we were waiting
                if let lastImmediate = self.lastImmediateSendTime,
                   Date().timeIntervalSince(lastImmediate) < 5
                {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: 30s timer cancelled - recent determination/IOB send")
                    self.throttleTimer30s = nil
                    self.pendingThrottledData30s = nil
                    self.throttledUpdatePending = false
                    return
                }

                // Convert data to JSON object for sending
                guard let jsonObject = try? JSONSerialization.jsonObject(with: dataToSend, options: []) else {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: Invalid JSON in 30s throttled data")
                    self.throttleTimer30s = nil
                    self.pendingThrottledData30s = nil
                    self.throttledUpdatePending = false
                    return
                }

                debugGarmin("[\(self.formatTimeForLog())] Garmin: 30s timer fired - sending collected updates")
                self.broadcastStateToWatchApps(jsonObject as Any)

                // Clean up
                self.throttleTimer30s = nil
                self.pendingThrottledData30s = nil
                self.throttledUpdatePending = false
            }

            self.throttledUpdatePending = true
            debugGarmin("[\(self.formatTimeForLog())] Garmin: 30s throttle timer started")
        }
    }

    /// Fetches recent glucose readings from CoreData, up to specified limit.
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose(limit: Int = 5) async throws -> [NSManagedObjectID] {
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

    /// Fetches recent temp basal events from CoreData pump history.
    /// - Returns: An array of `NSManagedObjectID`s for pump events with temp basals.
    private func fetchTempBasals() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: false, // Most recent first
            fetchLimit: 5
        )

        return try await backgroundContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // Filter only events that have a tempBasal
            return pumpEvents.filter { $0.tempBasal != nil }.map(\.objectID)
        }
    }

    // MARK: - Debug Logging Methods

    private func logSwissAlpineWatchStates(_ watchStates: [GarminSwissAlpineWatchState]) {
        guard debugWatchState else { return }

        let watchface = currentWatchface
        let watchfaceUUID = watchface.watchfaceUUID?.uuidString ?? "Unknown"
        let datafieldUUID = watchface.datafieldUUID?.uuidString ?? "Unknown"

        do {
            let jsonData = try JSONEncoder().encode(watchStates)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let compactJson = jsonString.replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "  ", with: " ")

                // Show which apps will actually receive data
                let destinations: String
                if isWatchfaceDataDisabled {
                    destinations = "datafield \(datafieldUUID) only (watchface disabled)"
                } else {
                    destinations = "watchface \(watchfaceUUID) / datafield \(datafieldUUID)"
                }

                debug(
                    .watchManager,
                    "📱 SwissAlpine: Sending \(watchStates.count) entries to \(destinations): \(compactJson)"
                )
            }
        } catch {
            debug(.watchManager, "📱 SwissAlpine: Sending \(watchStates.count) entries (failed to encode for logging)")
        }
    }

    private func logTrioWatchState(_ watchState: GarminTrioWatchState) {
        guard debugWatchState else { return }

        let watchface = currentWatchface
        let watchfaceUUID = watchface.watchfaceUUID?.uuidString ?? "Unknown"
        let datafieldUUID = watchface.datafieldUUID?.uuidString ?? "Unknown"

        do {
            let jsonData = try JSONEncoder().encode(watchState)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let compactJson = jsonString.replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "  ", with: " ")

                // Show which apps will actually receive data
                let destinations: String
                if isWatchfaceDataDisabled {
                    destinations = "datafield \(datafieldUUID) only (watchface disabled)"
                } else {
                    destinations = "watchface \(watchfaceUUID) / datafield \(datafieldUUID)"
                }

                debug(
                    .watchManager,
                    "📱 Trio: Sending to \(destinations): \(compactJson)"
                )
            }
        } catch {
            debug(.watchManager, "📱 Trio: Failed to encode for logging")
        }
    }

    // MARK: - Trio Watchface State Setup

    /// Builds a Trio format GarminWatchState with string values and unit conversion
    func setupGarminTrioWatchState() async throws -> GarminTrioWatchState {
        // Skip expensive calculations if no Garmin devices are connected (except in simulator)
        #if targetEnvironment(simulator)
            let skipDeviceCheck = true
        #else
            let skipDeviceCheck = false
        #endif

        guard !devices.isEmpty || skipDeviceCheck else {
            debug(.watchManager, "⌚️⛔ Skipping setupGarminTrioWatchState - No Garmin devices connected")
            return GarminTrioWatchState()
        }

        do {
            // Get Glucose IDs
            let glucoseIds = try await fetchGlucose()

            // Fetch the latest OrefDetermination object if available
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.enactedDetermination
            )

            // Turn those IDs into live NSManagedObjects
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)

            // Perform logic on the background context
            return await backgroundContext.perform {
                var watchState = GarminTrioWatchState()

                /// Pull glucose, trendRaw, delta, lastLoopDateInterval, iob, cob, isf, and eventualBGRaw
                let iobValue = self.iobService.currentIOB ?? 0
                watchState.iob = self.iobFormatterWithOneFractionDigit(iobValue)

                if let latestDetermination = determinationObjects.first {
                    watchState.lastLoopDateInterval = latestDetermination.timestamp.map {
                        guard $0.timeIntervalSince1970 > 0 else { return 0 }
                        return UInt64($0.timeIntervalSince1970)
                    }

                    // COB with validation
                    let cobDouble = Double(latestDetermination.cob)
                    if cobDouble.isFinite, !cobDouble.isNaN, cobDouble >= 0 {
                        let cobNumber = NSNumber(value: latestDetermination.cob)
                        watchState.cob = Formatter.integerFormatter.string(from: cobNumber)
                    }

                    // Get the setting from settingsManager and only include sensRatio if setting is .sensRatio
                    let currentDataType1 = self.currentDataType1
                    if currentDataType1 == .sensRatio {
                        if let sensRatio = latestDetermination.autoISFratio {
                            let sensRatioDouble = Double(truncating: sensRatio as NSNumber)
                            if sensRatioDouble.isFinite, !sensRatioDouble.isNaN, sensRatioDouble > 0 {
                                watchState.sensRatio = sensRatio.description
                            } else {
                                // Invalid ratio - default to 1.0 (no adjustment)
                                watchState.sensRatio = "1.0"
                            }
                        } else {
                            // Nil ratio - default to 1.0 (no adjustment)
                            watchState.sensRatio = "1.0"
                        }
                    }

                    // EventualBG with validation (stored as Int16 mg/dL in CoreData)
                    if let eventualBG = latestDetermination.eventualBG as? Int16 {
                        if eventualBG >= 0, eventualBG <= 500 {
                            if self.units == .mgdL {
                                watchState.eventualBGRaw = eventualBG.description
                            } else {
                                let parsedEventualBG = Double(eventualBG).asMmolL
                                watchState.eventualBGRaw = parsedEventualBG.description
                            }
                        }
                    }

                    // ISF with validation (stored as Int16 mg/dL in CoreData)
                    if let insulinSensitivity = latestDetermination.insulinSensitivity as? Int16 {
                        if insulinSensitivity > 0, insulinSensitivity <= 300 {
                            if self.units == .mgdL {
                                watchState.isf = insulinSensitivity.description
                            } else {
                                let parsedIsf = Double(insulinSensitivity).asMmolL
                                watchState.isf = parsedIsf.description
                            }
                        }
                    }
                }

                // If no glucose data is present, just return partial watch state
                guard let latestGlucose = glucoseObjects.first else {
                    self.logTrioWatchState(watchState)
                    return watchState
                }

                // Format the current glucose reading
                if self.units == .mgdL {
                    watchState.glucose = "\(latestGlucose.glucose)"
                } else {
                    let mgdlValue = Decimal(latestGlucose.glucose)
                    let latestGlucoseValue = Double(truncating: mgdlValue.asMmolL as NSNumber)
                    watchState.glucose = "\(latestGlucoseValue)"
                }

                // Convert direction to a textual trend
                watchState.trendRaw = latestGlucose.direction ?? "--"

                // Calculate a glucose delta if we have at least two readings
                if glucoseObjects.count >= 2 {
                    var deltaValue = Decimal(glucoseObjects[0].glucose - glucoseObjects[1].glucose)

                    if self.units == .mmolL {
                        deltaValue = Double(truncating: deltaValue as NSNumber).asMmolL
                    }

                    let formattedDelta = deltaValue.description
                    watchState.delta = deltaValue < 0 ? "\(formattedDelta)" : "+\(formattedDelta)"
                }

                // Log the watch state before returning
                self.logTrioWatchState(watchState)

                return watchState
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up Garmin Trio watch state: \(error)"
            )
            throw error
        }
    }

    // MARK: - SwissAlpine Watchface State Setup

    /// Builds a SwissAlpine format GarminWatchState with numeric values for last 24 glucose readings
    func setupGarminSwissAlpineWatchState() async throws -> [GarminSwissAlpineWatchState] {
        // Skip expensive calculations if no Garmin devices are connected (except in simulator)
        #if targetEnvironment(simulator)
            let skipDeviceCheck = true
        #else
            let skipDeviceCheck = false
        #endif

        guard !devices.isEmpty || skipDeviceCheck else {
            debug(.watchManager, "⌚️⛔ Skipping setupGarminSwissAlpineWatchState - No Garmin devices connected")
            return []
        }

        do {
            // Get Glucose IDs - fetch up to 24 entries
            let glucoseIds = try await fetchGlucose(limit: 24)

            // Fetch the latest OrefDetermination object if available
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.enactedDetermination
            )

            // Fetch temp basal from pump history
            let tempBasalIds = try await fetchTempBasals()

            // Turn those IDs into live NSManagedObjects
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)
            let tempBasalObjects: [PumpEventStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: tempBasalIds, context: backgroundContext)

            // Perform logic on the background context
            return await backgroundContext.perform {
                var watchStates: [GarminSwissAlpineWatchState] = []

                // Get units hint
                let unitsHint = self.units == .mgdL ? "mgdl" : "mmol"

                // Calculate IOB once (same for all entries)
                let iobValue = Double(self.iobService.currentIOB ?? 0)

                // Calculate COB, sensRatio, ISF, eventualBG from determination
                var cobValue: Double?
                var sensRatioValue: Double?
                var isfValue: Int16?
                var eventualBGValue: Int16?

                if let latestDetermination = determinationObjects.first {
                    // Safe COB conversion
                    let cobDouble = Double(latestDetermination.cob)
                    if cobDouble.isFinite, !cobDouble.isNaN {
                        cobValue = cobDouble
                    } else {
                        cobValue = nil
                        if self.debugWatchState {
                            debug(.watchManager, "⌚️ SwissAlpine: COB is NaN or infinite, excluding from data")
                        }
                    }

                    // Only include sensRatio if data type setting is .sensRatio
                    let currentDataType1 = self.currentDataType1
                    if currentDataType1 == .sensRatio {
                        if let sensRatio = latestDetermination.autoISFratio {
                            let sensRatioDouble = Double(truncating: sensRatio as NSNumber)
                            if sensRatioDouble.isFinite, !sensRatioDouble.isNaN, sensRatioDouble > 0 {
                                sensRatioValue = sensRatioDouble
                            } else {
                                // Invalid ratio - default to 1.0 (no adjustment)
                                sensRatioValue = 1.0
                                if self.debugWatchState {
                                    debug(.watchManager, "⌚️ SwissAlpine: SensRatio is NaN or infinite, using default 1.0")
                                }
                            }
                        } else {
                            // Nil ratio - default to 1.0 (no adjustment)
                            sensRatioValue = 1.0
                        }
                    }

                    // ISF and eventualBG - stored as Int16 in CoreData (mg/dL values)
                    // For SwissAlpine: send raw mg/dL values (no unit conversion needed)
                    if let insulinSensitivity = latestDetermination.insulinSensitivity as? Int16 {
                        // Validate reasonable range for ISF (20-300 mg/dL per unit typical)
                        if insulinSensitivity > 0, insulinSensitivity <= 300 {
                            isfValue = insulinSensitivity
                        } else {
                            isfValue = nil
                            if self.debugWatchState {
                                debug(
                                    .watchManager,
                                    "⌚️ SwissAlpine: ISF out of range (\(insulinSensitivity)), excluding from data"
                                )
                            }
                        }
                    }

                    if let eventualBG = latestDetermination.eventualBG as? Int16 {
                        // Validate reasonable range for BG (0-500 mg/dL)
                        if eventualBG >= 0, eventualBG <= 500 {
                            eventualBGValue = eventualBG
                        } else {
                            eventualBGValue = nil
                            if self.debugWatchState {
                                debug(
                                    .watchManager,
                                    "⌚️ SwissAlpine: EventualBG out of range (\(eventualBG)), excluding from data"
                                )
                            }
                        }
                    }
                }

                let currentDataType2 = self.currentDataType2
                var adjustedEventualBGValue: Int16? = eventualBGValue
                if currentDataType2 == .tbr {
                    // When TBR is selected, set eventualBG to nil (exclude from JSON)
                    adjustedEventualBGValue = nil
                    if self.debugWatchState {
                        debug(.watchManager, "⌚️ SwissAlpine: TBR mode selected, excluding eventualBG from JSON")
                    }
                }

                // Get current basal rate directly from temp basal
                var tbrValue: Double?
                if let firstTempBasal = tempBasalObjects.first, // Most recent temp basal
                   let tempBasalData = firstTempBasal.tempBasal,
                   let tempRate = tempBasalData.rate
                {
                    // Send raw value without rounding
                    tbrValue = Double(truncating: tempRate)

                    if self.debugWatchState {
                        debug(.watchManager, "⌚️ Current basal rate: \(tbrValue ?? 0) U/hr from temp basal")
                    }
                } else {
                    // If no temp basal, get scheduled basal from profile
                    let basalProfile = self.settingsManager.preferences.basalProfile as? [BasalProfileEntry] ?? []
                    if !basalProfile.isEmpty {
                        let now = Date()
                        let calendar = Calendar.current
                        let currentTimeMinutes = calendar.component(.hour, from: now) * 60 + calendar
                            .component(.minute, from: now)

                        // Find the current basal rate from profile
                        var currentBasalRate: Double = 0
                        for entry in basalProfile.reversed() {
                            if entry.minutes <= currentTimeMinutes {
                                currentBasalRate = Double(entry.rate)
                                break
                            }
                        }

                        if currentBasalRate > 0 {
                            // Send raw value without rounding
                            tbrValue = currentBasalRate

                            if self.debugWatchState {
                                debug(.watchManager, "⌚️ Current scheduled basal rate: \(tbrValue ?? 0) U/hr from profile")
                            }
                        }
                    }
                }

                // Process each glucose reading (up to 24)
                for (index, glucose) in glucoseObjects.enumerated() {
                    var watchState = GarminSwissAlpineWatchState()

                    // Set timestamp for this glucose reading (in milliseconds)
                    // CRITICAL FIX: For index 0 (most recent), use determination timestamp (last loop time)
                    // For historical readings (index > 0), use glucose timestamp
                    if index == 0 {
                        // Use last loop time for the current reading (like Trio watchface does)
                        if let latestDetermination = determinationObjects.first,
                           let loopTimestamp = latestDetermination.timestamp
                        {
                            watchState.date = UInt64(loopTimestamp.timeIntervalSince1970 * 1000)
                        } else if let glucoseDate = glucose.date {
                            // Fallback to glucose date if no determination available
                            watchState.date = UInt64(glucoseDate.timeIntervalSince1970 * 1000)
                        }
                    } else {
                        // Historical readings use their actual glucose timestamp
                        if let glucoseDate = glucose.date {
                            watchState.date = UInt64(glucoseDate.timeIntervalSince1970 * 1000)
                        }
                    }

                    // Set SGV (already Int16, just validate it's reasonable)
                    let glucoseValue = glucose.glucose
                    // Glucose should be 0-500 range (0 = sensor error, 500+ = HIGH)
                    if glucoseValue >= 0, glucoseValue <= 500 {
                        watchState.sgv = glucoseValue // Already Int16, just assign
                    } else {
                        watchState.sgv = nil
                        if self.debugWatchState {
                            debug(.watchManager, "⌚️ SwissAlpine: Invalid glucose value (\(glucoseValue)), excluding from data")
                        }
                        continue // Skip this invalid glucose entry
                    }

                    // Set direction
                    watchState.direction = glucose.direction ?? "--"

                    // Calculate delta if we have a next reading
                    if index < glucoseObjects.count - 1 {
                        let deltaValue = glucose.glucose - glucoseObjects[index + 1].glucose
                        // Delta is already Int16 (Int16 - Int16 = Int16), just validate reasonable range
                        if deltaValue >= -100, deltaValue <= 100 {
                            watchState.delta = deltaValue // Already Int16, just assign
                        } else {
                            watchState.delta = nil
                            if self.debugWatchState {
                                debug(.watchManager, "⌚️ SwissAlpine: Delta out of range (\(deltaValue)), excluding from data")
                            }
                        }
                    } else {
                        // Last entry has no delta
                        watchState.delta = nil
                    }

                    // Only include extended data for the most recent reading (index 0)
                    if index == 0 {
                        watchState.units_hint = unitsHint
                        watchState.iob = iobValue
                        watchState.cob = cobValue
                        watchState.tbr = tbrValue // Current basal rate in U/hr
                        watchState.isf = isfValue
                        watchState.eventualBG = adjustedEventualBGValue
                        watchState.sensRatio = sensRatioValue
                        // noise is left as nil (will be excluded from JSON)
                    }

                    watchStates.append(watchState)
                }

                // Log the watch states if debugging is enabled
                if self.debugWatchState {
                    self.logSwissAlpineWatchStates(watchStates)
                }

                return watchStates
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up Garmin SwissAlpine watch state: \(error)"
            )
            throw error
        }
    }

    // MARK: - Helper Methods

    /// Formats IOB value with one fraction digit
    func iobFormatterWithOneFractionDigit(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1

        // Prevent small values from rounding to 0 by enforcing a minimum threshold
        if value.magnitude < 0.1, value != 0 {
            return value > 0 ? "0.1" : "-0.1"
        }

        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// Formats a Date to HH:mm:ss string for logging
    private func formatTimeForLog(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Simulated Device (for Xcode Simulator Testing)

    #if targetEnvironment(simulator)
        /// Creates a simulated Garmin device for testing in Xcode Simulator
        /// This allows testing the full workflow without a real Garmin watch
        private func addSimulatedGarminDevice() {
            guard enableSimulatedDevice else { return }

            // Create a mock IQDevice for simulator testing
            // Using a fixed UUID so it persists across app launches
            let simulatedUUID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

            // Note: IQDevice initializer may vary - adjust as needed
            // This is a placeholder that may need adjustment based on actual IQDevice API
            if let simulatedDevice = createMockIQDevice(
                uuid: simulatedUUID,
                friendlyName: "Simulated Garmin Watch",
                modelName: "Enduro 3 (Simulator)"
            ) {
                devices = [simulatedDevice]
                debugGarmin("📱 Simulator: Added simulated Garmin device for testing")
                debugGarmin("📱 Simulator: Device UUID: \(simulatedUUID)")
                debugGarmin("📱 Simulator: Use this to test determination/IOB throttling, settings changes, etc.")
            } else {
                debugGarmin("⚠️ Simulator: Could not create simulated device (IQDevice API may have changed)")
            }
        }

        /// Helper to create a mock IQDevice - implementation depends on IQDevice's actual initializers
        private func createMockIQDevice(uuid _: UUID, friendlyName _: String, modelName _: String) -> IQDevice? {
            // Note: This is a placeholder - the actual IQDevice creation may require
            // different parameters or may not be possible to mock directly.
            // You may need to adjust this based on ConnectIQ SDK documentation.

            // If IQDevice can't be created directly, you might need to:
            // 1. Use a real device connection once and persist it
            // 2. Or modify IQDevice to support test initialization
            // 3. Or create a protocol and use dependency injection

            // For now, returning nil as IQDevice likely requires Garmin SDK initialization
            // Users should connect a real device once, then it will be persisted
            nil
        }
    #endif

    // MARK: - Device & App Registration

    /// Registers the given devices for ConnectIQ events (device status changes) and watch app messages.
    /// It also creates and registers watch apps (watchface + data field) for each device.
    /// - Parameter devices: The devices to register.
    private func registerDevices(_ devices: [IQDevice]) {
        // Clear out old references
        watchApps.removeAll()

        for device in devices {
            // Listen for device-level status changes
            connectIQ?.register(forDeviceEvents: device, delegate: self)

            // Get current watchface setting
            let watchface = currentWatchface

            // Create a watchface app using the UUID from the enum
            // Only register watchface if data is NOT disabled
            if !isWatchfaceDataDisabled {
                if let watchfaceUUID = watchface.watchfaceUUID,
                   let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
                {
                    debug(
                        .watchManager,
                        "Garmin: Registering \(watchface.displayName) watchface (UUID: \(watchfaceUUID)) for device \(device.friendlyName ?? "Unknown")"
                    )

                    // Track watchface app
                    watchApps.append(watchfaceApp)

                    // Register to receive app-messages from the watchface
                    connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
                } else {
                    debug(
                        .watchManager,
                        "Garmin: Could not create \(watchface.displayName) watchface app for device \(device.uuid!)"
                    )
                }
            } else {
                debugGarmin("Garmin: Skipping watchface registration - data disabled")
            }

            // ALWAYS create and register data field app (not affected by disable setting)
            if let datafieldUUID = watchface.datafieldUUID,
               let watchDataFieldApp = IQApp(uuid: datafieldUUID, store: UUID(), device: device)
            {
                debug(
                    .watchManager,
                    "Garmin: Registering data field (UUID: \(datafieldUUID)) for device \(device.friendlyName ?? "Unknown")"
                )

                // Track datafield app
                watchApps.append(watchDataFieldApp)

                // Register to receive app-messages from the datafield
                connectIQ?.register(forAppMessages: watchDataFieldApp, delegate: self)
            } else {
                debugGarmin("Garmin: Could not create data-field app for device \(device.uuid!)")
            }
        }
    }

    /// Restores previously persisted devices from local storage into `devices`.
    private func restoreDevices() {
        devices = persistedDevices.map(\.iqDevice)
    }

    // MARK: - Combine Subscriptions

    /// Subscribes to the `.openFromGarminConnect` notification, parsing devices from the given URL
    /// and updating the device list accordingly.
    private func subscribeToOpenFromGarminConnect() {
        notificationCenter
            .publisher(for: .openFromGarminConnect)
            .sink { [weak self] notification in
                guard
                    let self = self,
                    let url = notification.object as? URL
                else { return }

                self.parseDevices(for: url)
            }
            .store(in: &cancellables)
    }

    /// Subscribes to determination updates with 20s throttle (first goes through, rest discarded)
    /// Also handles IOB updates since they fire simultaneously with determinations
    private func subscribeToDeterminationThrottle() {
        determinationSubject
            .throttle(for: .seconds(20), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] data in
                guard let self = self else { return }

                // Only cache if no recent watchface change (within last 25 seconds)
                // This prevents caching stale format data that was in the throttle pipeline
                let shouldCache: Bool
                if let lastChange = self.lastWatchfaceChangeTime {
                    let timeSinceChange = Date().timeIntervalSince(lastChange)
                    shouldCache = timeSinceChange > 25 // Throttle is 20s, add 5s buffer
                    if !shouldCache {
                        debugGarmin(
                            "[\(self.formatTimeForLog())] Garmin: Not caching - data may be from before watchface change (\(Int(timeSinceChange))s ago)"
                        )
                    }
                } else {
                    shouldCache = true // No recent watchface change
                }

                if shouldCache {
                    self.cachedDeterminationData = data
                }

                self.lastImmediateSendTime = Date() // Mark for any 30s timers (status requests, settings)

                // Convert data to JSON object for sending
                guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: Invalid JSON in determination data")
                    return
                }

                debugGarmin("[\(self.formatTimeForLog())] Garmin: Sending determination/IOB (20s throttle passed)")
                self.broadcastStateToWatchApps(jsonObject as Any)
            }
            .store(in: &cancellables)
    }

    // Note: Old subscribeToWatchState() removed - using manual timer management instead

    // MARK: - Parsing & Broadcasting

    /// Parses devices from a Garmin Connect URL and updates our `devices` property.
    /// - Parameter url: The URL provided by Garmin Connect containing device selection info.
    private func parseDevices(for url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        devices = parsed ?? []

        // Fulfill any pending promise in case this is in response to `selectDevices()`.
        deviceSelectionPromise?(.success(devices))
        deviceSelectionPromise = nil
    }

    /// Sends the given state dictionary to all known watch apps (watchface & data field) by checking
    /// if each app is installed and then sending messages asynchronously.
    /// - Parameter state: The dictionary representing the watch state to be broadcast.
    private func broadcastStateToWatchApps(_ state: Any) {
        // Log connection health status if we have failures
        if failedSendCount > 0 {
            let timeSinceLastSuccess = lastSuccessfulSendTime.map { Date().timeIntervalSince($0) } ?? .infinity
            debug(
                .watchManager,
                "[\(formatTimeForLog())] Garmin: Broadcasting with \(failedSendCount) recent failures. Last success: \(Int(timeSinceLastSuccess))s ago"
            )
        }

        watchApps.forEach { app in
            // Check if this is the watchface app
            let watchface = currentWatchface
            let isWatchfaceApp = app.uuid == watchface.watchfaceUUID

            // Skip broadcasting to watchface if data is disabled
            if isWatchfaceDataDisabled, isWatchfaceApp {
                debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, skipping broadcast to watchface")
                return
            }

            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    self?.debugGarmin("[\(self?.formatTimeForLog() ?? "")] Garmin: App not installed on device: \(app.uuid!)")
                    return
                }
                debug(.watchManager, "[\(self?.formatTimeForLog() ?? "")] Garmin: Sending watch-state to app \(app.uuid!)")
                self?.sendMessage(state, to: app)
            }
        }
    }

    // MARK: - GarminManager Conformance

    /// Prompts the user to select one or more Garmin devices, returning a publisher that emits
    /// the final array of selected devices once the user finishes selection.
    /// - Returns: An `AnyPublisher` emitting `[IQDevice]` on success, or empty array on error/timeout.
    func selectDevices() -> AnyPublisher<[IQDevice], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                // If self is gone, just resolve with an empty array
                promise(.success([]))
                return
            }
            // Store the promise so we can fulfill it when the user selects devices
            self.deviceSelectionPromise = promise

            // Show Garmin's default device selection UI
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

    /// Converts the given JSON data into an NSDictionary and sends it to all known watch apps.
    /// Only used for throttled updates (IOB, DataType changes)
    /// - Parameter data: JSON-encoded data representing the latest watch state.
    func sendWatchStateData(_ data: Data) {
        sendWatchStateDataWith30sThrottle(data)
    }

    /// Sends watch state data immediately, bypassing the 30-second throttling
    /// Used for critical updates like determinations, glucose deletions, and status requests
    private func sendWatchStateDataImmediately(_ data: Data) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            debugGarmin("Garmin: Invalid JSON for immediate watch-state data")
            return
        }

        if debugWatchState {
            if let dict = jsonObject as? NSDictionary {
                debugGarmin("Garmin: Immediately sending watch state dictionary with \(dict.count) fields (no throttle)")
            } else if let array = jsonObject as? NSArray {
                debugGarmin("Garmin: Immediately sending watch state array with \(array.count) entries (no throttle)")
            }
        }

        // Directly broadcast without going through the throttled subject
        broadcastStateToWatchApps(jsonObject)
    }

    // Track current send trigger for debugging (thread-safe)
    private let triggerLock = OSAllocatedUnfairLock()
    private var _currentSendTrigger: String = "Unknown"

    private var currentSendTrigger: String {
        get { triggerLock.withLock { _currentSendTrigger } }
        set { triggerLock.withLock { _currentSendTrigger = newValue } }
    }

    // Track connection health
    private var lastSuccessfulSendTime: Date?
    private var failedSendCount = 0
    private var connectionAlertShown = false

    // Manual throttle for 30s updates
    private var throttleTimer30s: Timer?
    private var pendingThrottledData30s: Data?

    // Combine subject for 10s throttled Determinations
    private let determinationSubject = PassthroughSubject<Data, Never>()

    // MARK: - Helper: Sending Messages

    /// Sends a message to a given IQApp with optional progress and completion callbacks.
    /// - Parameters:
    ///   - msg: The dictionary to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    private func sendMessage(_ msg: Any, to app: IQApp) {
        // Check if this is the watchface app
        let watchface = currentWatchface
        let isWatchfaceApp = app.uuid == watchface.watchfaceUUID

        // Skip sending if data is disabled AND this is the watchface app
        if isWatchfaceDataDisabled, isWatchfaceApp {
            debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, not sending message to watchface")
            return
        }

        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in
                // Optionally track progress here
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.failedSendCount = 0
                    self.lastSuccessfulSendTime = Date()
                    self.connectionAlertShown = false // Reset alert flag on success
                    debug(
                        .watchManager,
                        "[\(self.formatTimeForLog())] Garmin: Successfully sent message to \(app.uuid!) [Trigger: \(self.currentSendTrigger)]"
                    )
                default:
                    self.failedSendCount += 1
                    debug(
                        .watchManager,
                        "[\(self.formatTimeForLog())] Garmin: FAILED to send to \(app.uuid!) [Trigger: \(self.currentSendTrigger)] (Failure #\(self.failedSendCount))"
                    )

                    // After 3 consecutive failures, show alert (but only once)
                    if self.failedSendCount >= 3, !self.connectionAlertShown {
                        self.showConnectionLostAlert()
                        self.connectionAlertShown = true
                    }
                }
            }
        )
    }

    /// Shows an alert when Garmin connection is lost
    private func showConnectionLostAlert() {
        let messageCont = MessageContent(
            content: "Unable to send data to Garmin device.\n\nPlease check:\n• Bluetooth is enabled\n• Watch is in range\n• Watch is powered on\n• Watchface/Datafield is installed",
            type: .warning,
            subtype: .misc,
            title: "Garmin Connection Lost"
        )
        router.alertMessage.send(messageCont)

        debugGarmin("[\(formatTimeForLog())] Garmin: Connection lost alert shown to user")
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
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        switch status {
        case .invalidDevice:
            debugGarmin("[\(formatTimeForLog())] Garmin: invalidDevice (\(device.uuid!))")
        case .bluetoothNotReady:
            debugGarmin("[\(formatTimeForLog())] Garmin: bluetoothNotReady (\(device.uuid!))")
        case .notFound:
            debugGarmin("[\(formatTimeForLog())] Garmin: notFound (\(device.uuid!))")
        case .notConnected:
            debugGarmin("[\(formatTimeForLog())] Garmin: notConnected (\(device.uuid!))")
        case .connected:
            debugGarmin("[\(formatTimeForLog())] Garmin: connected (\(device.uuid!))")
        @unknown default:
            debugGarmin("[\(formatTimeForLog())] Garmin: unknown state (\(device.uuid!))")
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called when a message arrives from a Garmin watch app (watchface or data field).
    /// If the watch requests a "status" update, we call appropriate setup method
    /// based on watchface setting and re-send the watch state data.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app sending the message.
    func receivedMessage(_ message: Any, from app: IQApp) {
        debugGarmin("[\(formatTimeForLog())] Garmin: Received message \(message) from app \(app.uuid!)")

        // Check if this message is from the watchface (not datafield)
        let watchface = currentWatchface
        let isFromWatchface = app.uuid == watchface.watchfaceUUID

        // If data is disabled AND the message is from the watchface, ignore it
        if isWatchfaceDataDisabled, isFromWatchface {
            debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, ignoring message from watchface")
            return
        }

        Task {
            // Check if the message is literally the string "status"
            guard
                let statusString = message as? String,
                statusString == "status"
            else {
                return
            }

            // Check if we sent an update very recently (within last 10 seconds)
            if let lastImmediate = self.lastImmediateSendTime,
               Date().timeIntervalSince(lastImmediate) < 10
            {
                debug(
                    .watchManager,
                    "[\(self.formatTimeForLog())] Garmin: Status request ignored - just sent update \(Int(Date().timeIntervalSince(lastImmediate)))s ago"
                )
                return
            }

            // Use throttled send for status requests to avoid spam
            do {
                if watchface == .swissalpine {
                    let watchStates = try await self.setupGarminSwissAlpineWatchState()
                    let watchStateData = try JSONEncoder().encode(watchStates)
                    self.currentSendTrigger = "Status-Request"
                    // Use 30s throttle to prevent status request spam
                    self.sendWatchStateDataWith30sThrottle(watchStateData)
                } else {
                    let watchState = try await self.setupGarminTrioWatchState()
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.currentSendTrigger = "Status-Request"
                    // Use 30s throttle to prevent status request spam
                    self.sendWatchStateDataWith30sThrottle(watchStateData)
                }
                debugGarmin("[\(self.formatTimeForLog())] Garmin: Status request queued for throttled send")
            } catch {
                debugGarmin("[\(self.formatTimeForLog())] Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}

// MARK: - SettingsObserver

extension BaseGarminManager: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        debug(.watchManager, "🔔 settingsDidChange triggered")

        // Check what changed by comparing with stored previous values
        let watchfaceChanged = previousWatchface != settings.garminWatchface
        let dataType1Changed = previousDataType1 != settings.garminDataType1
        let dataType2Changed = previousDataType2 != settings.garminDataType2
        let unitsChanged = units != settings.units
        let disabledChanged = previousDisableWatchfaceData != settings.garminDisableWatchfaceData

        // Debug what changed BEFORE updating stored values
        if watchfaceChanged {
            debug(
                .watchManager,
                "Garmin: Watchface changed from \(previousWatchface.displayName) to \(settings.garminWatchface.displayName). Re-registering devices only, no data update"
            )
        }

        if dataType1Changed {
            debug(
                .watchManager,
                "Garmin: Data type 1 changed from \(previousDataType1.displayName) to \(settings.garminDataType1.displayName)"
            )
        }

        if dataType2Changed {
            debug(
                .watchManager,
                "Garmin: Data type 2 changed from \(previousDataType2.displayName) to \(settings.garminDataType2.displayName)"
            )
        }

        if unitsChanged {
            debugGarmin("Garmin: Units changed - immediate update required")
        }

        if disabledChanged {
            debug(
                .watchManager,
                "Garmin: Watchface data disabled changed from \(previousDisableWatchfaceData) to \(settings.garminDisableWatchfaceData)"
            )

            // Re-register devices to add/remove watchface app based on disabled state
            registerDevices(devices)

            if settings.garminDisableWatchfaceData {
                debugGarmin("Garmin: Watchface app unregistered, datafield continues")
            } else {
                debugGarmin("Garmin: Watchface app re-registered - sending immediate update")
            }
        }

        // NOW update stored values AFTER logging the changes
        units = settings.units
        previousWatchface = settings.garminWatchface
        previousDataType1 = settings.garminDataType1
        previousDataType2 = settings.garminDataType2
        previousDisableWatchfaceData = settings.garminDisableWatchfaceData

        // Handle watchface change - ONLY re-register, NO data send
        if watchfaceChanged {
            // Clear cached determination data - different watchfaces have different formats
            cachedDeterminationData = nil
            lastWatchfaceChangeTime = Date()
            debugGarmin("Garmin: Cleared cached determination data due to watchface change")

            registerDevices(devices)
            debugGarmin("Garmin: Re-registered devices for new watchface UUID")
            // NO data send here - wait for watch to request or next regular update
        }

        // Determine which type of update is needed (if any)
        let needsImmediateUpdate = (
            unitsChanged ||
                (disabledChanged && !settings.garminDisableWatchfaceData)
        ) &&
            !watchfaceChanged // Don't send if only watchface changed

        let needsThrottledUpdate = (dataType1Changed || dataType2Changed) &&
            !watchfaceChanged // Don't send if only watchface changed

        // Send immediate update for critical changes
        if needsImmediateUpdate {
            Task {
                do {
                    // Try to use cached determination data first to avoid CoreData staleness
                    if let cachedData = self.cachedDeterminationData {
                        self.currentSendTrigger = "Settings-Units/Re-enable"
                        debugGarmin("Garmin: Using cached determination data for immediate settings update")
                        self.sendWatchStateDataImmediately(cachedData)
                        self.lastImmediateSendTime = Date()
                        debugGarmin("Garmin: Immediate update sent for units/re-enable change (from cache)")
                    } else {
                        // Fallback to fresh query if no cache available
                        if settings.garminWatchface == .swissalpine {
                            let watchStates = try await self.setupGarminSwissAlpineWatchState()
                            let watchStateData = try JSONEncoder().encode(watchStates)
                            self.currentSendTrigger = "Settings-Units/Re-enable"
                            self.sendWatchStateDataImmediately(watchStateData)
                            self.lastImmediateSendTime = Date()
                            debugGarmin("Garmin: Immediate update sent for units/re-enable change (fresh query)")
                        } else { // Must be .trio
                            let watchState = try await self.setupGarminTrioWatchState()
                            let watchStateData = try JSONEncoder().encode(watchState)
                            self.currentSendTrigger = "Settings-Units/Re-enable"
                            self.sendWatchStateDataImmediately(watchStateData)
                            self.lastImmediateSendTime = Date()
                            debugGarmin("Garmin: Immediate update sent for units/re-enable change (fresh query)")
                        }
                    }
                } catch {
                    debug(
                        .watchManager,
                        "\(DebuggingIdentifiers.failed) Failed to send immediate update after settings change: \(error)"
                    )
                }
            }
        }
        // Send throttled update for data type changes
        else if needsThrottledUpdate {
            Task {
                do {
                    if settings.garminWatchface == .swissalpine {
                        let watchStates = try await self.setupGarminSwissAlpineWatchState()
                        let watchStateData = try JSONEncoder().encode(watchStates)
                        self.currentSendTrigger = "Settings-DataType"
                        // DataType changes use 30s throttling
                        self.sendWatchStateDataWith30sThrottle(watchStateData)
                        debugGarmin("Garmin: Throttled update queued for data type change")
                    } else { // Must be .trio
                        let watchState = try await self.setupGarminTrioWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.currentSendTrigger = "Settings-DataType"
                        // DataType changes use 30s throttling
                        self.sendWatchStateDataWith30sThrottle(watchStateData)
                        debugGarmin("Garmin: Throttled update queued for data type change")
                    }
                } catch {
                    debug(
                        .watchManager,
                        "\(DebuggingIdentifiers.failed) Failed to send throttled update after settings change: \(error)"
                    )
                }
            }
        }
    }
}
