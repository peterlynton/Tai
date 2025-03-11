import Foundation
import SwiftUI
import Swinject

extension InsulinConcentration {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var showConfirmationDialog = false
        @State private var hasChanges = false

        @Environment(\.dismiss) var dismiss
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                List {
                    selectedConcentrationSection().listRowBackground(Color.chart)
                    concentrationPickerSection().listRowBackground(Color.chart)

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
                    Button("Confirm", role: .destructive) { saveConcentrationAndDismiss() }
                } message: {
                    Text(
                        "Ensure that the selected insulin concentration matches the vial or pen label. U\(Int(truncating: NSDecimalNumber(decimal: state.tempConcentration * 100))) means \(Int(truncating: NSDecimalNumber(decimal: state.tempConcentration * 100))) units per ml."
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
                        Text("10 U/mL").tag(Decimal(0.1))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: state.tempConcentration) { _ in
                    hasChanges = state.tempConcentration != state.insulinConcentration
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
