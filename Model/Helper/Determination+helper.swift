import CoreData
import Foundation

extension OrefDetermination {
    static func fetch(_ predicate: NSPredicate = .predicateForOneDayAgo) -> NSFetchRequest<OrefDetermination> {
        let request = OrefDetermination.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: false)]
        request.predicate = predicate
        request.fetchLimit = 1
        return request
    }
}

extension OrefDetermination {
    var reasonParts: [String] {
        reason?.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason?.components(separatedBy: "; ").last ?? ""
    }

    func minPredBGFromReason(with units: GlucoseUnits) -> Decimal? {
        // Find the part that contains "minPredBG"
        if let minPredBGPart = reasonParts.first(where: { $0.contains("minPredBG") }) {
            // Extract the number after "minPredBG"
            let components = minPredBGPart.components(separatedBy: "minPredBG ")
            if let valueComponent = components.dropFirst().first {
                // Get everything after "minPredBG " and convert to Decimal
                let valueString = valueComponent.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted)
                var value = Decimal(string: valueString)

                // Check if conversion is needed
                if units == .mmolL {
                    value = value?.asMgdL
                }
                // debug(.service, "minPredBG is \(value ?? 0)")
                return value
            }
        }
        return nil
    }
}

extension NSPredicate {
    static var enactedDetermination: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "enacted == %@ AND timestamp >= %@", true as NSNumber, date as NSDate)
    }

    static var suggestedDetermination: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(
            format: "deliverAt >= %@ AND (enacted == false OR enacted == nil)",
            date as NSDate
        )
    }

    static var determinationsForCobIobCharts: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }

    static var enactedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND enacted == %@",
            Date.oneDayAgo as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }

    static var suggestedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND (enacted == %@ OR enacted == nil OR enacted != %@)",
            Date.oneDayAgo as NSDate,
            false as NSNumber,
            true as NSNumber,
            true as NSNumber
        )
    }

    static var determinationsForStats: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }

    // for autoISF History
    static func determinationPeriod(from startDate: Date, to endDate: Date) -> NSPredicate {
        NSPredicate(format: "deliverAt >= %@ AND deliverAt <= %@", startDate as NSDate, endDate as NSDate)
    }
}
