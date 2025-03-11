//
//  TotalInsulinDisplayType.swift
//  Trio
//
//  Created by Cengiz Deniz on 25.08.24.
//
import Foundation

enum TherapyParameterDisplayType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case totalDailyDose
    case autoisfSensRatio

    var displayName: String {
        switch self {
        case .totalDailyDose:
            return String(localized: "Total Daily Dose 24hrs", comment: "")
        case .autoisfSensRatio:
            return String(localized: "autoISF Sens Ratio", comment: "")
        }
    }
}
