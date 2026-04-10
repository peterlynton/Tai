import Foundation

struct CarbSensitivities: JSON {
    var units: GlucoseUnits
    var userPreferredUnits: GlucoseUnits
    var sensitivities: [CarbSensitivityEntry]
}

extension CarbSensitivities {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case sensitivities
    }
}

struct CarbSensitivityEntry: JSON {
    let sensitivity: Decimal
    let offset: Int
    let start: String
}

extension CarbSensitivityEntry {
    private enum CodingKeys: String, CodingKey {
        case sensitivity
        case offset
        case start
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sensitivity = try container.decode(Double.self, forKey: .sensitivity).decimal ?? .zero
        let start = try container.decode(String.self, forKey: .start)
        let offset = try container.decode(Int.self, forKey: .offset)

        self = CarbSensitivityEntry(sensitivity: sensitivity, offset: offset, start: start)
    }
}
