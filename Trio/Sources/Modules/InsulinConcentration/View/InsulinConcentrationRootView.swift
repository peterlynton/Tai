import Foundation
import SwiftUI
import Swinject

extension InsulinConcentration {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var showConfirmationDialog = false
        @State private var showSecondConfirmationDialog = false
        @State private var hasChanges = false

        @Environment(\.dismiss) var dismiss
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                List {
                    selectedConcentrationSection().listRowBackground(Color.chart)
                    concentrationPickerSection().listRowBackground(Color.chart)
                    if state.insulinConcentration < 1 || state.tempConcentration < 1 {
                        adjustLimtsForDiluted().listRowBackground(Color.chart)
                    }
                    saveButton()
                }
                .scrollContentBackground(.hidden)
                .tint(Color.tabBar)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .navigationTitle("Select Concentration")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear(perform: configureView)

                .confirmationDialog(
                    "Are you sure to switch to U\(Int(truncating: NSDecimalNumber(decimal: state.tempConcentration * 100)))?",
                    isPresented: $showConfirmationDialog,
                    titleVisibility: .visible
                ) {
                    Button("Confirm", role: .destructive) {
                        showSecondConfirmationDialog = true
                    }
                } message: {
                    Text(
                        "Ensure that the selected insulin concentration matches the vial or pen label. U\(Int(truncating: NSDecimalNumber(decimal: state.tempConcentration * 100))) means \(Int(truncating: NSDecimalNumber(decimal: state.tempConcentration * 100))) units per ml."
                    )
                }
                .confirmationDialog(
                    "Check your Basal Profile after adding Pump!",
                    isPresented: $showSecondConfirmationDialog,
                    titleVisibility: .visible
                ) {
                    Button("Got it!", role: .destructive) {
                        saveConcentrationAndDismiss()
                    }
                } message: {
                    Text(
                        "Switching insulin concentration changes the basal increments that can be delivered by pump. For diluted insulins smaller increments can be used. For high concentrations the increment will be larger than your regular U100 increment - this compulsory needs adjustment!\n\nBe aware that the pump managers will always show U100 as concentration setting, as they on their own currently only deal with U100. The seeting here in Tai will prevail nonetheless!"
                    )
                }
            }
        }

        func saveConcentrationAndDismiss() {
            state.saveChanges()
            dismiss()
        }

        @ViewBuilder func selectedConcentrationSection() -> some View {
            Section(header: Text("Insulin Concentration Selected")) {
                HStack {
                    Text("U\(Int(truncating: NSDecimalNumber(decimal: state.tempConcentration * 100)))")
                    if state.tempConcentration == 1 {
                        Text("- Standard Insulin 100 U/mL")
                    } else if state.tempConcentration < 1 {
                        Text(" - diluted Insulin")
                    } else {
                        Text("- higher custom concentration")
                    }
                }
            }
        }

        @ViewBuilder func concentrationPickerSection() -> some View {
            Section(header: Text("Change Setting")) {
                Picker("Insulin Concentration", selection: $state.tempConcentration) {
                    Text("200 U/mL").tag(Decimal(2))
                    Text("100 U/mL").tag(Decimal(1))
                    if state.allowDilution {
                        Text("50 U/mL").tag(Decimal(0.5))
                        Text("40 U/mL").tag(Decimal(0.4))
                        Text("10 U/mL").tag(Decimal(0.1))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: state.tempConcentration) { _ in
                    hasChanges = state.tempConcentration != state.insulinConcentration
                }
            }
        }

        @ViewBuilder func adjustLimtsForDiluted() -> some View {
            Section(header: Text("Adjust Limits for Diluted Insulin")) {
                VStack(spacing: 6) {
                    Text(
                        "When changing TO or FROM diluted insulins, please check whether you want to decrease (TO) or increase (FROM):"
                    )
                    BulletList(
                        listItems: [
                            "Maximum Insulin on Board",
                            "Maximum Bolus",
                            "Maximum Basal Rate"
                        ],
                        listItemSpacing: 10
                    )
                    Text(
                        "as often diluted insulins are used for patients with small insulin dosing requirements."
                    )
                    Text(
                        "You can change these settings in Therapy > Units and Limits after saving the new concentration and after you have added a pump!"
                    )
                }
            }
        }

        @ViewBuilder func saveButton() -> some View {
            HStack {
                Spacer()
                Button("Save") {
                    showConfirmationDialog = true
                }
                .disabled(!hasChanges)
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)
                Spacer()
            }
            .listRowBackground(hasChanges ? Color(.systemBlue) : Color(.systemGray4))
        }
    }
}
