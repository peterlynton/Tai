import Combine

extension CarbRatioEditor {
    final class Provider: BaseProvider, CarbRatioEditorProvider {
        var profile: CarbRatios {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                ?? CarbRatios(units: .grams, schedule: [])
        }

        var isfProfile: InsulinSensitivities {
            storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: []
                )
        }

        var csfProfile: CarbSensitivities {
            storage.retrieve(OpenAPS.Settings.carbSensitivities, as: CarbSensitivities.self)
                ?? CarbSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.carbSensitivities))
                ?? CarbSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: []
                )
        }

        func saveProfile(_ profile: CarbRatios) {
            storage.save(profile, as: OpenAPS.Settings.carbRatios)
        }
    }
}
