import Foundation

// MARK: - Garmin Data Type Settings

/// Primary data type selection for Garmin watchface and datafield.
/// Determines whether to display COB or Sensitivity Ratio alongside glucose data.
/// Used by both Trio and SwissAlpine watchfaces.
enum GarminDataType1: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case cob
    case isf
    case sensRatio

    var displayName: String {
        switch self {
        case .cob:
            return String(localized: "COB", comment: "")
        case .isf:
            return String(localized: "Insulin Sensitivity Factor", comment: "")
        case .sensRatio:
            return String(localized: "Sensitivity Ratio", comment: "")
        }
    }
}

/// Secondary data type selection for both Trio and SwissAlpine watchfaces.
/// Determines whether to display Temp Basal Rate or Eventual BG.
enum GarminDataType2: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case tbr
    case eventualBG

    var displayName: String {
        switch self {
        case .tbr:
            return String(localized: "TBR (Temp Basal Rate)", comment: "")
        case .eventualBG:
            return String(localized: "Eventual BG", comment: "")
        }
    }
}

// MARK: - Garmin Watchface Setting

/// Defines the available Garmin watchfaces with their associated UUIDs.
/// Each watchface has both a watchface app UUID and a datafield app UUID.
/// Both watchfaces now use the same data structure and settings (dataType1 and dataType2).
enum GarminWatchface: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case trio
    case swissalpine

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio original", comment: "")
        case .swissalpine:
            return String(localized: "Swissalpine xDrip+", comment: "")
        }
    }

    /// The UUID for the watchface application in Garmin Connect IQ
    var watchfaceUUID: UUID? {
        switch self {
        case .trio:
            // return UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")  // local build
            return UUID(uuidString: "81204522-B1BE-4E19-8E6E-C4032AAF8C6D") // ConnectIQ build
        case .swissalpine:
            return UUID(uuidString: "5A643C13-D5A7-40D4-B809-84789FDF4A1F")
        }
    }

    /// The UUID for the datafield application in Garmin Connect IQ
    var datafieldUUID: UUID? {
        switch self {
        case .trio:
            return UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
        case .swissalpine:
            return UUID(uuidString: "7A2268F6-3381-4474-81BD-0A3E7F458CB7")
        }
    }
}

// MARK: - Garmin Watch Settings Group

/// Groups related Garmin watch settings together for easier management.
/// Both watchfaces use the same settings: dataType1 and dataType2.
struct GarminWatchSettings: Codable, Hashable {
    var watchface: GarminWatchface = .trio
    var dataType1: GarminDataType1 = .cob
    var dataType2: GarminDataType2 = .tbr
    var garminDisableWatchfaceData: Bool = true
}
