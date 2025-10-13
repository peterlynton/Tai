import Combine
import ConnectIQ
import SwiftUI

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var devices: [IQDevice] = []
        @Published var confirmBolusFaster = false
        @Published var garminWatchface: GarminWatchface = .trio
        @Published var garminDataType1: GarminDataType1 = .cob
        @Published var garminDataType2: GarminDataType2 = .tbr
        @Published var garminDisableWatchfaceData: Bool = false
        @Published var isDisableToggleLocked: Bool = false
        @Published var remainingCooldownSeconds: Int = 0

        private(set) var preferences = Preferences()
        private var cooldownTimer: Timer?
        private var cooldownEndTime: Date?

        override func subscribe() {
            preferences = provider.preferences
            units = settingsManager.settings.units
            subscribeSetting(\.garminDataType1, on: $garminDataType1) { garminDataType1 = $0 }
            subscribeSetting(\.garminDataType2, on: $garminDataType2) { garminDataType2 = $0 }
            subscribeSetting(\.garminWatchface, on: $garminWatchface) { garminWatchface = $0 }

            // Custom handling for garminDisableWatchfaceData to respect the cooldown
            subscribeSetting(\.garminDisableWatchfaceData, on: $garminDisableWatchfaceData) { [weak self] newValue in
                guard let self = self else { return }
                // Only update if not locked or if setting to true
                if !self.isDisableToggleLocked || newValue {
                    self.garminDisableWatchfaceData = newValue
                }
            }

            subscribeSetting(\.confirmBolusFaster, on: $confirmBolusFaster) { confirmBolusFaster = $0 }

            devices = garmin.devices
        }

        func selectGarminDevices() {
            garmin.selectDevices()
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.devices, on: self)
                .store(in: &lifetime)
        }

        func deleteGarminDevice() {
            garmin.updateDeviceList(devices)
        }

        func handleWatchfaceChange() {
            // When watchface changes, automatically disable data and start cooldown
            garminDisableWatchfaceData = true
            startCooldownTimer()
        }

        private func startCooldownTimer() {
            // Cancel any existing timer
            cooldownTimer?.invalidate()

            // Set the cooldown end time (30 seconds from now)
            cooldownEndTime = Date().addingTimeInterval(30)
            isDisableToggleLocked = true
            remainingCooldownSeconds = 30

            // Create a timer that fires every second
            cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }

                if let endTime = self.cooldownEndTime {
                    let remaining = Int(endTime.timeIntervalSinceNow)
                    if remaining <= 0 {
                        // Cooldown is over
                        self.isDisableToggleLocked = false
                        self.remainingCooldownSeconds = 0
                        self.cooldownTimer?.invalidate()
                        self.cooldownTimer = nil
                        self.cooldownEndTime = nil
                    } else {
                        // Update remaining seconds
                        self.remainingCooldownSeconds = remaining
                    }
                }
            }
        }

        deinit {
            cooldownTimer?.invalidate()
        }
    }
}

extension WatchConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
