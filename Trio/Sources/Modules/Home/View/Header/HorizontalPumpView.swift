import SwiftUI

struct HorizontalPumpView: View {
    let reservoir: Decimal?
    let name: String
    let expiresAtDate: Date?
    let timerDate: Date
    let pumpStatusHighlightMessage: String?
    let battery: [OpenAPS_Battery]
    let autoISFratio: Decimal
    let totalDaily: Decimal
    let autoisfEnabled: Bool
    @Binding var showPumpSelection: Bool
    @Binding var shouldDisplayPumpSetupSheet: Bool
    let pumpSet: Bool
    var onTDDTap: (() -> Void)?
    var onAISRTap: (() -> Void)?
    let concentration: Decimal

    @Environment(\.colorScheme) var colorScheme

    private var batteryFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            Group {
                if let pumpStatusHighlightMessage = pumpStatusHighlightMessage {
                    Text(pumpStatusHighlightMessage)
                        .font(.footnote)
                        .fontWeight(.bold)
                        .layoutPriority(2) // Higher priority to ensure it scales less
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if reservoir == nil && battery.isEmpty {
                            Image(systemName: "keyboard.onehanded.left")
                                .font(.body)
                                .imageScale(.large)
                            Text("Add pump")
                                .font(.caption)
                                .bold()
                                .layoutPriority(1)
                        }
                        if let reservoir = reservoir {
                            HStack(spacing: 4) {
                                Image(systemName: "cross.vial.fill")
                                    .font(.callout)
                                    .foregroundColor(reservoirColor)
                                if reservoir == 0xDEAD_BEEF {
                                    Text("\(50 * concentration)+ " + String(localized: "U", comment: "Insulin unit"))
                                        .font(.callout)
                                        .fontWeight(.bold)
                                        .fontDesign(.rounded)
                                } else {
                                    Text(
                                        Formatter.integerFormatter
                                            .string(from: (reservoir * concentration) as NSNumber)! +
                                            String(localized: " U", comment: "Insulin unit")
                                    )
                                    .font(.callout)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                }
                            }
                        }
                        if (battery.first?.display) != nil, let shouldBatteryDisplay = battery.first?.display,
                           shouldBatteryDisplay
                        {
                            HStack {
                                Image(systemName: "battery.100")
                                    .font(.callout)
                                    .foregroundStyle(batteryColor)
                                Text("\(Formatter.integerFormatter.string(for: battery.first?.percent ?? 100) ?? "100") %")
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                            }
                        }
                        if let date = expiresAtDate {
                            HStack {
                                Image(systemName: "stopwatch.fill")
                                    .font(.callout)
                                    .foregroundStyle(timerColor)

                                let remainingTimeString = remainingTimeString(time: date.timeIntervalSince(timerDate))

                                Text(remainingTimeString)
                                    .font(date.timeIntervalSince(timerDate) > 0 ? .callout : .subheadline)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(
                                        // If the string is > 6 chars, i.e., exceeds "xd yh", limit width to 80 pts
                                        // This forces the "Replace pod" string to wrap to 2 lines.
                                        maxWidth: remainingTimeString.count > 6 ? 80 : .infinity,
                                        alignment: .leading
                                    )
                            }
                        }
                    }
                }
            }
            .onTapGesture {
                if pumpSet == false {
                    // shows user confirmation dialog with pump model choices, then proceeds to setup
                    showPumpSelection.toggle()
                } else {
                    // sends user to pump settings
                    shouldDisplayPumpSetupSheet.toggle()
                }
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "ivfluid.bag")
                    .font(.system(size: 16))
                    .foregroundColor(.insulin)
                    .layoutPriority(1)
                Text("24h")
                    .foregroundColor(.insulin)
                    .font(.callout).fontDesign(.rounded)
                    .layoutPriority(1)
                Text(Formatter.decimalFormatterWithOneFractionDigit.string(from: totalDaily as NSNumber) ?? "0.0")
                    .font(.callout).fontDesign(.rounded).fontWeight(.bold)
                    .layoutPriority(2)
            }
            .onTapGesture {
                onTDDTap?()
            }

            Spacer()
            if autoisfEnabled {
                Group {
                    Text("aiSR")
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(.loopGreen)
                        .layoutPriority(1)
                    Text(Formatter.decimalFormatterWithTwoFractionDigits.string(from: autoISFratio as NSNumber) ?? "1.0")
                        .font(.callout).fontWeight(.bold)
                        .fontDesign(.rounded)
                        .layoutPriority(2)
                }
                .onTapGesture {
                    onAISRTap?()
                }
            } else {
                Text("AS")
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.zt)
                    .layoutPriority(1)
                Text(Formatter.decimalFormatterWithTwoFractionDigits.string(from: autoISFratio as NSNumber) ?? "1.0")
                    .font(.callout).fontWeight(.bold)
                    .fontDesign(.rounded)
                    .layoutPriority(2)
            }

            Spacer()
        }
        .lineLimit(1) // Ensure all text stays on a single line
        .minimumScaleFactor(0.5) // Allow the text to scale down if needed
        .fixedSize(horizontal: false, vertical: true) // Prevent vertical scaling
    }

    private func remainingTimeString(time: TimeInterval) -> String {
        guard time > 0 else {
            return String(localized: "Replace pod", comment: "View/Header when pod expired")
        }

        var time = time
        let days = Int(time / 1.days.timeInterval)
        time -= days.days.timeInterval
        let hours = Int(time / 1.hours.timeInterval)
        time -= hours.hours.timeInterval
        let minutes = Int(time / 1.minutes.timeInterval)

        if days >= 1 {
            return "\(days)" + String(localized: "d", comment: "abbreviation for days") + " \(hours)" +
                String(localized: "h", comment: "abbreviation for hours")
        }

        if hours >= 1 {
            return "\(hours)" + String(localized: "h", comment: "abbreviation for hours")
        }

        return "\(minutes)" + String(localized: "m", comment: "abbreviation for minutes")
    }

    private var batteryColor: Color {
        guard let battery = battery.first else {
            return .gray
        }

        switch battery.percent {
        case ...10:
            return Color.loopRed
        case ...20:
            return Color.orange
        default:
            return Color.loopGreen
        }
    }

    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return Color.loopRed
        case ...30:
            return Color.orange
        default:
            return Color.insulin
        }
    }

    private var timerColor: Color {
        guard let expisesAt = expiresAtDate else {
            return .gray
        }

        let time = expisesAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return Color.loopRed
        case ...1.days.timeInterval:
            return Color.orange
        default:
            return Color.loopGreen
        }
    }
}
