import Combine
import Observation
import SwiftUI

extension AutoISFSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!

        var units: GlucoseUnits = .mgdL

        // Published properties for state binding
        @Published var autoisf: Bool = false {
            didSet {
                updateEnableAutosens() // Call the method whenever autoisf changes
            }
        }

        @Published var enableAutosens: Bool = true
        @Published var enableSMBEvenOnOddOffAlways: Bool = false
        @Published var autoISFoffSport: Bool = false
        @Published var autoISFmax: Decimal = 2
        @Published var autoISFmin: Decimal = 0.5
        @Published var smbDeliveryRatio: Decimal = 0.85
        @Published var smbDeliveryRatioMin: Decimal = 0.65
        @Published var smbDeliveryRatioMax: Decimal = 0.80
        @Published var smbDeliveryRatioBGrange: Decimal = 0
        @Published var smbMaxRangeExtension: Decimal = 2
        @Published var enableBGAcceleration: Bool = true
        @Published var autoISFhourlyChange: Decimal = 0.6
        @Published var lowerISFrangeWeight: Decimal = 0.7
        @Published var higherISFrangeWeight: Decimal = 0.3
        @Published var bgAccelISFweight: Decimal = 0.15
        @Published var bgBrakeISFweight: Decimal = 0.15
        @Published var postMealISFweight: Decimal = 0.02
        @Published var iobThresholdPercent: Decimal = 1
        @Published var enableBGacceleration: Bool = false

        var insulinActionCurve: Decimal = 6

        // Method to update enableAutosens when autoisf is false
        private func updateEnableAutosens() {
            if !autoisf {
                enableAutosens = true // Always enable autosens to true when autoisf is false
            }
        }

        override func subscribe() {
            units = settingsManager.settings.units
            // Ensure all preferences map to state properties correctly
            subscribePreferencesSetting(\.autoisf, on: $autoisf) { autoisf = $0 }
            subscribePreferencesSetting(\.enableAutosens, on: $enableAutosens) { enableAutosens = $0 }
            subscribePreferencesSetting(\.enableSMBEvenOnOddOffAlways, on: $enableSMBEvenOnOddOffAlways) {
                enableSMBEvenOnOddOffAlways = $0 }
            subscribePreferencesSetting(\.autoISFoffSport, on: $autoISFoffSport) { autoISFoffSport = $0 }
            subscribePreferencesSetting(\.iobThresholdPercent, on: $iobThresholdPercent) { iobThresholdPercent = $0 }
            subscribePreferencesSetting(\.enableBGacceleration, on: $enableBGacceleration) { enableBGacceleration = $0 }
            subscribePreferencesSetting(\.autoISFmax, on: $autoISFmax) { autoISFmax = $0 }
            subscribePreferencesSetting(\.autoISFmin, on: $autoISFmin) { autoISFmin = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatio, on: $smbDeliveryRatio) { smbDeliveryRatio = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioMin, on: $smbDeliveryRatioMin) { smbDeliveryRatioMin = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioMax, on: $smbDeliveryRatioMax) { smbDeliveryRatioMax = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioBGrange, on: $smbDeliveryRatioBGrange) { smbDeliveryRatioBGrange = $0 }
            subscribePreferencesSetting(\.smbMaxRangeExtension, on: $smbMaxRangeExtension) { smbMaxRangeExtension = $0 }
            subscribePreferencesSetting(\.enableBGacceleration, on: $enableBGAcceleration) { enableBGAcceleration = $0 }
            subscribePreferencesSetting(\.autoISFhourlyChange, on: $autoISFhourlyChange) { autoISFhourlyChange = $0 }
            subscribePreferencesSetting(\.lowerISFrangeWeight, on: $lowerISFrangeWeight) { lowerISFrangeWeight = $0 }
            subscribePreferencesSetting(\.higherISFrangeWeight, on: $higherISFrangeWeight) { higherISFrangeWeight = $0 }
            subscribePreferencesSetting(\.bgAccelISFweight, on: $bgAccelISFweight) { bgAccelISFweight = $0 }
            subscribePreferencesSetting(\.bgBrakeISFweight, on: $bgBrakeISFweight) { bgBrakeISFweight = $0 }
            subscribePreferencesSetting(\.postMealISFweight, on: $postMealISFweight) { postMealISFweight = $0 }
        }
    }
}

extension AutoISFSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
