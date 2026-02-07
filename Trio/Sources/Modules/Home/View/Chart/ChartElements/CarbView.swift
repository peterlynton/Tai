import Charts
import Foundation
import SwiftUI

struct CarbView: ChartContent {
    let glucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let carbData: [CarbEntryStored]
    let fpuData: [CarbEntryStored]
    let minValue: Decimal
    let peaks: [(date: Date, glucose: Int16, type: ExtremumType)]

    /// Time proximity (seconds) within which a carb marker is considered to collide with a peak label.
    private static let proximityWindow: TimeInterval = 15 * 60

    /// Returns the nearby peak's `ExtremumType` if `date` is within ±15 min of any peak, otherwise `nil`.
    private func nearbyPeakType(for date: Date) -> ExtremumType? {
        peaks.first(where: { abs($0.date.timeIntervalSince(date)) <= Self.proximityWindow && $0.type != .none })?.type
    }

    /// Extra vertical offset applied when a carb marker collides with a peak label.
    private var collisionOffset: Decimal {
        MainChartHelper.bolusOffset(units: units) * Decimal(1.3)
    }

    var body: some ChartContent {
        drawCarbs()
        drawFpus()
    }

    private func drawCarbs() -> some ChartContent {
        ForEach(carbData) { carb in
            let carbAmount = carb.carbs
            let carbDate = carb.date ?? Date()

            if let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: carbDate.timeIntervalSince1970
            )?.glucose {
                // Original position (glucose − 1× offset); shift down extra if near a peak-min label
                let baseY = (units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL) - MainChartHelper
                    .bolusOffset(units: units)
                let nearPeak = nearbyPeakType(for: carbDate)
                let yPosition = nearPeak == .min ? baseY - collisionOffset : baseY
                let size = min(
                    sqrt(CGFloat(carbAmount) / .pi) * MainChartHelper.Config.carbsScale,
                    MainChartHelper.Config.maxCarbSize
                )

                PointMark(
                    x: .value("Time", carbDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    Image(systemName: "circle.fill").font(.system(size: size)).foregroundStyle(Color.loopYellow)
                        .overlay(
                            Circle().stroke(Color.primary, lineWidth: 1)
                        ) }
                .annotation(position: .bottom) {
                    Text(Formatter.integerFormatter.string(from: carbAmount as NSNumber)!).font(.caption2)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    private func drawFpus() -> some ChartContent {
        ForEach(fpuData, id: \.id) { fpu in
            let fpuAmount = fpu.carbs
            let size = (MainChartHelper.Config.fpuSize + CGFloat(fpuAmount) * MainChartHelper.Config.carbsScale) * 1.8
            let yPosition = minValue // value is parsed to mmol/L when passed into struct based on user settings

            PointMark(
                x: .value("Time", fpu.date ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize(size)
            .foregroundStyle(Color.brown)
        }
    }
}
