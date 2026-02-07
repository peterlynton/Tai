import Charts
import Foundation
import SwiftUI

/// Renders glucose turning point labels (peaks and valleys) on the main chart.
///
/// Each detected extremum is displayed as a small annotated label showing the glucose value,
/// positioned above maxima and below minima. Colors match the glucose range thresholds.
struct GlucosePeaksChartView: ChartContent {
    let peaks: [(date: Date, glucose: Int16, type: ExtremumType)]
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let glucoseColorScheme: GlucoseColorScheme
    let currentGlucoseTarget: Decimal

    var body: some ChartContent {
        ForEach(Array(peaks.enumerated()), id: \.offset) { _, peak in
            let glucoseDecimal = Decimal(peak.glucose)
            let displayValue = units == .mgdL ? glucoseDecimal : glucoseDecimal.asMmolL
            let color = peakColor(glucose: glucoseDecimal)
            let formattedValue = formattedGlucose(Int(peak.glucose))

            // Invisible point mark to anchor the annotation at the correct chart position
            PointMark(
                x: .value("Time", peak.date, unit: .second),
                y: .value("Value", displayValue)
            )
            .symbolSize(0)
            .annotation(position: annotationPosition(for: peak.type)) {
                Text(formattedValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Helpers

    /// Determines annotation position based on extremum type.
    private func annotationPosition(for type: ExtremumType) -> AnnotationPosition {
        switch type {
        case .max:
            return .top
        case .min:
            return .bottom
        case .none:
            return .top
        }
    }

    /// Returns the color for a peak label based on glucose thresholds.
    /// Matches the coloring logic in ``GlucoseChartView``: dynamic scheme uses hardcoded
    /// bounds (55–220) for a wider gradient, static scheme uses the user-set thresholds.
    private func peakColor(glucose: Decimal) -> Color {
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamic = glucoseColorScheme == .dynamicColor

        return Trio.getDynamicGlucoseColor(
            glucoseValue: glucose,
            highGlucoseColorValue: isDynamic ? hardCodedHigh : highGlucose,
            lowGlucoseColorValue: isDynamic ? hardCodedLow : lowGlucose,
            targetGlucose: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    /// Formats the glucose value for display, respecting unit preferences.
    private func formattedGlucose(_ glucose: Int) -> String {
        if units == .mgdL {
            return "\(glucose)"
        } else {
            return glucose.formattedAsMmolL
        }
    }
}
