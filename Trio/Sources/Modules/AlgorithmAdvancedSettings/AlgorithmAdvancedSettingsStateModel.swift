import Combine
import Observation
import SwiftUI

extension AlgorithmAdvancedSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Injected() var nightscout: NightscoutManager!

        var units: GlucoseUnits = .mgdL

        @Published var maxDailySafetyMultiplier: Decimal = 3
        @Published var currentBasalSafetyMultiplier: Decimal = 4
        @Published var skipNeutralTemps: Bool = false
        @Published var unsuspendIfNoTemp: Bool = false
        @Published var suspendZerosIOB: Bool = false
        @Published var min5mCarbimpact: Decimal = 8
        @Published var remainingCarbsFraction: Decimal = 1.0
        @Published var remainingCarbsCap: Decimal = 90
        @Published var noisyCGMTargetMultiplier: Decimal = 1.3
        @Published var allowDilution: Bool = false
        @Published var hideInsulinBadge: Bool = false
        @Published var insulinActionCurve: Decimal = 10

        override func subscribe() {
            units = settingsManager.settings.units

            subscribePreferencesSetting(\.maxDailySafetyMultiplier, on: $maxDailySafetyMultiplier) {
                maxDailySafetyMultiplier = $0 }
            subscribePreferencesSetting(\.currentBasalSafetyMultiplier, on: $currentBasalSafetyMultiplier) {
                currentBasalSafetyMultiplier = $0 }
            subscribePreferencesSetting(\.unsuspendIfNoTemp, on: $unsuspendIfNoTemp) { unsuspendIfNoTemp = $0 }
            subscribePreferencesSetting(\.suspendZerosIOB, on: $suspendZerosIOB) { suspendZerosIOB = $0 }
            subscribePreferencesSetting(\.suspendZerosIOB, on: $suspendZerosIOB) { suspendZerosIOB = $0 }
            subscribePreferencesSetting(\.min5mCarbimpact, on: $min5mCarbimpact) { min5mCarbimpact = $0 }
            subscribePreferencesSetting(\.remainingCarbsFraction, on: $remainingCarbsFraction) { remainingCarbsFraction = $0 }
            subscribePreferencesSetting(\.remainingCarbsCap, on: $remainingCarbsCap) { remainingCarbsCap = $0 }
            subscribePreferencesSetting(\.noisyCGMTargetMultiplier, on: $noisyCGMTargetMultiplier) {
                noisyCGMTargetMultiplier = $0 }
            subscribeSetting(\.allowDilution, on: $allowDilution) { allowDilution = $0 }
            subscribeSetting(\.hideInsulinBadge, on: $hideInsulinBadge) { hideInsulinBadge = $0 }
        }
    }
}

extension AlgorithmAdvancedSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
