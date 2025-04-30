import SwiftUI
import Swinject

extension B30Settings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Enable"),
                    content: {
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableB30,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Activate B30 EatingSoon", comment: "Enable B30")
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: String(localized: "Activate B30 EatingSoon", comment: "Enable B30"),
                            miniHint: String(
                                localized:
                                "Enables an increased basal rate after an EatingSoon TT and a manual bolus to saturate the infusion site with insulin.",
                                comment: "Enable B30 miniHint"
                            ),
                            verboseHint: AnyView(
                                VStack(alignment: .leading) {
                                    Text(
                                        "Enables an increased basal rate after an EatingSoon TT and a manual bolus to saturate the infusion site with insulin to increase insulin absorption for SMB's following a meal with no carb counting."
                                    )
                                    BulletList(
                                        listItems: [
                                            "needs an EatingSoon TempTarget (TT) with a specific GlucoseTarget",
                                            "in order to activate B30 a minimum manual Bolus needs to be given",
                                            "you can specify how long B30 run and how high it is",
                                            "while B30 TBR runs no SMB's will be enacted",
                                            "TBR ignores maxBasal multipliers, but respects maxBasal of pump",
                                            "once activated you can stop the B30 TBR and allowing SMB's by just cancelling the TT"
                                        ],
                                        listItemSpacing: 10
                                    )
                                    Text(
                                        "Initiating B30 can be done by Apple Shortcuts\nhttps://tinyurl.com/aimiB30shortcut\n"
                                    )
                                }
                            )
                        )
                    }
                )
                if state.enableB30 {
                    Section(header: Text("B30 Settings")) {
                        SettingInputSection(
                            decimalValue: $state.B30iTimeTarget,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "TempTarget Level for B30", comment: "B30 TT Level")
                                }
                            ),
                            units: state.units,
                            type: .decimal("B30iTimeTarget"),
                            label: String(localized: "TempTarget Level for B30", comment: "B30 TT Level"),
                            miniHint: String(
                                localized:
                                "An EatingSoon TempTarget needs to be enabled to start B30 adaption. Set level for this target to be identified.",
                                comment: "B30 TT Level miniHint"
                            ),
                            verboseHint: AnyView(
                                Text(
                                    String(
                                        localized:
                                        "Set the EatingSoon TempTarget glucose level to trigger B30. Should be a low TT like \(state.units == .mgdL ? "80" : 80.formattedAsMmolL) \(state.units.rawValue). Keep in mind it should be an even TT to allow autoISF SMB's after the duration specified, if the target would still be active. Canceling this TT will imediatly stop B30 adaptions.",
                                        comment: "B30 TT Level VerboseHint"
                                    )
                                )
                            )
                        )
                        SettingInputSection(
                            decimalValue: $state.B30iTimeStartBolus,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Minimum Start Bolus Size", comment: "B30 Start Bolus")
                                }
                            ),
                            units: state.units,
                            type: .decimal("B30iTimeStartBolus"),
                            label: String(localized: "Minimum Start Bolus Size", comment: "B30 Start Bolus"),
                            miniHint: String(
                                localized:
                                "Minimum manual bolus to start a B30 adaption.",
                                comment: "B30 Start Bolus miniHint"
                            ),
                            verboseHint: AnyView(
                                Text(
                                    String(
                                        localized:
                                        "Specify the minimum bolus size required to trigger B30.",
                                        comment: "B30 Start Bolus VerboseHint"
                                    )
                                )
                            )
                        )
                        SettingInputSection(
                            decimalValue: $state.B30iTime,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Duration of Increased B30 Basal Rate", comment: "B30 Duration")
                                }
                            ),
                            units: state.units,
                            type: .decimal("B30iTime"),
                            label: String(localized: "Duration of Increased B30 Basal Rate", comment: "B30 Duration"),
                            miniHint: String(
                                localized:
                                "Duration of increased basal rate that saturates the infusion site with insulin. Default 30 minutes.",
                                comment: "B30 Duration miniHint"
                            ),
                            verboseHint: AnyView(
                                Text(
                                    String(
                                        localized:
                                        "Set the duration for the increased basal rate in B30 mode. Default is 30 minutes.",
                                        comment: "B30 Duration VerboseHint"
                                    )
                                )
                            )
                        )
                        SettingInputSection(
                            decimalValue: $state.B30basalFactor,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "B30 Basal Rate Increase Factor", comment: "B30 Factor")
                                }
                            ),
                            units: state.units,
                            type: .decimal("B30basalFactor"),
                            label: String(localized: "B30 Basal Rate Increase Factor", comment: "B30 Factor"),
                            miniHint: String(
                                localized:
                                "Factor that multiplies your regular basal rate from profile for B30. Max is 10. The TBR will ignore the maxBasalMultipliers but respect maxBasal setting!",
                                comment: "B30 Factor miniHint"
                            ),
                            verboseHint: AnyView(
                                Text(
                                    String(
                                        localized:
                                        "Specify the factor to increase the basal rate during B30. Max is 10x.",
                                        comment: "B30 Factor VerboseHint"
                                    )
                                )
                            )
                        )
                        SettingInputSection(
                            decimalValue: $state.B30upperLimit,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Upper BG Limit for B30", comment: "B30 Upper BG Limit")
                                }
                            ),
                            units: state.units,
                            type: .decimal("B30upperLimit"),
                            label: String(localized: "Upper BG Limit for B30", comment: "B30 Upper BG Limit"),
                            miniHint: String(
                                localized:
                                "B30 will only run & supress SMB as long as BG stays underneath that level. Default is \(state.units == .mgdL ? "130" : 130.formattedAsMmolL) \(state.units.rawValue).",
                                comment: "B30 Upper BG Limit miniHint"
                            ),
                            verboseHint: AnyView(
                                Text(
                                    String(
                                        localized:
                                        "Set the maximum BG level for B30 & suppressed SMB to remain active. Default is \(state.units == .mgdL ? "130" : 130.formattedAsMmolL) \(state.units.rawValue).",
                                        comment: "B30 Upper BG Limit VerboseHint"
                                    )
                                )
                            )
                        )
                        SettingInputSection(
                            decimalValue: $state.B30upperDelta,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Upper Delta Limit for B30", comment: "B30 Upper Delta")
                                }
                            ),
                            units: state.units,
                            type: .decimal("B30upperDelta"),
                            label: String(localized: "Upper Delta Limit for B30", comment: "B30 Upper Delta"),
                            miniHint: String(
                                localized:
                                "B30 will only run & supress SMB's as long as BG delta stays below that level. Default is \(state.units == .mgdL ? "8" : 8.formattedAsMmolL) \(state.units.rawValue).",
                                comment: "B30 Upper Delta miniHint"
                            ),
                            verboseHint: AnyView(
                                Text(
                                    String(
                                        localized:
                                        "Set the maximum BG delta limit for B30 & suppressed SMB to remain active. Default is \(state.units == .mgdL ? "8" : 8.formattedAsMmolL) \(state.units.rawValue).",
                                        comment: "B30 Upper Delta VerboseHint"
                                    )
                                )
                            )
                        )
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text(
                            "Enables an increased basal rate after an EatingSoon TT and a manual bolus to saturate the infusion site with insulin to increase insulin absorption for SMB's following a meal with no carb counting."
                        )
                        BulletList(
                            listItems: [
                                "needs an EatingSoon TempTarget (TT) with a specific GlucoseTarget",
                                "in order to activate B30 a minimum manual Bolus needs to be given",
                                "you can specify how long B30 run and how high it is",
                                "while B30 TBR runs no SMB's will be enacted",
                                "once activated you can stop the B30 TBR and allowing SMB's by just cancelling the TT"
                            ],
                            listItemSpacing: 10
                        )
                        Text(
                            "Initiating B30 can be done by Apple Shortcuts\nhttps://tinyurl.com/aimiB30shortcut\n"
                        )
                    }
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("AIMI B30 Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
