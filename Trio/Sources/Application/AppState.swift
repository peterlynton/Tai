import Foundation
import Observation
import SwiftUI
import UIKit

@Observable class AppState {
    func trioBackgroundColor(for colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    // For statistics view settings
    var statSelectedViewType: Stat.StateModel.StatisticViewType = .glucose
    var statSelectedInsulinChartType: Stat.StateModel.InsulinChartType = .totalDailyDose
    var statSelectedInsulinTimeInterval: Stat.StateModel.StatsTimeInterval = .day
}
