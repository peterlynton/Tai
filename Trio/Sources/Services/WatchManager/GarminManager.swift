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

    @Injected() private var storage: FileStorage!

    /// Persists the user's device list between app launches.
    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    /// Router for presenting alerts or navigation flows (injected via Swinject).
    private let router: Router

    /// Garmin ConnectIQ shared instance for watch interactions.
    private let connectIQ = ConnectIQ.sharedInstance()

    /// Keeps references to watch apps (both watchface & data field) for each registered device.
    private var watchApps: [IQApp] = []

    /// A subject that publishes watch-state dictionaries; watchers can throttle or debounce.
    private let watchStateSubject = PassthroughSubject<NSDictionary, Never>()

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

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
        subscribeToOpenFromGarminConnect()
        subscribeToWatchState()

        units = settingsManager.settings.units

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Skip if no Garmin devices are connected
                guard !self.devices.isEmpty else { return }
                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.sendWatchStateData(watchStateData)
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Error updating watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        iobService.iobPublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.sendWatchStateData(watchStateData)
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

    // MARK: - Internal Setup / Handlers

    /// Sets up handlers for OrefDetermination and GlucoseStored entity changes in CoreData.
    /// When these change, we re-compute the Garmin watch state and send updates to the watch.
    private func registerHandlers() {
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Skip if no Garmin devices are connected
                guard !self.devices.isEmpty else { return }
                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.sendWatchStateData(watchStateData)
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) failed to update watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        // Due to the batch insert, this only observes deletion of Glucose entries
        coreDataPublisher?
            .filteredByEntityName("GlucoseStored")
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Skip if no Garmin devices are connected
                guard !self.devices.isEmpty else { return }
                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.sendWatchStateData(watchStateData)
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) failed to update watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)
    }

    /// Fetches recent glucose readings from CoreData, up to 288 results.
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
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
            ascending: true,
            fetchLimit: 100
        )

        return try await backgroundContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // Filter only events that have a tempBasal
            return pumpEvents.filter { $0.tempBasal != nil }.map(\.objectID)
        }
    }

    /// Gets the scheduled basal rate for a specific time from the basal profile.
    /// - Parameters:
    ///   - time: The time to check
    ///   - profile: The basal profile entries
    /// - Returns: The scheduled basal rate at that time, or nil if not found
    private func getCurrentBasalRate(at time: Date, from profile: [BasalProfileEntry]) -> Decimal? {
        debug(.watchManager, "⌚️ getCurrentBasalRate - Profile entries: \(profile.count)")

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        guard let hours = timeComponents.hour, let minutes = timeComponents.minute else {
            debug(.watchManager, "⌚️ getCurrentBasalRate - Failed to get time components")
            return nil
        }

        let totalMinutes = hours * 60 + minutes
        debug(.watchManager, "⌚️ getCurrentBasalRate - Looking for time: \(hours):\(minutes) (total: \(totalMinutes) minutes)")

        // Special case: If profile has only one entry, it applies for full 24 hours
        if profile.count == 1 {
            debug(.watchManager, "⌚️ getCurrentBasalRate - Single entry profile, rate: \(profile[0].rate)")
            return profile[0].rate
        }

        // Log all profile entries
        for (index, entry) in profile.enumerated() {
            debug(.watchManager, "⌚️ Profile[\(index)]: start=\(entry.start), minutes=\(entry.minutes), rate=\(entry.rate)")
        }

        // Find the applicable basal rate using binary search (similar to TDDStorage)
        var left = 0
        var right = profile.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let entry = profile[mid]
            let nextMinutes = mid + 1 < profile.count ? profile[mid + 1].minutes : 1440

            debug(
                .watchManager,
                "⌚️ Binary search - checking entry[\(mid)]: \(entry.minutes) <= \(totalMinutes) < \(nextMinutes)?"
            )

            if totalMinutes >= entry.minutes, totalMinutes < nextMinutes {
                debug(.watchManager, "⌚️ getCurrentBasalRate - Found matching rate: \(entry.rate) at entry[\(mid)]")
                return entry.rate
            }

            if totalMinutes < entry.minutes {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }

        debug(.watchManager, "⌚️ getCurrentBasalRate - No matching rate found after binary search")
        return nil
    }

    /// Builds a `GarminWatchState` reflecting the latest glucose, trend, delta, eventual BG, ISF, IOB, and COB.
    /// - Returns: A `GarminWatchState` containing the most recent device- and therapy-related info.
    func setupGarminWatchState() async throws -> GarminWatchState {
        // Skip expensive calculations if no Garmin devices are connected (except in simulator)
        #if targetEnvironment(simulator)
            let skipDeviceCheck = true
        #else
            let skipDeviceCheck = false
        #endif

        guard !devices.isEmpty || skipDeviceCheck else {
            debug(.watchManager, "⌚️❌ Skipping setupGarminWatchState - No Garmin devices connected")
            return GarminWatchState()
        }

        do {
            // Get Glucose IDs
            let glucoseIds = try await fetchGlucose()

            // Fetch the latest OrefDetermination object if available
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.predicateFor30MinAgoForDetermination
            )

            // Fetch temp basal from pump history
            let tempBasalIds = try await fetchTempBasals()

            // Fetch basal profile to calculate TBR percentage
            let basalProfile = await storage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
            debug(.watchManager, "⌚️ Basal Profile fetched: \(basalProfile.count) entries")

            // Turn those IDs into live NSManagedObjects
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)
            let tempBasalObjects: [PumpEventStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: tempBasalIds, context: backgroundContext)

            // Perform logic on the background context
            return await backgroundContext.perform {
                var watchState = GarminWatchState()

                // Set units_hint based on current unit setting
                watchState.units_hint = self.units == .mgdL ? "mgdl" : "mmol"

                // Set noise to nil so it won't be included in JSON
                watchState.noise = nil

                // Set IOB from the IOB service (rounded to 1 decimal place)
                let iobValue = self.iobService.currentIOB ?? 0
                watchState.iob = Double(iobValue).roundedDouble(toPlaces: 1)

                // Calculate and set TBR (temporary basal rate percentage)
                if let lastTempBasal = tempBasalObjects.last?.tempBasal,
                   let tempRate = lastTempBasal.rate
                {
                    // Get current scheduled basal rate
                    let now = Date()
                    if let scheduledRate = self.getCurrentBasalRate(at: now, from: basalProfile) {
                        let tbrPercentage = (Double(truncating: tempRate) / Double(scheduledRate)) * 100
                        watchState.tbr = Int16(tbrPercentage.rounded())

                        debug(
                            .watchManager,
                            "⌚️ TBR Calculation - Temp Rate: \(Double(truncating: tempRate)) U/hr, Scheduled Rate: \(Double(scheduledRate)) U/hr, TBR: \(watchState.tbr ?? 0)%"
                        )
                    } else {
                        debug(.watchManager, "⌚️ TBR Calculation - Could not find scheduled basal rate")
                    }
                } else {
                    // No temp basal running, default to 100%
                    watchState.tbr = 100
                    debug(.watchManager, "⌚️ TBR Calculation - No temp basal running, defaulting to 100%")
                }

                // Process determination data (COB, date, eventualBG, ISF, sensRatio)
                if let latestDetermination = determinationObjects.first {
                    // Set date (timestamp in milliseconds)
                    if let timestamp = latestDetermination.timestamp, timestamp.timeIntervalSince1970 > 0 {
                        watchState.date = UInt64(timestamp.timeIntervalSince1970 * 1000)
                    }

                    // Set COB (rounded to 1 decimal place)
                    let cobValue = Double(latestDetermination.cob)
                    watchState.cob = cobValue.roundedDouble(toPlaces: 1)

                    // Set sensRatio based on settings (rounded to 2 decimal places)
                    let currentSetting = self.settingsManager.settings.garminWatchSetting
                    if currentSetting == .sensRatio {
                        let sensRatio = latestDetermination.autoISFratio ?? 1
                        let sensRatioValue = Double(truncating: sensRatio as NSNumber)
                        watchState.sensRatio = sensRatioValue.roundedDouble(toPlaces: 2)
                    }

                    // Set ISF and eventualBG (no unit conversion, raw values)
                    let insulinSensitivity = latestDetermination.insulinSensitivity ?? 0
                    let eventualBG = latestDetermination.eventualBG ?? 0

                    watchState.isf = Int16(truncating: insulinSensitivity)
                    watchState.eventualBG = Int16(truncating: eventualBG)
                }

                // If no glucose data is present, just return partial watch state
                guard let latestGlucose = glucoseObjects.first else {
                    return watchState
                }

                // Set SGV (sensor glucose value - raw value, no conversion)
                watchState.sgv = Int16(latestGlucose.glucose)

                // Set direction (trend)
                watchState.direction = latestGlucose.direction ?? "--"

                // Calculate delta if we have at least two readings (raw value, no conversion)
                if glucoseObjects.count >= 2 {
                    let deltaValue = glucoseObjects[0].glucose - glucoseObjects[1].glucose
                    watchState.delta = Int16(deltaValue)
                }

                // Log the complete watch state for review
                self.logWatchState(watchState)

                return watchState
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up Garmin watch state: \(error)"
            )
            throw error
        }
    }

    /// Logs the complete watch state for debugging
    private func logWatchState(_ watchState: GarminWatchState) {
        debug(
            .watchManager,
            """
            📱 GarminWatchState Summary:
            ├─ date: \(watchState.date?.description ?? "nil")
            ├─ sgv: \(watchState.sgv?.description ?? "nil")
            ├─ delta: \(watchState.delta?.description ?? "nil")
            ├─ direction: \(watchState.direction ?? "nil")
            ├─ units_hint: \(watchState.units_hint ?? "nil")
            ├─ noise: \(watchState.noise?.description ?? "nil")
            ├─ iob: \(watchState.iob?.description ?? "nil")
            ├─ tbr: \(watchState.tbr?.description ?? "nil")
            ├─ cob: \(watchState.cob?.description ?? "nil")
            ├─ eventualBG: \(watchState.eventualBG?.description ?? "nil")
            ├─ isf: \(watchState.isf?.description ?? "nil")
            └─ sensRatio: \(watchState.sensRatio?.description ?? "nil")
            """
        )
    }

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

            // Create a watchface app
            guard
                let watchfaceUUID = Config.watchfaceUUID,
                let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
            else {
                debug(.watchManager, "Garmin: Could not create watchface app for device \(device.uuid!))")
                continue
            }

            // Create a watch data field app
            guard
                let watchdataUUID = Config.watchdataUUID,
                let watchDataFieldApp = IQApp(uuid: watchdataUUID, store: UUID(), device: device)
            else {
                debug(.watchManager, "Garmin: Could not create data-field app for device \(device.uuid!)")
                continue
            }

            // Track both apps for potential messages
            watchApps.append(watchfaceApp)
            watchApps.append(watchDataFieldApp)

            // Register to receive app-messages from the watchface
            connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
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

    /// Subscribes to any watch-state dictionaries published via `watchStateSubject`, and throttles them
    /// so updates aren't sent too frequently. Each update triggers a broadcast to all watch apps.
    private func subscribeToWatchState() {
        watchStateSubject
            .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] state in
                self?.broadcastStateToWatchApps(state)
            }
            .store(in: &cancellables)
    }

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
    private func broadcastStateToWatchApps(_ state: NSDictionary) {
        watchApps.forEach { app in
            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    debug(.watchManager, "Garmin: App not installed on device: \(app.uuid!)")
                    return
                }
                debug(.watchManager, "Garmin: Sending watch-state to app \(app.uuid!)")
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
    /// - Parameter data: JSON-encoded data representing the latest watch state. If decoding fails,
    ///   the method logs an error and does nothing else.
    func sendWatchStateData(_ data: Data) {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = jsonObject as? NSDictionary
        else {
            debug(.watchManager, "Garmin: Invalid JSON for watch-state data")
            return
        }
        watchStateSubject.send(dict)
    }

    // MARK: - Helper: Sending Messages

    /// Sends a message to a given IQApp with optional progress and completion callbacks.
    /// - Parameters:
    ///   - msg: The dictionary to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    private func sendMessage(_ msg: NSDictionary, to app: IQApp) {
        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in
                // Optionally track progress here
            },
            completion: { result in
                switch result {
                case .success:
                    debug(.watchManager, "Garmin: Successfully sent message to \(app.uuid!)")
                default:
                    debug(.watchManager, "Garmin: Unknown result or failed to send message to \(app.uuid!)")
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
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        switch status {
        case .invalidDevice:
            debug(.watchManager, "Garmin: invalidDevice (\(device.uuid!))")
        case .bluetoothNotReady:
            debug(.watchManager, "Garmin: bluetoothNotReady (\(device.uuid!))")
        case .notFound:
            debug(.watchManager, "Garmin: notFound (\(device.uuid!))")
        case .notConnected:
            debug(.watchManager, "Garmin: notConnected (\(device.uuid!))")
        case .connected:
            debug(.watchManager, "Garmin: connected (\(device.uuid!))")
        @unknown default:
            debug(.watchManager, "Garmin: unknown state (\(device.uuid!))")
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
        debug(.watchManager, "Garmin: Received message \(message) from app \(app.uuid!)")

        Task {
            // Check if the message is literally the string "status"
            guard
                let statusString = message as? String,
                statusString == "status"
            else {
                return
            }

            do {
                // Fetch the latest watch state (async) and encode it to JSON data
                let watchState = try await self.setupGarminWatchState()
                let watchStateData = try JSONEncoder().encode(watchState)

                // Now send that JSON data to the watch
                sendWatchStateData(watchStateData)
            } catch {
                debug(.watchManager, "Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}

extension BaseGarminManager {
    // MARK: - Config

    /// Configuration struct containing watch app UUIDs for the Garmin watchface and data field.
    private enum Config {
        /// Example watchface UUID
        static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")

        /// Example data field UUID
        static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
    }
}

extension BaseGarminManager: SettingsObserver {
    /// Called whenever TrioSettings changes (e.g., user toggles mg/dL vs. mmol/L).
    /// - Parameter _: The updated TrioSettings instance.
    func settingsDidChange(_: TrioSettings) {
        // Update local units and re-send watch state
        units = settingsManager.settings.units

        Task {
            do {
                let watchState = try await setupGarminWatchState()
                let watchStateData = try JSONEncoder().encode(watchState)
                sendWatchStateData(watchStateData)
            } catch {
                debug(
                    .watchManager,
                    "\(DebuggingIdentifiers.failed) failed to send watch state data: \(error)"
                )
            }
        }
    }
}
