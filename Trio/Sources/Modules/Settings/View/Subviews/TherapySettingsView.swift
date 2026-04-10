//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct TherapySettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel
    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView? = AnyView(
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Carb Sensitivity Factor (CSF) represents how much your blood glucose rises per gram of carbohydrate consumed. It describes your digestive process - how effectively carbs are absorbed into your blood."
            )
            Text(
                "The CSF profile is used to optionally re-calculate your Carb Ratio (CR) from your Insulin Sensitivity Factor (ISF) using the formula: CR = ISF / CSF"
            )
            Text(
                "This approach is important because creating separate CR and ISF profiles implicitly defines an unreviewed CSF profile (calculated as CSF = ISF / CR) that may be incorrect. By explicitly defining your CSF profile (which should actually be just a single entry as most of us do not know much about how CSF changes), you ensure that CR automatically adjusts correctly throughout the day as your ISF changes, maintaining physiologically accurate insulin dosing for carbohydrates."
            )
            Text(
                "CR combines two independent physiological processes: CSF (carb absorption into blood) and ISF (insulin moving glucose out of blood). These processes operate separately, so when ISF changes due to exercise or stress, CSF remains stable, and CR adjusts accordingly through the formula CR = ISF / CSF."
            )
        }
    )
    @State var hintLabel: String? = String(localized: "Carb Sensitivity Profile", comment: "Carb Sensitivity Profile")

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Basic Settings"),
                content: {
                    Text("Units and Limits").navigationLink(to: .unitsAndLimits, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section(
                header: Text("Basic Insulin Rates & Targets"),
                content: {
                    Text("Glucose Targets").navigationLink(to: .targetsEditor, from: self)
                    Text("Basal Rates").navigationLink(to: .basalProfileEditor, from: self)
                    Text("Carb Ratios").navigationLink(to: .crEditor, from: self)
                    Text("Insulin Sensitivities").navigationLink(to: .isfEditor, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section {
                VStack {
                    Text("Carb Sensitivities").navigationLink(to: .csfEditor, from: self)
                    HStack(alignment: .top) {
                        Text("Optional profile used to derive Carb Ratios from ISF.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                shouldDisplayHint.toggle()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        ).buttonStyle(BorderlessButtonStyle())
                    }.padding(.top)
                }
            } header: {
                Text("Carb Sensitivity Profile")
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Therapy Settings")
        .navigationBarTitleDisplayMode(.automatic)
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
    }
}
