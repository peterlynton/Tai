import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State private var showConcentrationEditor = false
        @State private var showEditConcentrationWarning = false
        @State private var shouldDisplayHint: Bool = false
        @State private var shouldDisplayHintPump: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showPumpSelection: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                List {
                    Section(
                        content: {
                            VStack {
                                if state.pumpState == nil {
                                    HStack {
                                        Text("Current Concentration")
                                        Spacer()
                                        Text(
                                            "U\(Int(truncating: NSDecimalNumber(decimal: state.insulinConcentration * 100)))"
                                        )
                                    }
                                    .contentShape(Rectangle()) // Ensures full-row tappability
                                    .navigationLink(to: .insulinConcentration, from: self)
                                } else {
                                    HStack {
                                        Text("Current Concentration")
                                        Spacer()
                                        Text("U\(Int(truncating: NSDecimalNumber(decimal: state.insulinConcentration * 100)))")
                                    }.foregroundColor(.secondary)
                                        .onTapGesture { showEditConcentrationWarning = true }
                                }

                                HStack(alignment: .center) {
                                    Text(
                                        "The insulin concentration is given in Insulin Units per mL. The standard is U100 with 100 U/mL."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(action: {
                                        shouldDisplayHint.toggle()
                                        selectedVerboseHint = AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text("Delete pump if you need to change Insulin Concentration")
                                                    .fontWeight(.bold)
                                                Text(
                                                    "The insulin concentration can only be changed if you change the insulin in your pump. To make that sure for every pump model, you will have to delete the current pump, change the Insulin Concentration and add your pump again."
                                                )
                                            }
                                        )
                                        hintLabel = String(
                                            localized:
                                            "Insulin Concentration",
                                            comment: "Insulin Concentration"
                                        )
                                    }) { HStack { Image(systemName: "questionmark.circle") }}
                                        .buttonStyle(BorderlessButtonStyle())
                                }.padding(.vertical)
                            }
                        },
                        header: { Text("Insulin Concentration") }
                    )
                    .listRowBackground(Color.chart)
                    .alert(isPresented: $showEditConcentrationWarning) {
                        Alert(
                            title: Text("Cannot change Concentration"),
                            message: Text("To edit insulin concentration, you must first remove the pump."),
                            dismissButton: .default(Text("Got it!"))
                        )
                    }

                    Section(
                        header: Text("Pump Integration to Trio"),
                        content: {
                            if let pumpState = state.pumpState {
                                Button {
                                    state.setupPump = true
                                } label: {
                                    HStack {
                                        Image(uiImage: pumpState.image ?? UIImage())
                                        Text(pumpState.name)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                                    .font(.title2)
                                }.padding()
                                if state.alertNotAck {
                                    Spacer()
                                    Button("Acknowledge all alerts") { state.ack() }
                                }
                            } else {
                                VStack {
                                    Button {
                                        showPumpSelection.toggle()
                                    } label: {
                                        Text("Add Pump")
                                            .font(.title3) }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .buttonStyle(.bordered)

                                    HStack(alignment: .center) {
                                        Text(
                                            "Pair your insulin pump with Trio. See hint for compatible devices."
                                        )
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        Spacer()
                                        Button(
                                            action: {
                                                shouldDisplayHintPump.toggle()
                                            },
                                            label: {
                                                HStack {
                                                    Image(systemName: "questionmark.circle")
                                                }
                                            }
                                        ).buttonStyle(BorderlessButtonStyle())
                                    }.padding(.top)
                                }.padding(.vertical)
                            }
                        }
                    )
                    .listRowBackground(Color.chart)

                    Section(
                        header: Text("Insulin Curve Parameters"),
                        content: {
                            SettingInputSection(
                                decimalValue: $state.insulinActionCurve,
                                booleanValue: $booleanPlaceholder,
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(
                                            localized: "Duration of Insulin Action",
                                            comment: "Duration of Insulin Action"
                                        )
                                    }
                                ),
                                units: state.units,
                                type: .decimal("dia"),
                                label: String(localized: "Duration of Insulin Action", comment: "Duration of Insulin Action"),
                                miniHint: String(
                                    localized: "Number of hours insulin is active in your body.",
                                    comment: "Mini Hint for Duration of Insulin Action"
                                ),
                                verboseHint:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Default: 10 hours").bold()
                                    Text(
                                        "The Duration of Insulin Action (DIA) defines how long your insulin continues to lower glucose readings after a dose."
                                    )
                                    Text(
                                        "This helps the system accurately track Insulin on Board (IOB), avoiding over- or under-corrections by considering the tail end of insulin's effect."
                                    )
                                    Text(
                                        "Tip: It is better to use Custom Peak Time rather than adjust your Duration of Insulin Action (DIA)."
                                    )
                                }
                            )

                            SettingInputSection(
                                decimalValue: $state.insulinPeakTime,
                                booleanValue: $state.useCustomPeakTime,
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(localized: "Use Custom Peak Time", comment: "Use Custom Peak Time")
                                    }
                                ),
                                units: state.units,
                                type: .conditionalDecimal("insulinPeakTime"),
                                label: String(localized: "Use Custom Peak Time", comment: "Use Custom Peak Time"),
                                conditionalLabel: String(localized: "Insulin Peak Time", comment: "Insulin Peak Time"),
                                miniHint: "Set a custom time for peak insulin effect.",
                                verboseHint:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Default: Set by Insulin Type").bold()
                                    Text(
                                        "Insulin Peak Time defines when insulin is most effective in lowering glucose, set in minutes after dosing."
                                    )
                                    Text(
                                        "This peak informs the system when to expect the most potent glucose-lowering effect, helping it predict glucose trends more accurately."
                                    )
                                    Text("System-Determined Defaults:").bold()
                                    Text("Ultra-Rapid: 55 minutes (permitted range 35-100 minutes)")
                                    Text("Rapid-Acting: 75 minutes (permitted range 50-120 minutes)")
                                }
                            )
                        }
                    )
                }
                .listSectionSpacing(sectionSpacing)
                .tint(Color.tabBar)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .onAppear {
                    state.insulinConcentration = state.settings.settings.insulinConcentration
                }
                .onDisappear {
                    state.saveIfChanged()
                }
                .navigationTitle("Insulin Pump")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                        sheetTitle: "Help"
                    )
                }
                .sheet(isPresented: $state.setupPump) {
                    if let pumpManager = state.provider.apsManager.pumpManager {
                        PumpSettingsView(
                            pumpManager: pumpManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    } else {
                        PumpSetupView(
                            pumpType: state.setupPumpType,
                            pumpInitialSettings: state.initialSettings,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    }
                }
                .sheet(isPresented: $shouldDisplayHintPump) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHintPump,
                        hintLabel: "Pump Pairing to Trio",
                        hintText: AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Current Pump Models Supported:"
                                )
                                VStack(alignment: .leading) {
                                    Text("• Medtronic")
                                    Text("• Omnipod Eros")
                                    Text("• Omnipod Dash")
                                    Text("• Dana (RS/-i)")
                                    Text("• Pump Simulator")
                                }
                                Text(
                                    "Note: If using a pump simulator, you will not have continuous readings from the CGM in Trio. Using a pump simulator is only advisable for becoming familiar with the app user interface. It will not give you insight on how the algorithm will respond."
                                )
                            }
                        ),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
                    )
                }
                .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                    Button("Medtronic") { state.addPump(.minimed) }
                    Button("Omnipod Eros") { state.addPump(.omnipod) }
                    Button("Omnipod Dash") { state.addPump(.omnipodBLE) }
                    Button("Dana(RS/-i)") { state.addPump(.dana) }
                    Button("Pump Simulator") { state.addPump(.simulator) }
                } message: { Text("Select Pump Model") }
            }
        }
    }
}
