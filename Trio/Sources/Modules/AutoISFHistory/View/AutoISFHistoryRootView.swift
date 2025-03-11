import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

extension AutoISFHistory {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @Environment(\.horizontalSizeClass) var sizeClass
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.managedObjectContext) var context

        @State private var selectedEndTime = Date()
        @State private var selectedTimeIntervalIndex = 1 // Default to 2 hours
        @State private var timeIntervalOptions = []
        @State private var autoISFResults: [AutoISFHistory] = [] // Holds the fetched results

        @State private var selectedEntry: autoISFHistory? // Track selected entry
        @State private var isPopupPresented = false
        @State private var tapped: Bool = false

        private var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.011, green: 0.058, blue: 0.109),
                    Color(red: 0.03921568627, green: 0.1333333333, blue: 0.2156862745)
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
                :
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.1)]), startPoint: .top, endPoint: .bottom)
        }

        private let itemFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter
        }()

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal

            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.minimumFractionDigits = 1
                formatter.roundingMode = .halfUp
            } else {
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        @ViewBuilder func historyISF() -> some View {
            autoISFview
        }

        var slots: CGFloat = 9 // Adjusted for new column count
        var slotwidth: CGFloat = 1

        var body: some View {
            VStack {
                HStack {
                    if !tapped {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                            Text(String(
                                localized: "Tap an entry row for details.",
                                comment: "Text prompting user to tap an entry row for details"
                            ))
                        }
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                    }
                    CustomDateTimePicker(selection: $state.selectedEndTime, minuteInterval: 15)
                        .frame(height: 40)
                    Spacer()
                    Picker("", selection: $state.selectedTimeIntervalIndex) {
                        ForEach(0 ..< state.timeIntervalOptions.count, id: \.self) { index in
                            Text("\(state.timeIntervalOptions[index])h").tag(index)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal)

                GeometryReader { geometry in
                    VStack(alignment: .leading) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(String(localized: "ISF factors", comment: "Label for ISF factors section")).foregroundColor(.uam)
                                .frame(width: 5 * slotwidth / slots * geometry.size.width, alignment: .center)
                            Text(String(localized: "Insulin", comment: "Label for Insulin section")).foregroundColor(.insulin)
                                .frame(width: 4 * slotwidth / slots * geometry.size.width, alignment: .center)
                        }
                        HStack(alignment: .bottom) {
                            Group {
                                Spacer()
                                Text(String(localized: "Time", comment: "Label for Time"))
                                Text(String(localized: "BG", comment: "Label for BG")).foregroundColor(.loopGreen)
                            }
                            Spacer()
                            Group {
                                Text(String(localized: "final", comment: "Label for final")).bold().foregroundColor(.uam)
                                Spacer()
                                Text(String(localized: "acce", comment: "Label for acce")).foregroundColor(.loopYellow)
                                Spacer()
                                Text(String(localized: "bg", comment: "Label for bg")).foregroundColor(.loopYellow)
                                Spacer()
                                Text(String(localized: "pp", comment: "Label for pp")).foregroundColor(.loopYellow)
                                Spacer()
                                Text(String(localized: "dura", comment: "Label for dura")).foregroundColor(.loopYellow)
                            }
                            Spacer()
                            Group {
                                Text(String(localized: "req.", comment: "Label for req.")).foregroundColor(.secondary)
                                Spacer()
                                Text(String(localized: "SMB", comment: "Label for SMB")).foregroundColor(.insulin)
                            }
                        }
                        .frame(width: 0.95 * geometry.size.width)
                        Divider()
                        historyISF()
                    }
                }
            }

            .font(.caption)
            .onAppear(perform: configureView)
            .navigationBarTitle("")
            .navigationBarItems(leading: Button(action: state.hideModal) {
                Text(String(localized: "Close", comment: "Close button label"))
                    .foregroundColor(Color.tabBar) })
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .overlay(
                popupView(), alignment: .bottom
            )
        }

        private func convertGlucose(_ value: Decimal, to units: GlucoseUnits) -> Double { // Use 'GlucoseUnits'
            switch units {
            case .mmolL:
                return Double(value) * 0.0555
            case .mgdL:
                return Double(value)
            }
        }

        var autoISFview: some View {
            GeometryReader { geometry in
                List {
                    ForEach(state.autoISFEntries, id: \.self) { entry in
                        HStack(spacing: 2) {
                            Text(Formatter.timeFormatter.string(from: entry.timestamp ?? Date()))
                                .frame(width: 0.8 / slots * geometry.size.width, alignment: .leading)

                            let displayGlucose = convertGlucose(entry.bg ?? 0, to: state.units)
                            Text(glucoseFormatter.string(from: NSNumber(value: displayGlucose)) ?? "")
                                //                            Text("\(entry.bg ?? 0)")
                                .foregroundColor(.loopGreen)
                                .frame(width: 0.8 / slots * geometry.size.width, alignment: .leading)
                            Group {
                                Text("\(entry.autoISF_ratio ?? 1)").foregroundColor(.uam)
                                Text("\(entry.acce_ratio ?? 1)").foregroundColor(.loopYellow)
                                Text("\(entry.bg_ratio ?? 1)").foregroundColor(.loopYellow)
                                Text("\(entry.pp_ratio ?? 1)").foregroundColor(.loopYellow)
                                Text("\(entry.dura_ratio ?? 1)").foregroundColor(.loopYellow)
                            }
                            .frame(width: 0.9 * slotwidth / slots * geometry.size.width, alignment: .center)
                            Group {
                                Text("\(entry.insulin_req ?? 0)").foregroundColor(.secondary)
                                Text("\(entry.smb ?? 0)").foregroundColor(.insulin)
                            }
                            .frame(width: 0.85 * slotwidth / slots * geometry.size.width, alignment: .center)
                        }
                        .contentShape(Rectangle()) // Make the row tappable
                        .onTapGesture {
                            tapped = true
                            selectedEntry = entry // Update selected row
                            isPopupPresented = true // Show popup
                        }
                    }.listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .listStyle(PlainListStyle())
            }.navigationBarTitle(Text("autoISF History"), displayMode: .inline)
        }

        @ViewBuilder private func popupView() -> some View {
            if isPopupPresented, let entry = selectedEntry {
                VStack {
                    Spacer().frame(height: 200) // Adds spacing at the top

                    DetailPopupView(
                        entry: entry,
                        isPopupPresented: $isPopupPresented,
                        units: state.units,
                        maxIOB: state.maxIOB,
                        iobThresholdPercent: state.iobThresholdPercent,
                        entries: state.autoISFEntries, // Pass all entries
                        selectedEntry: $selectedEntry, // Pass selected entry
                        moveToPreviousEntry: moveToPreviousEntry, // Pass function
                        moveToNextEntry: moveToNextEntry // Pass function
                    )
                    .transition(.move(edge: .top))
                    .animation(.easeInOut)
                }
                .frame(maxWidth: .infinity)
                .edgesIgnoringSafeArea(.top)
            }
        }

        // Get index of current entry
        private var currentIndex: Int? {
            state.autoISFEntries.firstIndex(where: { $0 == selectedEntry })
        }

        // Check if Up button is possible
        private var canMoveUp: Bool {
            if let index = currentIndex {
                return index > 0
            }
            return false
        }

        // Check if Down button is possible
        private var canMoveDown: Bool {
            if let index = currentIndex {
                return index < state.autoISFEntries.count - 1
            }
            return false
        }

        // Move to previous entry
        private func moveToPreviousEntry() {
            if let index = currentIndex, index > 0 {
                selectedEntry = state.autoISFEntries[index - 1]
            }
        }

        // Move to next entry
        private func moveToNextEntry() {
            if let index = currentIndex, index < state.autoISFEntries.count - 1 {
                selectedEntry = state.autoISFEntries[index + 1]
            }
        }
    }
}
