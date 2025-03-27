import Foundation

struct Determination: JSON, Equatable {
    let id: UUID?
    var reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    var eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Decimal?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
    let carbsReq: Decimal?
    let temp: TempType?
    var bg: Decimal?
    let reservoir: Decimal?
    var isf: Decimal?
    var timestamp: Date?

    /// `tdd` (Total Daily Dose) is included so it can be part of the
    /// enacted and suggested devicestatus data that gets uploaded to Nightscout.
    var tdd: Decimal?

    var current_target: Decimal?
    let insulinForManualBolus: Decimal?
    let manualBolusErrorString: Decimal?
    var minDelta: Decimal?
    var expectedDelta: Decimal?
    var minGuardBG: Decimal?
    var minPredBG: Decimal?
    var threshold: Decimal?
    let carbRatio: Decimal?
    let received: Bool?
    //    autoISF
    let smbRatio: Decimal?
    let duraISFratio: Decimal?
    let bgISFratio: Decimal?
    let ppISFratio: Decimal?
    let acceISFratio: Decimal?
    let autoISFratio: Decimal?
    let iobTH: Decimal?
    let tick: Int?
    // acce calc
    let parabolaFitMinutes: Decimal?
    let parabolaFitLastDelta: Decimal?
    let parabolaFitNextDelta: Decimal?
    let parabolaFitCorrelation: Decimal?
    let parabolaFitA0: Decimal?
    let parabolaFitA1: Decimal?
    let parabolaFitA2: Decimal?
    let duraMin: Decimal?
    let duraAvg: Decimal?
    let bgAcce: Decimal?
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

extension Determination {
    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case isf = "ISF"
        case current_target
        case tdd = "TDD"
        case insulinForManualBolus
        case manualBolusErrorString
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
        case received
        // autoISF
        case smbRatio = "SMBratio"
        case duraISFratio = "dura_ISFratio"
        case bgISFratio = "bg_ISFratio"
        case ppISFratio = "pp_ISFratio"
        case acceISFratio = "acce_ISFratio"
        case autoISFratio = "auto_ISFratio"
        case iobTH = "iob_THeffective"
        case tick
        // acce calc
        case parabolaFitMinutes = "parabola_fit_minutes"
        case parabolaFitLastDelta = "parabola_fit_last_delta"
        case parabolaFitNextDelta = "parabola_fit_next_delta"
        case parabolaFitCorrelation = "parabola_fit_correlation"
        case parabolaFitA0 = "parabola_fit_a0"
        case parabolaFitA1 = "parabola_fit_a1"
        case parabolaFitA2 = "parabola_fit_a2"
        case duraMin = "dura_min"
        case duraAvg = "dura_avg"
        case bgAcce = "bg_acce"
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

protocol DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination)
}

extension Determination {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
