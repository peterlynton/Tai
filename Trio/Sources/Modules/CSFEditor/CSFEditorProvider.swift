import Foundation

extension CSFEditor {
    final class Provider: BaseProvider, CSFEditorProvider {
        var profile: CarbSensitivities {
            var retrievedSensitivities = storage.retrieve(OpenAPS.Settings.carbSensitivities, as: CarbSensitivities.self)
                ?? CarbSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.carbSensitivities))
                ?? CarbSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: []
                )

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dL settings
            if retrievedSensitivities.units == .mmolL || retrievedSensitivities.userPreferredUnits == .mmolL {
                let convertedSensitivities = retrievedSensitivities.sensitivities.map { csf in
                    CarbSensitivityEntry(
                        sensitivity: storage.parseSettingIfMmolL(value: csf.sensitivity),
                        offset: csf.offset,
                        start: csf.start
                    )
                }
                retrievedSensitivities = CarbSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: convertedSensitivities
                )
                saveProfile(retrievedSensitivities)
            }

            return retrievedSensitivities
        }

        func saveProfile(_ profile: CarbSensitivities) {
            storage.save(profile, as: OpenAPS.Settings.carbSensitivities)
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

        var crProfile: CarbRatios {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                ?? CarbRatios(
                    units: .grams,
                    schedule: []
                )
        }
    }
}
