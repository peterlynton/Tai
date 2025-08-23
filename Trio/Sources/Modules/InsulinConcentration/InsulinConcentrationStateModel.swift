import SwiftUI

extension InsulinConcentration {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!

        var allowDilution: Bool = false
        @Published var insulinConcentration: Decimal = 1
        @Published var tempConcentration: Decimal = 1 // Temporary storage

        override func subscribe() {
            allowDilution = settings.settings.allowDilution
            let storedConcentration = settings.settings.insulinConcentration
            insulinConcentration = storedConcentration
            tempConcentration = storedConcentration // Sync temp with saved value

            subscribeSetting(\.insulinConcentration, on: $insulinConcentration) {
                self.insulinConcentration = $0
                self.tempConcentration = $0 // Keep temp in sync
            }
        }

        func saveChanges() {
            insulinConcentration = tempConcentration
            settings.settings.insulinConcentration = tempConcentration // Persist new value
        }
    }
}
