import Charts
import Foundation
import SwiftUI

struct InsulinView: ChartContent {
    let glucoseData: [GlucoseStored]
    let insulinData: [PumpEventStored]
    let units: GlucoseUnits
    let bolusIncrement: Decimal

    var body: some ChartContent {
        drawBoluses()
        drawSMBs()
        drawExternals()
    }

    private func drawBoluses() -> some ChartContent {
        ForEach(insulinData) { insulin in
            // Safely unwrap the optional bolus
            if let bolus = insulin.bolus, bolus.isSMB == false, bolus.isExternal == false {
                let amount = bolus.amount ?? 0 as NSDecimalNumber
                let bolusDate = insulin.timestamp ?? Date()

                if amount != 0, let glucose = MainChartHelper.timeToNearestGlucose(
                    glucoseValues: glucoseData,
                    time: bolusDate.timeIntervalSince1970
                )?.glucose {
                    let yPosition = (units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL)
                    let size = (sqrt(CGFloat(amount) / .pi) * MainChartHelper.Config.bolusScale * 2)

                    PointMark(
                        x: .value("Time", bolusDate, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbol {
                        Image(systemName: "circle.fill").font(.system(size: size)).foregroundStyle(Color.teal)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth: 1)
                            )
                    }
                    .annotation(position: .top) {
                        Text(Formatter.bolusFormatterToIncrement(for: bolusIncrement).string(from: amount) ?? "")
                            .font(.caption2)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
    }

    private func drawSMBs() -> some ChartContent {
        ForEach(insulinData) { insulin in
            // Safely unwrap the optional bolus
            if let bolus = insulin.bolus, bolus.isSMB == true {
                let amount = bolus.amount ?? 0 as NSDecimalNumber
                let bolusDate = insulin.timestamp ?? Date()

                if amount != 0, let glucose = MainChartHelper.timeToNearestGlucose(
                    glucoseValues: glucoseData,
                    time: bolusDate.timeIntervalSince1970
                )?.glucose {
                    let size = (
                        MainChartHelper.Config.bolusSize + CGFloat(truncating: amount) * MainChartHelper.Config
                            .bolusScale
                    )
                    let yPosition = (units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL) + MainChartHelper
                        .bolusOffset(units: units)

                    PointMark(
                        x: .value("Time", bolusDate, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbol {
                        ZStack {
                            Image(systemName: "arrowtriangle.down")
                                .font(.system(size: size + 3))
                                .foregroundStyle(Color.primary)
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: size))
                                .foregroundStyle(Color.insulin)
                        }
                    }
                    .annotation(position: .top) {
                        Text(Formatter.bolusFormatterToIncrement(for: bolusIncrement).string(from: amount) ?? "")
                            .font(.caption2)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
    }

    private func drawExternals() -> some ChartContent {
        ForEach(insulinData.filter { $0.bolus?.isExternal == true }) { insulin in
            let amount = insulin.bolus?.amount ?? 0 as NSDecimalNumber
            let bolusDate = insulin.timestamp ?? Date()

            if amount != 0, let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: bolusDate.timeIntervalSince1970
            )?.glucose {
                let yPosition = (units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL) + MainChartHelper
                    .bolusOffset(units: units) * 2
                let size = (CGFloat(truncating: amount) * MainChartHelper.Config.bolusScale / 2)

                PointMark(
                    x: .value("Time", bolusDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    ZStack {
                        Image(systemName: "rhombus")
                            .font(.system(size: size + 2))
                            .foregroundStyle(Color.primary)
                        Image(systemName: "rhombus.fill")
                            .font(.system(size: size))
                            .foregroundStyle(Color.purple)
                    }
                }
                .annotation(position: .top) {
                    Text(Formatter.bolusFormatterToIncrement(for: bolusIncrement).string(from: amount) ?? "")
                        .font(.caption2)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }
}
