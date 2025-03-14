import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

struct TimePicker: Identifiable {
    let label: String
    let number: String
    var active: Bool
    let hours: Int16
    var id: String { label }
}

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver
        let safeAreaSize: CGFloat = 0.08

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var state = StateModel()

        @State var settingsPath = NavigationPath()
        @State var isStatusPopupPresented = false
        @State private var statusTitlePopup: String = ""
        @State var showCancelAlert = false
        @State var showCancelConfirmDialog = false
        @State var isConfirmStopOverrideShown = false
        @State var isConfirmStopOverridePresented = false
        @State var isConfirmStopTempTargetShown = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        @State var showPumpSelection: Bool = false
        @State var showCGMSelection: Bool = false
        @State var notificationsDisabled = false
        @State var timeButtons: [TimePicker] = [
            TimePicker(label: String(localized: "2 hours"), number: "2", active: false, hours: 2),
            TimePicker(label: String(localized: "4 hours"), number: "4", active: false, hours: 4),
            TimePicker(label: String(localized: "6 hours"), number: "6", active: false, hours: 6),
            TimePicker(label: String(localized: "12 hours"), number: "12", active: false, hours: 12),
            TimePicker(label: String(localized: "24 hours"), number: "24", active: false, hours: 24)
        ]

        let buttonFont = Font.custom("TimeButtonFont", size: 14)

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 1
        )) var latestOverride: FetchedResults<OverrideStored>

        @FetchRequest(fetchRequest: TempTargetStored.fetch(
            NSPredicate.lastActiveTempTarget,
            ascending: false,
            fetchLimit: 1
        )) var latestTempTarget: FetchedResults<TempTargetStored>

        var bolusProgressFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            let bolusIncrement = state.bolusIncrement
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximumFractionDigits = Decimal.maxFractionDigits(for: bolusIncrement)
            formatter.minimumFractionDigits = 1
            formatter.allowsFloats = true
            formatter.roundingIncrement = Double(bolusIncrement) as NSNumber
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var historySFSymbol: String {
            if #available(iOS 17.0, *) {
                return "book.pages"
            } else {
                return "book"
            }
        }

        @ViewBuilder func pumpTimezoneView(_ badgeImage: UIImage, _ badgeColor: Color) -> some View {
            HStack {
                Image(uiImage: badgeImage.withRenderingMode(.alwaysTemplate))
                    .font(.system(size: 14))
                    .colorMultiply(badgeColor)
                Text(String(localized: "Time Change Detected", comment: ""))
                    .bold()
                    .font(.system(size: 14))
                    .foregroundStyle(badgeColor)
            }
            .onTapGesture {
                if state.pumpDisplayState != nil {
                    // sends user to pump settings
                    state.shouldDisplayPumpSetupSheet.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .overlay(
                Capsule()
                    .stroke(badgeColor.opacity(0.4), lineWidth: 2)
            )
        }

        var cgmSelectionButtons: some View {
            ForEach(cgmOptions, id: \.name) { option in
                if let cgm = state.listOfCGM.first(where: option.predicate) {
                    Button(option.name) {
                        state.addCGM(cgm: cgm)
                    }
                }
            }
        }

        var glucoseView: some View {
            CurrentGlucoseView(
                concentration: state.concentration,
                hideInsulinBadge: state.hideInsulinBadge,
                timerDate: state.timerDate,
                units: state.units,
                alarm: state.alarm,
                lowGlucose: state.lowGlucose,
                highGlucose: state.highGlucose,
                cgmAvailable: state.cgmAvailable,
                currentGlucoseTarget: state.currentGlucoseTarget,
                glucoseColorScheme: state.glucoseColorScheme,
                glucose: state.latestTwoGlucoseValues
            ).scaleEffect(0.9)
                .onTapGesture {
                    if !state.cgmAvailable {
                        showCGMSelection.toggle()
                    } else {
                        state.shouldDisplayCGMSetupSheet.toggle()
                    }
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.showModal(for: .snooze)
                }
        }

        var pumpView: some View {
            PumpView(
                reservoir: state.reservoir,
                name: state.pumpName,
                expiresAtDate: state.pumpExpiresAtDate,
                timerDate: state.timerDate,
                pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
                battery: state.batteryFromPersistence
            )
            .onTapGesture {
                if state.pumpDisplayState == nil {
                    // shows user confirmation dialog with pump model choices, then proceeds to setup
                    showPumpSelection.toggle()
                } else {
                    // sends user to pump settings
                    state.shouldDisplayPumpSetupSheet.toggle()
                }
            }
        }

        var horizontalPumpView: some View {
            HorizontalPumpView(
                reservoir: state.reservoir,
                name: state.pumpName,
                expiresAtDate: state.pumpExpiresAtDate,
                timerDate: state.timerDate,
                pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
                battery: state.batteryFromPersistence,
                autoISFratio: (state.determinationsFromPersistence.first?.autoISFratio ?? 1) as Decimal,
                totalDaily: state.fetchedTDDs.first?.totalDailyDose ?? 0,
                autoisfEnabled: state.autoisfEnabled
            )
            .onTapGesture {
                if state.pumpDisplayState == nil {
                    // shows user confirmation dialog with pump model choices, then proceeds to setup
                    showPumpSelection.toggle()
                } else {
                    // sends user to pump settings
                    state.shouldDisplayPumpSetupSheet.toggle()
                }
            }
        }

        var tempBasalString: String? {
            guard let lastTempBasal = state.tempBasals.last?.tempBasal, let tempRate = lastTempBasal.rate else {
                return nil
            }
            let rateString = Formatter.insulinFormatterToIncrement(for: state.bolusIncrement)
                .string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

//            if let apsManager = state.apsManager, apsManager.isManualTempBasal {
//                manualBasalString = String(
//                    localized:
//                    " - Manual Basal ⚠️",
//                    comment: "Manual Temp basal"
//                )
//            }

            return rateString + String(localized: " U/hr", comment: "Unit per hour with space") + manualBasalString
        }

        var overrideString: String? {
            guard let latestOverride = latestOverride.first else {
                return nil
            }

            let percent = latestOverride.percentage
            let percentString = percent == 100 ? "" : "\(percent.formatted(.number)) %"

            let unit = state.units
            var target = (latestOverride.target ?? 100) as Decimal
            target = unit == .mmolL ? target.asMmolL : target

            var targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
                .rawValue
            if tempTargetString != nil {
                targetString = ""
            }

            let duration = latestOverride.duration ?? 0
            let addedMinutes = Int(truncating: duration)
            let date = latestOverride.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            let indefinite = latestOverride.indefinite
            var durationString = ""

            if !indefinite {
                if newDuration >= 1 {
                    durationString = formatHrMin(Int(newDuration))
                } else if newDuration > 0 {
                    durationString = "\(Int(newDuration * 60)) s"

                } else {
                    /// Do not show the Override anymore
                    Task {
                        guard let objectID = self.latestOverride.first?.objectID else { return }
                        await state.cancelOverride(withID: objectID)
                    }
                }
            }

            let smbScheduleString = latestOverride
                .smbIsScheduledOff && ((latestOverride.start?.stringValue ?? "") != (latestOverride.end?.stringValue ?? ""))
                ? " \(formatTimeRange(start: latestOverride.start?.stringValue, end: latestOverride.end?.stringValue))"
                : ""

            let smbToggleString = latestOverride.smbIsOff || latestOverride
                .smbIsScheduledOff ? "SMBs Off\(smbScheduleString)" : ""

            let components = [durationString, percentString, targetString, smbToggleString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: ", ")
        }

        var tempTargetString: String? {
            guard let latestTempTarget = latestTempTarget.first else {
                return nil
            }
            let duration = latestTempTarget.duration
            let addedMinutes = Int(truncating: duration ?? 0)
            let date = latestTempTarget.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            var durationString = ""
            var percentageString = ""
            var target = (latestTempTarget.target ?? 100) as Decimal
            var halfBasalTarget: Decimal = 160
            if latestTempTarget.halfBasalTarget != nil {
                halfBasalTarget = latestTempTarget.halfBasalTarget! as Decimal
            } else { halfBasalTarget = state.settingHalfBasalTarget }
            var showPercentage = false
            if target > 100, state.isExerciseModeActive || state.highTTraisesSens { showPercentage = true }
            if target < 100, state.lowTTlowersSens, state.autosensMax > 1 { showPercentage = true }
            if showPercentage {
                percentageString =
                    " \(state.computeAdjustedPercentage(halfBasalTargetValue: halfBasalTarget, tempTargetValue: target))%" }
            target = state.units == .mmolL ? target.asMmolL : target
            let targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " +
                state.units.rawValue + percentageString

            if newDuration >= 1 {
                durationString =
                    "\(newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) min"
            } else if newDuration > 0 {
                durationString =
                    "\((newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) s"
            } else {
                /// Do not show the Temp Target anymore
                Task {
                    guard let objectID = self.latestTempTarget.first?.objectID else { return }
                    await state.cancelTempTarget(withID: objectID)
                }
            }

            let components = [targetString, durationString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: ", ")
        }

        var timeIntervalButtons: some View {
            let buttonColor = (colorScheme == .dark ? Color.white : Color.black).opacity(0.8)

            return HStack(alignment: .center) {
                ForEach(timeButtons) { button in
                    Button(action: {
                        state.hours = button.hours
                    }) {
                        Group {
                            if button.active {
                                Text(
                                    button.hours.description + "\u{00A0}" +
                                        String(localized: "h", comment: "h")
                                )
                            } else {
                                Text(button.hours.description)
                            }
                        }
                        .font(.footnote)
                        .fontWeight(button.active ? .semibold : .regular)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .foregroundColor(
                            button
                                .active ? (colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white) : buttonColor
                        )
                        .background(button.active ? buttonColor.opacity(colorScheme == .dark ? 1 : 0.8) : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(button.active ? buttonColor.opacity(0.4) : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }

        var statsIconString: String {
            if #available(iOS 18, *) {
                return "chart.line.text.clipboard"
            } else {
                return "list.clipboard"
            }
        }

        @ViewBuilder private func tappableButton(
            buttonColor: Color,
            label: String,
            iconString: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: {
                action()
            }) {
                HStack {
                    Image(systemName: iconString)
                    Text(label)
                }
                .font(.footnote)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .foregroundStyle(buttonColor)
                .overlay(
                    Capsule()
                        .stroke(buttonColor.opacity(0.4), lineWidth: 2)
                )
            }
        }

        var timeIntervalPanel: some View {
            HStack(alignment: .center) {
                Spacer()
                Button(action: { state.showModal(for: .statistics) }) {
                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                        .symbolRenderingMode(.palette)
                        .scaleEffect(x: -1)
                        .foregroundStyle(
                            Color.primary,
                            LinearGradient(colors: [
                                Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
                                Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
                                Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
                                Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
                                Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
                            ], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: 24, height: 24)
                        .background(
                            colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                Color.white
                        )
                        .clipShape(Circle())
                }
                Spacer()
                ForEach(timeButtons) { button in
                    Text(button.active ? button.label : button.number).onTapGesture {
                        state.hours = button.hours
                    }
                    .foregroundStyle(button.active ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.9) : .secondary)
                    .frame(maxHeight: 30).padding(.horizontal, 8)
                    .background(
                        button.active ?
                            // RGB(30, 60, 95)
                            (
                                colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                    Color.white
                            ) :
                            Color
                            .clear
                    )
                    .cornerRadius(20)
                }
                Spacer()
                Button(action: {
                    state.isLegendPresented.toggle()
                }) {
                    Image(systemName: "info")
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black).opacity(0.9)
                        .frame(width: 24, height: 24)
                        .background(
                            colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                Color.white
                        )
                        .clipShape(Circle())
                }
                .padding([.top, .bottom])
                Spacer()
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33),
                radius: colorScheme == .dark ? 5 : 3
            )
            .font(buttonFont)
        }

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            ZStack {
                MainChartView(
                    geo: geo,
                    safeAreaSize: notificationsDisabled == true ? safeAreaSize : 0,
                    units: state.units,
                    hours: state.filteredHours,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    screenHours: state.hours,
                    displayXgridLines: state.displayXgridLines,
                    displayYgridLines: state.displayYgridLines,
                    thresholdLines: state.thresholdLines,
                    state: state,
                    showCobIobChart: state.showCobIobChart
                )
            }
            .padding(.bottom, UIDevice.adjustPadding(min: 0, max: nil))
        }

        func highlightButtons() {
            for i in 0 ..< timeButtons.count {
                timeButtons[i].active = timeButtons[i].hours == state.hours
            }
        }

        @ViewBuilder func rightHeaderPanel(_: GeometryProxy) -> some View {
            VStack(alignment: .trailing, spacing: 15) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16))
                        .foregroundColor(.loopGreen)
                    let isfValue = state.enactedAndNonEnactedDeterminations.first?.insulinSensitivity ?? NSDecimalNumber.zero
                    let isfValueDecimal = isfValue.decimalValue
                    let convertedISF = state.units == .mgdL ? isfValueDecimal.description : isfValueDecimal
                        .formattedAsMmolL
                    Text(convertedISF)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
//                    Text("\(state.units.rawValue)/U")
//                        .font(.system(size: 12, design: .rounded))
                }

                /// eventualBG string
                if let eventualBG = state.enactedAndNonEnactedDeterminations.first?.eventualBG {
                    let bg = eventualBG as Decimal
                    HStack {
                        Text(
                            "⇢"
                        ).font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: (
                                    state.units == .mmolL ? bg
                                        .asMmolL : bg
                                ) as NSNumber
                            )!
                        )
                        .font(.system(size: 16, weight: .bold)) }
                } else {
                    HStack {
                        Text("⇢")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("--")
                    }
                }
                /// Loop view at bottomLeading
                /// Loop view at bottomLeading
                LoopView(
                    closedLoop: state.closedLoop,
                    timerDate: state.timerDate,
                    isLooping: state.isLooping,
                    lastLoopDate: state.lastLoopDate,
                    manualTempBasal: state.manualTempBasal,
                    determination: state.determinationsFromPersistence
                )
                .onTapGesture {
                    setStatusTitlePopup()
                    state.isStatusPopupPresented.toggle()
                    setStatusTitlePopup()
//                    state.isLoopStatusPresented = true
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
            }
        }

        @ViewBuilder func leftHeaderPanel(_: GeometryProxy) -> some View {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: "drop.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.insulin)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits
                                .string(from: (state.enactedAndNonEnactedDeterminations.first?.iob ?? 0) as NSNumber) ?? "0"
                        ) +
                            String(localized: " U", comment: "Insulin unit")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
//                    InsulinConcentrationBadge(concentration: 1)
                }
                HStack {
                    Image("premeal")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 15, height: 15)
                        .foregroundColor(.loopYellow)
                        .padding(.leading, 3)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                            ) ?? "0"
                        ) +
                            String(localized: " g", comment: "gram of carbs")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }
                HStack {
                    if state.pumpSuspended {
                        Text("Pump suspended")
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.loopGray)
                    } else if let tempBasalString = tempBasalString {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .rotationEffect(Angle(degrees: 180))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.insulinTintColor.opacity(0.9), .insulinTintColor.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text(tempBasalString)
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                    } else {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .rotationEffect(Angle(degrees: 180))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.insulinTintColor.opacity(0.9), .insulinTintColor.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("No Data")
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                    }
                }
            }
        }

        @ViewBuilder func mealPanel(_: GeometryProxy) -> some View {
            HStack {
                HStack {
                    Image(systemName: "drop.circle")
                        .font(.callout)
                        .foregroundColor(Color.insulin)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits
                                .string(from: (state.enactedAndNonEnactedDeterminations.first?.iob ?? 0) as NSNumber) ?? "0"
                        ) +
                            String(localized: " U", comment: "Insulin unit")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }

                Spacer()

                HStack {
                    Image("premeal")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.loopYellow)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                            ) ?? "0"
                        ) +
                            String(localized: " g", comment: "gram of carbs")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }

                Spacer()

                HStack {
                    if state.pumpSuspended {
                        Text("Pump suspended")
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.loopGray)
                    } else if let tempBasalString = tempBasalString {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .rotationEffect(Angle(degrees: 180))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.insulinTintColor.opacity(1), .insulinTintColor.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        if tempBasalString.count > 5 {
                            Text(tempBasalString)
                                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .truncationMode(.tail)
                                .allowsTightening(true)
                        } else {
                            // Short strings can just display normally
                            Text(tempBasalString).font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        }
                    } else {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .rotationEffect(Angle(degrees: 180))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.insulinTintColor.opacity(1), .insulinTintColor.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("No Data")
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                    }
                }
                if state.therapyParameterDisplayType == .autoisfSensRatio {
                    Spacer()
                    HStack {
                        if state.autoisfEnabled {
                            Text("aiSR")
                                .font(.callout).fontWeight(.bold)
                                .foregroundColor(Color.loopGreen)

                            if let determination = state.determinationsFromPersistence.first,
                               let autoISFratioValue = determination.autoISFratio as? Decimal
                            {
                                Text(
                                    Formatter.decimalFormatterWithTwoFractionDigits.string(
                                        from: NSDecimalNumber(decimal: autoISFratioValue)
                                    ) ?? "0"
                                )
                                .font(.callout).fontWeight(.bold)
                                .fontDesign(.rounded)
                            } else {
                                Text("--")
                                    .font(.callout).fontWeight(.bold)
                                    .fontDesign(.rounded)
                            }
                        } else {
                            Text("AS")
                                .font(.callout).fontWeight(.bold)
                                .foregroundColor(Color.zt)

                            if let determination = state.determinationsFromPersistence.first,
                               let autoISFratioValue = determination.autoISFratio as? Decimal
                            {
                                Text(
                                    Formatter.decimalFormatterWithTwoFractionDigits.string(
                                        from: NSDecimalNumber(decimal: autoISFratioValue)
                                    ) ?? "0"
                                )
                                .font(.callout).fontWeight(.bold)
                                .fontDesign(.rounded)
                            } else {
                                Text("--")
                                    .font(.callout).fontWeight(.bold)
                                    .fontDesign(.rounded)
                            }
                        }
                    }
                } else {
                    Spacer()

                    Text("TDD:")
                        .foregroundColor(Color.insulin)
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                    Text(
                        (
                            Formatter.insulinFormatterToIncrement(for: 0.1)
                                .string(from: (state.fetchedTDDs.first?.totalDailyDose ?? 0) as NSNumber) ??
                                "0"
                        ) + String(localized: " U", comment: "Insulin unit")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }
            }.padding(.horizontal)
        }

        @ViewBuilder func adjustmentsOverrideView(_ overrideString: String) -> some View {
            Group {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(Color.primary, Color.purple)
                VStack(alignment: .leading) {
                    Text(latestOverride.first?.name ?? String(localized: "Custom Override"))
                        .font(.subheadline)
                        .frame(alignment: .leading)

                    Text(overrideString)
                        .font(.caption)
                }
            }
            .onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentsTempTargetView(_ tempTargetString: String) -> some View {
            Group {
                let targetValue = latestTempTarget.first?.target?.doubleValue ?? 0.0
                let rotationValue: Double = targetValue < 100 ? 180 : 0
                Image(systemName: "arrow.up.circle.badge.clock")
                    .rotationEffect(.degrees(rotationValue))
                    .font(.system(size: 22))
                    .foregroundStyle(Color.primary, Color.loopGreen)
                VStack(alignment: .leading) {
                    Text(latestTempTarget.first?.name ?? String(localized: "Temp Target"))
                        .font(.subheadline)
                        .frame(alignment: .leading)
                    Text(tempTargetString)
                        .font(.caption)
                        .frame(alignment: .leading)
                }
            }
            .onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentsCancelView(_ cancelAction: @escaping () -> Void) -> some View {
            Image(systemName: "xmark.app")
                .font(.system(size: 24))
                .foregroundStyle(
                    Color.loopGreen,
                    Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569)
                )
                .onTapGesture {
                    cancelAction()
                }
        }

        @ViewBuilder func adjustmentsCancelTempTargetView() -> some View {
            Image(systemName: "xmark.app")
                .font(.system(size: 24))
                .foregroundStyle(Color.primary, Color.loopGreen)
                .confirmationDialog(
                    "Stop the Temp Target \"\(latestTempTarget.first?.name ?? "")\"?",
                    isPresented: $isConfirmStopTempTargetShown,
                    titleVisibility: .visible
                ) {
                    Button("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestTempTarget.first?.objectID else { return }
                            await state.cancelTempTarget(withID: objectID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .onTapGesture {
                    if !latestTempTarget.isEmpty {
                        isConfirmStopTempTargetShown = true
                    }
                }
        }

        @ViewBuilder func adjustmentsCancelOverrideView() -> some View {
            Image(systemName: "xmark.app")
                .font(.system(size: 24))
                .foregroundStyle(Color.primary, Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569))
                .confirmationDialog(
                    "Stop the Override \"\(latestOverride.first?.name ?? "")\"?",
                    isPresented: $isConfirmStopOverridePresented,
                    titleVisibility: .visible
                ) {
                    Button("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestOverride.first?.objectID else { return }
                            await state.cancelOverride(withID: objectID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .onTapGesture {
                    if !latestOverride.isEmpty {
                        isConfirmStopOverridePresented = true
                    }
                }
        }

        @ViewBuilder func noActiveAdjustmentsView() -> some View {
            Group {
                VStack {
                    Text("No Active Adjustment")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Profile at 100 %")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 10)

                Spacer()

                /// to ensure the same position....
                Image(systemName: "xmark.app")
                    .font(.title)
                    // clear color for the icon
                    .foregroundStyle(Color.clear)
            }.onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentView(geo: GeometryProxy) -> some View {
//            let background = colorScheme == .dark ? Material.ultraThinMaterial.opacity(0.5) : Color.black.opacity(0.2)

            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        (overrideString != nil || tempTargetString != nil) ?
                            (
                                colorScheme == .dark ?
                                    Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) :
                                    Color.insulin.opacity(0.1)
                            ) : Color.clear // Use clear and add the Material in the background
                    )
                    .background(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.35 : 0))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: geo.size.height * 0.06)
                    .shadow(
                        color: (overrideString != nil || tempTargetString != nil) ?
                            (
                                colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                                    Color.black.opacity(0.33)
                            ) : Color.clear,
                        radius: 3
                    )
                HStack {
                    if let overrideString = overrideString, let tempTargetString = tempTargetString {
                        HStack {
                            adjustmentsOverrideView(overrideString)

                            Spacer()

                            Divider()
                                .frame(height: geo.size.height * 0.05)
                                .padding(.horizontal, 2)

                            adjustmentsTempTargetView(tempTargetString)

                            Spacer()

                            adjustmentsCancelView({
                                if !latestTempTarget.isEmpty, !latestOverride.isEmpty {
                                    showCancelConfirmDialog = true
                                } else if !latestOverride.isEmpty {
                                    showCancelAlert = true
                                } else if !latestTempTarget.isEmpty {
                                    showCancelAlert = true
                                }
                            })
                        }
                    } else if let overrideString = overrideString {
                        adjustmentsOverrideView(overrideString)
                        Spacer()
                        adjustmentsCancelOverrideView()

                    } else if let tempTargetString = tempTargetString {
                        HStack {
                            adjustmentsTempTargetView(tempTargetString)
                            Spacer()
                            adjustmentsCancelTempTargetView()
                        }
                    } else {
                        noActiveAdjustmentsView()
                    }
                }.padding(.horizontal, 10)
                    .confirmationDialog("Adjustment to Stop", isPresented: $showCancelConfirmDialog) {
                        Button("Stop Override", role: .destructive) {
                            Task {
                                guard let objectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: objectID)
                            }
                        }
                        Button("Stop Temp Target", role: .destructive) {
                            Task {
                                guard let objectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: objectID)
                            }
                        }
                        Button("Stop All Adjustments", role: .destructive) {
                            Task {
                                guard let overrideObjectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: overrideObjectID)

                                guard let tempTargetObjectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: tempTargetObjectID)
                            }
                        }
                    } message: {
                        Text("Select Adjustment")
                    }
            }.padding(.horizontal, 10)
                .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 10))
        }

        @ViewBuilder func bolusProgressBar(_ progress: Decimal) -> some View {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 15)
                    .frame(height: 6)
                    .foregroundColor(.clear)
                    .background(
                        LinearGradient(colors: [
                            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902),
                            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
                            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
                            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
                            Color(red: 0.7215686275, green: 0.3411764706, blue: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                            .mask(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 15)
                                    .frame(width: geo.size.width * CGFloat(progress))
                            }
                    )
            }
        }

        @ViewBuilder func bolusProgressView(geo: GeometryProxy, _ progress: Decimal) -> some View {
            /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
            /// - TRUE:  show the pump bolus
            /// - FALSE:  do not show a progress bar at all
            if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
                let bolusFraction = progress * (bolusTotal as Decimal)
                let bolusString =
                    (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                        + String(localized: " of ", comment: "Bolus string partial message: 'x U of y U' in home view") +
                        (bolusProgressFormatter.string(from: bolusTotal as NSNumber) ?? "0")
                        + String(localized: " U", comment: "Insulin unit")

                ZStack {
                    /// rectangle as background
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) : Color
                                .insulin
                                .opacity(0.1)
                        )
                        .background(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.35 : 0))
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .frame(height: geo.size.height * 0.06)
                        .shadow(
                            color: (overrideString != nil || tempTargetString != nil) ?
                                (
                                    colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                                        Color.black.opacity(0.33)
                                ) : Color.clear,
                            radius: 3
                        )

                    /// actual bolus view
                    HStack {
                        Image("bolus")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 25, height: 25)
                            .foregroundColor(Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902))

                        Spacer()
                        Group {
                            Text("Bolusing")
                                .font(.subheadline)
                            Text(bolusString)
                                .font(.subheadline)
                        }.padding(.leading, 5)

                        Spacer()

                        Button {
                            state.showProgressView()
                            state.cancelBolus()
                        } label: {
                            Image(systemName: "xmark.app")
                                .font(.system(size: 25))
                                .foregroundStyle(Color.primary, Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902))
                        }
                    }.padding(.horizontal, 10)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 10))
                .overlay(alignment: .bottom) {
                    let offset = geo.size.height * 0.045
                    bolusProgressBar(progress)
                        .padding(.leading, 42)
                        .padding(.trailing, 50)
                        .offset(y: offset)
                }.clipShape(RoundedRectangle(cornerRadius: 15))
            }
        }

        @ViewBuilder func alertSafetyNotificationsView(geo: GeometryProxy) -> some View {
            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        Color(
                            red: 0.9,
                            green: 0.133333333,
                            blue: 0.2156862745
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: geo.size.height * safeAreaSize)
                    .coordinateSpace(name: "alertSafetyNotificationsView")
                    .shadow(
                        color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                            Color.black.opacity(0.33),
                        radius: 3
                    )
                HStack {
                    Spacer()
                    VStack {
                        Text("⚠️ Safety Notifications are OFF")
                            .font(.headline)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.gradient)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Fix now by turning Notifications ON.")
                            .font(.footnote)
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.gradient)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.leading, 5)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.white)
                        .font(.headline)
                }.padding(.horizontal, 10)
                    .padding(.trailing, 8)
                    .onTapGesture {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
            }.padding(.horizontal, 10)
                .padding(.top, 0)
        }

        @ViewBuilder func mainViewElements(_ geo: GeometryProxy) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    /// glucose bobble
                    glucoseView

                    /// right panel with loop status and evBG
                    HStack {
                        Spacer()
                        rightHeaderPanel(geo)
                    }.padding(.trailing, 20)

                    /// left panel with meal related info
                    HStack {
                        leftHeaderPanel(geo)
                        Spacer()
                    }.padding(.leading, 20)
                }
                .padding(.top, 10)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if notificationsDisabled {
                        alertSafetyNotificationsView(geo: geo)
                    }
                    if let badgeImage = state.pumpStatusBadgeImage, let badgeColor = state.pumpStatusBadgeColor {
                        pumpTimezoneView(badgeImage, badgeColor)
                            .padding(.horizontal, 20)
                    }
                }

//                mealPanel(geo).padding(.top, UIDevice.adjustPadding(min: nil, max: 30))
//                    .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 20))

                horizontalPumpView
                    .padding(.top, UIDevice.adjustPadding(min: nil, max: 10))
                    .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 10))

                mainChart(geo: geo)

                timeIntervalPanel
                    .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 6))

//                HStack {
//                    tappableButton(
//                        buttonColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.8),
//                        label: String(localized: "Stats", comment: "Stats icon in main view"),
//                        iconString: statsIconString,
//                        action: { state.showModal(for: .statistics) }
//                    )
//
//                    Spacer()
//
//                    timeIntervalButtons.padding(.top, UIDevice.adjustPadding(min: 0, max: 10))
//                        .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 10))
//
//                    Spacer()
//
//                    tappableButton(
//                        buttonColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.8),
//                        label: String(localized: "Info", comment: "Info icon in main view"),
//                        iconString: "info",
//                        action: { state.isLegendPresented.toggle() }
//                    )
//                }
//                .padding(.horizontal)
//                .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 10))

                if let progress = state.bolusProgress {
                    bolusProgressView(geo: geo, progress)
                        .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 6))
                } else if overrideString != nil || tempTargetString != nil {
                    adjustmentView(geo: geo)
                        .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 6))
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onReceive(
                resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
                perform: {
                    if notificationsDisabled != $0 {
                        notificationsDisabled = $0
                        if notificationsDisabled {
                            debug(.default, "notificationsDisabled")
                        }
                    }
                }
            )
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                mainViewElements(geo)
            }
            .onChange(of: state.hours) {
                highlightButtons()
            }
            .onAppear {
                configureView {
                    highlightButtons()
                }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .blur(radius: state.isLoopStatusPresented ? 3 : 0)
//            .sheet(isPresented: $state.isLoopStatusPresented) {
//                LoopStatusView(state: state)
//            }
            .popup(isPresented: state.isStatusPopupPresented, alignment: .top, direction: .top) {
                VStack {
                    Rectangle().opacity(0).frame(height: 200)
                    popup
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color("Chart"))
                        )
                        .opacity(0.85)
                        .gesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onEnded { value in
                                    if value.translation.height < 0 {
                                        state.isStatusPopupPresented = false
                                    }
                                }
                        )
                }
            }
            .sheet(isPresented: $state.isLegendPresented) {
                ChartLegendView(state: state)
            }
            // PUMP RELATED
            .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                Button("Medtronic") { state.addPump(.minimed) }
                Button("Omnipod Eros") { state.addPump(.omnipod) }
                Button("Omnipod Dash") { state.addPump(.omnipodBLE) }
                Button("Dana(RS/-i)") { state.addPump(.dana) }
                Button("Pump Simulator") { state.addPump(.simulator) }
            } message: { Text("Select Pump Model") }
            .sheet(isPresented: $state.shouldDisplayPumpSetupSheet) {
                if let pumpManager = state.provider.apsManager.pumpManager {
                    PumpConfig.PumpSettingsView(
                        pumpManager: pumpManager,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                } else {
                    PumpConfig.PumpSetupView(
                        pumpType: state.setupPumpType,
                        pumpInitialSettings: PumpConfig.PumpInitialSettings.default,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            // CGM RELATED
            .confirmationDialog("CGM Model", isPresented: $showCGMSelection) {
                cgmSelectionButtons
            } message: {
                Text("Select CGM Model")
            }
            .sheet(isPresented: $state.shouldDisplayCGMSetupSheet) {
                switch state.cgmCurrent.type {
                case .enlite,
                     .nightscout,
                     .none,
                     .simulator,
                     .xdrip:
                    CGMSettings.CustomCGMOptionsView(
                        resolver: self.resolver,
                        state: state.cgmStateModel,
                        cgmCurrent: state.cgmCurrent,
                        deleteCGM: state.deleteCGM
                    )
                case .plugin:
                    if let fetchGlucoseManager = state.fetchGlucoseManager,
                       let cgmManager = fetchGlucoseManager.cgmManager,
                       state.cgmCurrent.type == fetchGlucoseManager.cgmGlucoseSourceType,
                       state.cgmCurrent.id == fetchGlucoseManager.cgmGlucosePluginId
                    {
                        CGMSettings.CGMSettingsView(
                            cgmManager: cgmManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state
                        )
                    } else {
                        CGMSettings.CGMSetupView(
                            CGMType: state.cgmCurrent,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state,
                            setupDelegate: state,
                            pluginCGMManager: self.state.pluginCGMManager
                        )
                    }
                }
            }
        }

        @ViewBuilder func tabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                              state.showCarbsRequiredBadge
                        else {
                            return nil
                        }
                        let carbsRequiredDecimal = Decimal(carbsRequired)
                        if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                            return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
                        }
                        return nil
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Main", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)

                    NavigationStack { DataTable.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: historySFSymbol) }.tag(1)

                    Spacer()

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Adjustments",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(2)

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .tabItem { Label(
                            "Settings",
                            systemImage: "gear"
                        ) }.tag(3)
                }
                .tint(Color.tabBar)

                Button(
                    action: {
                        state.showModal(for: .bolus) },
                    label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.tabBar)
                            .padding(.bottom, 1)
                            .padding(.horizontal, 22.5)
                    }
                )
            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
                .onChange(of: selectedTab) {
                    if !settingsPath.isEmpty {
                        settingsPath = NavigationPath()
                    }
                }
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: String(localized: "Updating IOB...", comment: "Progress text when updating IOB"))
                }
            }
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitlePopup).font(.headline).foregroundColor(.primary)
                    .padding(.bottom, 4)

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Group {
                        Text("Error During Algorithm Run at \(Formatter.dateFormatter.string(from: date))").font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }.foregroundColor(.loopRed)
                }

                if let determination = state.determinationsFromPersistence.first {
                    if determination.glucose == 400 {
                        Text("Invalid CGM reading (HIGH).")
                            .bold()
                            .padding(.top)
                            .foregroundStyle(Color.loopRed)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SMBs and Non-Zero Temp. Basal Rates are disabled.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                    } else {
                        let tags = !state.isSmoothingEnabled ? determination.reasonParts : determination
                            .reasonParts + ["Smoothing: On"]
                        TagCloudView(
                            tags: tags,
                            shouldParseToMmolL: state.units == .mmolL
                        )
                        .animation(.none, value: false)
                        Text("Algorithm reasoning").font(.headline).foregroundColor(.primary)
                            .padding(.vertical, 4)
//                        Text(
//                            self
//                                .parseReasonConclusion(
//                                    determination.reasonConclusion,
//                                    isMmolL: state.units == .mmolL
//                                )
//                        ).font(.subheadline).foregroundColor(.white)
                        Text(determination.reasonConclusion)
                            .font(.subheadline).foregroundColor(.primary)
                    }
                } else {
                    Text("No Algorithm result").font(.body).foregroundColor(.primary)
                }

                Button {
                    state.isStatusPopupPresented = false
                } label: {
                    Text("Got it!")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
        }

        private func setStatusTitlePopup() {
            if let determination = state.determinationsFromPersistence.first {
                let dateFormatter = DateFormatter()
                dateFormatter.timeStyle = .short
                statusTitlePopup = String(localized: "oref enacted at", comment: "Headline in enacted pop up") +
                    " " +
                    dateFormatter
                    .string(from: determination.deliverAt ?? Date())
            } else {
                statusTitlePopup = "No oref result"
                return
            }
        }
    }
}

extension UIDevice {
    public enum DeviceSize: CGFloat {
        case smallDevice = 667 // Height for 4" iPhone SE
        case largeDevice = 852 // Height for 6.1" iPhone 15 Pro
    }

    @usableFromInline static func adjustPadding(
        min: CGFloat? = nil,
        max: CGFloat? = nil
    ) -> CGFloat? {
        if UIScreen.screenHeight > UIDevice.DeviceSize.smallDevice.rawValue {
            if UIScreen.screenHeight >= UIDevice.DeviceSize.largeDevice.rawValue {
                return max
            } else {
                return min != nil ?
                    (max != nil ? max! * (UIScreen.screenHeight / UIDevice.DeviceSize.largeDevice.rawValue) : nil) : nil
            }
        } else {
            return min
        }
    }
}

extension UIScreen {
    static var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }

    static var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }
}

/// Checks if the device is using a 24-hour time format.
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

/// Converts a duration in minutes to a formatted string (e.g., "1 h 30 m").
func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m)\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
    case let (h, 0):
        return "\(h)\u{00A0}" + String(localized: "h", comment: "h")
    default:
        return hours.description + "\u{00A0}" + String(localized: "h", comment: "h") + "\u{00A0}" + minutes
            .description + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
    }
}

// Helper function to convert a start and end hour to either 24-hour or AM/PM format
func formatTimeRange(start: String?, end: String?) -> String {
    guard let start = start, let end = end else {
        return ""
    }

    // Check if the format is 24-hour or AM/PM
    if is24HourFormat() {
        // Return the original 24-hour format
        return "\(start)-\(end)"
    } else {
        // Convert to AM/PM format using DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"

        if let startHour = Int(start), let endHour = Int(end) {
            let startDate = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
            let endDate = Calendar.current.date(bySettingHour: endHour, minute: 0, second: 0, of: Date()) ?? Date()

            // Customize the format to "2p" or "2a"
            formatter.dateFormat = "ha"
            let startFormatted = formatter.string(from: startDate).lowercased().replacingOccurrences(of: "m", with: "")
            let endFormatted = formatter.string(from: endDate).lowercased().replacingOccurrences(of: "m", with: "")

            return "\(startFormatted)-\(endFormatted)"
        } else {
            return ""
        }
    }
}
