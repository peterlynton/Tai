import Charts
import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var editMode = EditMode.inactive
        @State private var shouldDisplayHint: Bool = false
        @State private var hintDetent = PresentationDetent.fraction(0.9)

        let chartScale = Calendar.current
            .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))
        let tzOffset = TimeZone.current.secondsFromGMT()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal

            return formatter
        }

        var now = Date()
        var basalScheduleChart: some View {
            Chart {
                ForEach(state.chartData!, id: \.self) { profile in
                    let startDate = Calendar.current.startOfDay(for: now)
                        .addingTimeInterval(profile.startDate.timeIntervalSinceReferenceDate + Double(tzOffset))
                    let endDate = Calendar.current.startOfDay(for: now)
                        .addingTimeInterval(profile.endDate!.timeIntervalSinceReferenceDate + Double(tzOffset))
                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", profile.amount),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                profile.isOverwritten ? Color.orange.opacity(0.5) : Color.teal.opacity(0.6),
                                Color.teal.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", endDate), y: .value("Amount", profile.amount))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                    LineMark(x: .value("Start Date", startDate), y: .value("Amount", profile.amount))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar
                    .current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        Button(action: {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        }, label: {
                            HStack {
                                if state.syncInProgress {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.syncInProgress ? "Saving..." : "Save to Pump")
                            }
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                            .disabled(shouldDisableButton)
                            .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var body: some View {
            Form {
                if !state.canAdd {
                    Section {
                        VStack(alignment: .leading) {
                            Text(
                                "Basal profile covers 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                            ).bold()
                        }
                    }.listRowBackground(Color.tabBar)
                }

                Section(header: Text("Concentration")) {
                    // Grid layout for macronutrient values
                    Grid(alignment: .trailing) {
                        GridRow {
                            Text("Insulin Concentration:").foregroundStyle(Color.secondary)
                                .gridColumnAlignment(.leading)
                            Text("U\(Int(truncating: NSDecimalNumber(decimal: state.concentration * 100)))")
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(Color.tabBar)
                                .onTapGesture {
                                    shouldDisplayHint = true
                                }
                        }
                        GridRow {
                            Text("Pump supported increment:").foregroundStyle(Color.secondary)
                                .gridColumnAlignment(.leading)
                            Text("\(rateFormatter.string(from: state.pumpIncrement * 10 as NSNumber) ?? "0")")
                            Text("μL/hr").foregroundStyle(Color.secondary)
                        }
                        Divider()
                        GridRow {
                            Text("Available basal increment:")
                                .gridColumnAlignment(.leading)
                            Text("\(rateFormatter.string(from: state.basalIncrement as NSNumber) ?? "0")")
                            Text("U/hr").foregroundStyle(Color.secondary)
                        }.bold()
                    }
                }.listRowBackground(Color.chart)

                if state.roundingHint {
                    Section(header: Text("Warning")) {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("Some basal rates have been rounded down to match the new increment.")
                            }
                            Divider()
                            Text("Make sure to Check & Save new Basal Profile!")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }
                    }.listRowBackground(Color.tabBar)
                }

                Section(header: Text("Schedule")) {
                    if !state.items.isEmpty {
                        basalScheduleChart.padding(.vertical)
                    }

                    list
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                            .foregroundColor(.primary) +
                            Text(" U/day")
                            .foregroundColor(.secondary)
                    }
                }.listRowBackground(Color.chart)

                Section {} header: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "note.text.badge.plus").foregroundStyle(.primary)
                            Text("Add an entry by tapping 'Add Rate +' in the top right-hand corner of the screen.")
                        }
                        HStack {
                            Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                            Text("Swipe to delete a single entry. Tap on it, to edit its time or rate.")
                        }
                    }
                    .textCase(nil)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 30) { saveButton }
            .alert(isPresented: $state.showAlert) {
                Alert(
                    title: Text("Unable to Save"),
                    message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                    dismissButton: .default(Text("Close"))
                )
            }
            .onChange(of: state.items) {
                state.calcTotal()
                state.calculateChartData()
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Basal Rates")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { state.add() }) {
                        HStack {
                            Text("Add Rate")
                            Image(systemName: "plus")
                        }
                    }.disabled(!state.canAdd)
                }
            })
            .environment(\.editMode, $editMode)
            .onAppear {
                configureView()
                state.validate()
                state.calculateChartData()
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: "Concentration & Basal Increment",
                    hintText: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Standard insulin concentration is U100 (100 units per mL), which is the baseline for most insulin pump delivery systems. To show this increment independent of units delivered, it can be shown as volume in μL/hr. The Pump Increment in μL/hr =  10 * Pump Increment in standard units/hr "
                            )
                            .font(.system(size: 16))

                            BulletList(
                                listItems: [
                                    "U100 Concentration (Standard): Pumps typically have standard insulin delivery increments based on this concentration.",
                                    "Diluted Insulin: Lower concentration allows for finer insulin increments (more granular delivery options).",
                                    "Higher Concentration: Each pump increment delivers more insulin units, reducing granularity.",
                                    "Basal increment varies based on the insulin concentration in your cartridge."
                                ],
                                listItemSpacing: 10
                            )

                            Text("Example:")
                                .font(.subheadline)
                                .padding(.top, 5)

                            Text(
                                "• In U100 insulin: 0.1 U increment delivers 0.1 units\n• In U50 insulin: 0.1 U increment delivers 0.05 units\n• In U200 insulin: 0.1 U increment delivers 0.2 units"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    ),
                    sheetTitle: "Insulin Concentration"
                )
            }
        }

        private func pickers(for index: Int) -> some View {
            Form {
                Section {
                    Picker(selection: $state.items[index].rateIndex, label: Text("Rate")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                (self.rateFormatter.string(from: state.rateValues[i] as NSNumber) ?? "") + " " +
                                    String(localized: "U/hr")
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].rateIndex, { state.calcTotal() })
                }.listRowBackground(Color.chart)

                Section {
                    Picker(selection: $state.items[index].timeIndex, label: Text("Time")) {
                        ForEach(state.availableTimeIndices(index), id: \.self) { i in
                            Text(
                                self.dateFormatter
                                    .string(from: Date(
                                        timeIntervalSince1970: state
                                            .timeValues[i]
                                    ))
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].timeIndex, { state.calcTotal() })
                }.listRowBackground(Color.chart)
            }
            .padding(.top)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Set Rate")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate")
                                .foregroundColor(.secondary)

                            // Check if this rate was rounded down
                            if let originalIndex = state.provider.profile.firstIndex(where: { originalEntry in
                                let originalTimeIndex = state.timeValues.firstIndex(of: Double(originalEntry.minutes * 60)) ?? -1
                                return originalTimeIndex == item.timeIndex
                            }),
                                state.roundedRateIndices.contains(originalIndex)
                            {
                                let originalRate = state.provider.profile[originalIndex].rate
                                let currentRate = state.rateValues[item.rateIndex]

                                Text(
                                    "\(rateFormatter.string(from: originalRate as NSNumber) ?? "0") → \(rateFormatter.string(from: currentRate as NSNumber) ?? "0") U/hr"
                                )
                                .foregroundColor(.insulin)
                            } else {
                                Text("\(rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") U/hr")
                            }

                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
                            )
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
            state.calculateChartData()
        }
    }
}
