import SwiftUI
import Swinject

extension AutoISFSettings {
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
                            booleanValue: $state.autoisf,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = "autoISF 3.01"
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: "Activate autoISF",
                            miniHint: String(
                                localized: "autoISF 3.01 calculates insulin sensitivity (ISF) each loop cycle based on glucose behaviour within set limits."
                            ),
                            verboseHint:
                            VStack(alignment: .leading) {
                                Text(
                                    "autoISF allows to adapt the insulin sensitivity factor (ISF) in the following scenarios of glucose behaviour:"
                                )
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                                BulletList(
                                    listItems:
                                    [
                                        "Accelaration: acce_ISF is a factor derived from acceleration of glucose levels.",
                                        "Glucose Level: bg_ISF is a factor derived from the deviation of glucose from target.",
                                        "Postprandial situation: pp_ISF is a factor derived from glucose rise delta.",
                                        "Long lasting Highs: dura_ISF is a factor derived from glucose being stuck at high levels."
                                    ],
                                    listItemSpacing: 10
                                )
                                Image("autoISF_factors")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 300)
                                    .padding(2)
                                Text(
                                    "When autoISF is turned on the autoISF Ratio (aiSR) will be displayed on Homeview, showing the final ISF / Sensitivity adaption, instead of the regular Autosens Sensitivity Ratio (AS)"
                                )
                                Divider()
                                Text("When all 4 effects are configured, how to deduce an end result?").bold()
                                Text("""
                                The normal case is to pick the strongest factor as the one and only factor to be applied. Here autosense is also part of the game. But how about the exceptions, i.e., when different factors pull in different directions? In order of precedence they are:
                                """)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)

                                BulletList(
                                    listItems:
                                    [
                                        "bg_ISF < 1, i.e., glucose is below target.",
                                        "If acce_ISF > 1, i.e., glucose is accelerating although below target, both factors get multiplied as a trade-off between them. Then the weaker of bg_ISF and Autosens is used as the final sensitivity ISF.",
                                        "acce_ISF < 1, i.e., glucose is decelerating while other effects want to strengthen ISF. In this case, the strongest of the remaining, positive factors will be multiplied by acce_ISF to reach a compromise. This overall factor will be compared with autosense and the stronger of the two will be used in calculating the final sensitivity ISF.",
                                        "In all of the above, the autoISF limits for maximum and minimum changes will also be applied."
                                    ],
                                    listItemSpacing: 10
                                )
                                Image("autoISF_flow")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 300)
                                    .padding(2)

                                Text("""
                                With v3.01 the following 5 settings were withdrawn because over time it proved they were not really necessary. One direct impact is a flatter menu structure for the remaining settings:
                                """)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)

                                BulletList(
                                    listItems: [
                                        "pp_ISF_hours no longer required because …",
                                        "enable_pp_ISF_always is now always true which means …",
                                        "delta_ISFrange_weight is no longer used in favour of pp_ISF",
                                        "enable_dura_ISF_with_COB is now always true",
                                        "enable_SMB_EvenOn_OddOff was discontinued and unified with enableSMB_EvenOn_OddOff_always"
                                    ],
                                    listItemSpacing: 10
                                )
                            }
                        )
                    }
                )

                if state.autoisf {
                    Section {
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableAutosens,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Enable Autosens", comment: "Enable Autosens")
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: String(localized: "Enable Autosens", comment: "Enable Autosens"),
                            miniHint: String(
                                localized:
                                "Switch Autosens on/off",
                                comment: "Autosens miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Default:  OFF ").bold()
                                Text(
                                    "autosens is not needed for autoISF as it adapts on a longer time frame than autoISF, so any autosens adjustment is lagging behind what is done by autoISF. It can be kept to ON, and in some border cases the autosens ISF will be used. Check on Discord."
                                )
                                Text(
                                    "When autoISF is turned off Autosens will always be activated and on HomwView, the Autosens Sensitivity Ratio (AS) will be shown instead of the autoISF Ratio (aiSR)"
                                )
                            }
                        )

                        // Odd  Targets disables SMB for autoISF
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableSMBEvenOnOddOffAlways,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(
                                        localized:
                                        "Odd Target disables SMB for autoISF",
                                        comment: "Odd Target disables SMB"
                                    )
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: String(
                                localized:
                                "Odd Target disables SMB for autoISF",
                                comment: "Odd Target disables SMB"
                            ),
                            miniHint: String(
                                localized:
                                "autoISF will enable SMBs for even and block them for odd Targets.",
                                comment: "Odd Target disables SMB miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Very neat feature that allows the use of profile and temporary targets to trigger SMB's being enabled or disabled. So a profile target at 3:00 am of \(state.units == .mgdL ? "121" : 121.formattedAsMmolL) \(state.units.rawValue) will prevent any SMB's in that time window. Schedule a TT of \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) at 3:20 am and from then on SMB's can be enacted."
                                )
                            }
                        )

                        // Exercise toggles all autoISF adjustments off
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.autoISFoffSport,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(
                                        localized:
                                        "Exercise toggles all autoISF adjustments off",
                                        comment: "autoISF Off for Sport"
                                    )
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: String(
                                localized:
                                "Exercise toggles all autoISF adjustments off",
                                comment: "autoISF Off for Sport"
                            ),
                            miniHint: String(
                                localized:
                                "Completely switches off autoISF during a high TT with adjusted sensitivity.",
                                comment: "Exercise toggles all autoISF adjustments off miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "If enabled this function will switch off autoISF adaptions completely if you are exercising. Exercising means you have a high TempTarget enabled and  HighTTraisesSens, so that this high TT will already increase your sensitivity (will be displayed in active TempTarget)."
                                )
                            }
                        )

                        // autoISF IOB Threshold Percent
                        SettingInputSection(
                            decimalValue: $state.iobThresholdPercent,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "autoISF IOB Threshold Percent", comment: "IOB Threshold")
                                }
                            ),
                            units: state.units,
                            type: .decimal("iobThresholdPercent"),
                            label: String(localized: "autoISF IOB Threshold Percent", comment: "IOB Threshold"),
                            miniHint: String(
                                localized:
                                "This is the share of maxIOB above which autoISF will disable SMB. 100% neutralizes it's effect.",
                                comment: "autoISF IOB Threshold miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Default: 100% ").bold()
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("""
                                        The variable IOB Threshold Percent holds a percentage of the maxIOB which is used as the threshold to disable SMB. If this is enabled by setting it lower than 100%, any sensitivity changes defined by the user are modulated internally into an effective IOB Threshold.

                                        The new capabilities are:
                                        """)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)

                                        BulletList(
                                            listItems: [
                                                //                                                "iiobThresholdPercent gets modulated while the pump profile is set to a percentage (profiles are not in Tai yet). The idea is that with changed sensitivity the threshold should change accordingly. So internally an effective iobTH is used. If for example the profile is raised to 120% because of an infection then the effective iobTH is 120% of iob_threshold_percent. This relieves the user from having to adapt the automation rules for those periods and having to remember setting them back once the profile is reset.",
                                                "IOB Threshold Percent gets modulated while sensitivity changes from TT - high TT raises Sens or low TT lowers Sens are active (Algorithm Settings > Target Behaviour)- in this respect high TT's lower effective max IOB and low TT raise it. These effects only activate if the IOB Threshold is set below 100%",
                                                "A very special modification happens during the initial rise after carbs intake. After the first few SMBs the IOB Threshold may eventually be surpassed. Often this initial overshoot was far too much due to limited capabilities using automations and led to hypo later. The code will limit this overshoot or tolerance to 130% of the effective IOB Threshold. During the next loop the IOB will most probably still be above that threshold and therefore SMBs stay disabled until iob drops below the effective threshold."
                                            ],
                                            listItemSpacing: 10
                                        )
                                    }
                                }
                            }
                        )

                        // autoISF Max
                        SettingInputSection(
                            decimalValue: $state.autoISFmax,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "autoISF Max", comment: "autoISF Max")
                                }
                            ),
                            units: state.units,
                            type: .decimal("autoISFmax"),
                            label: String(localized: "autoISF Max", comment: "autoISF Max"),
                            miniHint: String(
                                localized:
                                "Highest ISF factor allowed.",
                                comment: "autoISF Max miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: 2").bold()
                                Text(
                                    "Multiplier cap on how high the autoISF ratio can be and therefore how low it can adjust ISF."
                                )
                            }
                        )

                        // autoISF Min
                        SettingInputSection(
                            decimalValue: $state.autoISFmin,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "autoISF Min", comment: "autoISF Min")
                                }
                            ),
                            units: state.units,
                            type: .decimal("autoISFmin"),
                            label: String(localized: "autoISF Min", comment: "autoISF Min"),
                            miniHint: String(
                                localized:
                                "Lowest ISF factor allowed.",
                                comment: "autoISF Min miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: 0.7").bold()
                                Text(
                                    "This is a multiplier cap for autoISF to set a limit on how low the autoISF ratio can be, which in turn determines how high it can adjust ISF."
                                )
                            }
                        )
                    } header: { Text("General") }
                    Section {
                        // Enable BG Acceleration
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableBGacceleration,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Enable BG Acceleration", comment: "Enable BG Acceleration")
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: String(localized: "Enable BG Acceleration", comment: "Enable BG Acceleration"),
                            miniHint: String(
                                localized:
                                "Enables the BG acceleration adaptions, adjusting ISF for accelerating/decelerating blood glucose.",
                                comment: "Enable BG Acceleration miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                ScrollView {
                                    Text("""
                                    acce_ISF is calculated by
                                    acce_ISF = 1 + acce_weight * fit_share * cap_weight * acceleration
                                    where fit_share is a measure of fit quality, i.e., 0% if unacceptable up to 100% if perfect;
                                    cap_weight is 0.5 below target and 1.0 otherwise;
                                    acce_weight is bgAccel_ISF_weight for acceleration away from target, i.e., mostly positive
                                    or bgBrake_ISF_weight for acceleration towards target, i.e., mostly negative.

                                    Initially, it was assumed that the weights for accelerating and braking are of similar size.
                                    First experiences suggest that the weight while decelerating should be 30-40% lower than for acceleration to reduce glucose oscillations. Quite often the acce_ISF contribution plays the dominant role inside autoISF and is therefore very important and delicate.

                                    Weights for acce_ISF of 0 disable this contribution. Start small with weights like 0.02 and observe the results before increasing them. Keep in mind that negative acceleration will start to happen while glucose is apparently still rising but the slope reduces. Here, acce_ISF will be <1, i.e., sensitivity grows and less insulin than normal will be required even before the glucose peak is reached.
                                    """)
                                        .font(.body)
                                        .multilineTextAlignment(.leading)
                                }
                                Image("acce_flow")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 300)
                                    .padding(2)
                            }
                        )
                        if state.enableBGacceleration {
                            // ISF Weight While BG Accelerates
                            SettingInputSection(
                                decimalValue: $state.bgAccelISFweight,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(
                                            localized:
                                            "ISF Weight While BG accelerates",
                                            comment: "BG Acceleration ISF Weight"
                                        )
                                    }
                                ),
                                units: state.units,
                                type: .decimal("bgAccelISFweight"),
                                label: String(
                                    localized:
                                    "ISF Weight While BG Accelerates",
                                    comment: "BG Acceleration ISF Weight"
                                ),
                                miniHint: String(
                                    localized:
                                    "Strengthens ISF decrease while glucose accelerates.",
                                    comment: "ISF Weight While BG Accelerates miniHint"
                                ),
                                verboseHint: VStack(alignment: .leading, spacing: 10) {
                                    Text("Typical:  0.1 ").bold()
                                    Text(
                                        "Strength of acce_ISF contribution with positive acceleration. Start with 0.02 as initial value."
                                    )
                                }
                            )
                            SettingInputSection(
                                decimalValue: $state.bgBrakeISFweight,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(
                                            localized:
                                            "ISF Weight While BG decelarates",
                                            comment: "BG Brake ISF Weight"
                                        )
                                    }
                                ),
                                units: state.units,
                                type: .decimal("bgAccelISFweight"),
                                label: String(
                                    localized:
                                    "ISF Weight While BG Decelerates.",
                                    comment: "BG Brake ISF Weight"
                                ),
                                miniHint: String(
                                    localized:
                                    "Strengthens ISF increase while glucose decelarates.",
                                    comment: "ISF Weight While BG Accelerates miniHint"
                                ),
                                verboseHint: VStack(alignment: .leading, spacing: 10) {
                                    Text("Typical:  0.07 ").bold()
                                    Text("Strength of acce_ISF contribution with negative acceleration.")
                                }
                            )
                        }
                    } header: { Text("Acce-ISF") }
                    Section {
                        // ISF Weight for Higher BGs
                        SettingInputSection(
                            decimalValue: $state.higherISFrangeWeight,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "ISF Weight for Higher BGs", comment: "ISF High BG Weight")
                                }
                            ),
                            units: state.units,
                            type: .decimal("higherISFrangeWeight"),
                            label: String(localized: "ISF Weight for Higher BGs", comment: "ISF High BG Weight"),
                            miniHint: String(
                                localized:
                                "This is the weight applied to the polygon which adapts ISF if glucose is above target.",
                                comment: "ISF Weight for Higher BGs miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: 0.4").bold()
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("""
                                        Used above target, strengthens ISF the more the higher this weight is. 0 disables this contribution, i.e., ISF is constant in the whole range above target.

                                        Start with a weight of 0.2 and observe the reactions.

                                        There are indicators that higher glucose needs stronger ISF. This was evident from all the successful AAPS users defining automation rules which strengthen the profile at higher glucose levels. The drawback is that there are sudden jumps in ISF at switch points and no further or minor adaptations in between.

                                        In autoISF a polygon is provided that defines a relationship between glucose and ISF and interpolates in between. This is currently hard coded but the user can apply weights to easily strengthen or weaken it in order to fit personal needs. In principle the polygon itself can be edited and the apk rebuilt if a different shape is required. Developing a GUI for that purpose was considered very tedious especially before knowing whether the results warrant the effort. With this approach you could even approximate the formula well enough that is used in DynamicISF for the ISF dependency on glucose.

                                        There is a special case possible, namely below target i.e. when bg_ISF < 1. ISF will be weakened and there is no point in checking the remaining effects. Only with positive acceleration the weakening will be less pronounced as that is a sign of rising glucose to come soon.
                                        """)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Image("bgISF_flow") // Replace "example" with your actual PNG asset name
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 300) // Adjust size as needed
                                    .padding(2)
                            }
                        )
                        // ISF Weight for Lower BGs
                        SettingInputSection(
                            decimalValue: $state.lowerISFrangeWeight,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "ISF Weight for Lower BGs", comment: "ISF Low BG Weight")
                                }
                            ),
                            units: state.units,
                            type: .decimal("lowerISFrangeWeight"),
                            label: String(localized: "ISF Weight for Lower BGs", comment: "ISF Low BG Weight"),
                            miniHint: String(
                                localized:
                                "This is the weight applied to the polygon which adapts ISF if glucose is below target.",
                                comment: "ISF Weight for Lower BGs miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: 0.6").bold()
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("""
                                        Used below target, weakens ISF the more the higher this weight is. 0 disables this contribution, i.e., ISF is constant in the whole range below target. This weight is less critical as the loop is probably running at Temp basal Rate = 0 anyway and you can start around 0.2.
                                        """)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        )
                    } header: { Text("BG-ISF") }
                    Section {
                        // ISF weight for postprandial BG rise
                        SettingInputSection(
                            decimalValue: $state.postMealISFweight,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(
                                        localized:
                                        "ISF Weight for Postprandial BG Rise",
                                        comment: "Postprandial ISF weight"
                                    )
                                }
                            ),
                            units: state.units,
                            type: .decimal("postMealISFweight"),
                            label: String(localized: "ISF Weight for Postprandial BG Rise", comment: "Postprandial ISF weight"),
                            miniHint: String(
                                localized:
                                "This is the weight applied to the linear slope while glucose rises and adapts ISF. With 0 this contribution is effectively disabled. Start with 0.01 - it hardly goes beyond 0.05!",
                                comment: "ISF weight for postprandial BG rise miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: 0.02").bold()
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("""
                                        autoISF can adapt ISF based on glucose delta. It was introduced to help users with gastroparesis. It is also useful for users in pure UAM mode because in their case no meal start can be detected. Given a positive short_avgdelta and glucose being above target+10, the result is:

                                        pp_ISF = 1 + delta * pp_ISF_weight.

                                        As a starting value for pp_ISF_weight, use 0.005. Observe the reactions and check the Enacted Popup before you increase it with care. A weight of 0 disables this contribution.
                                        """)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        )
                    } header: { Text("pp-ISF") }
                    Section {
                        // DuraISF Weight
                        SettingInputSection(
                            decimalValue: $state.autoISFhourlyChange,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "DuraISF Weight", comment: "DuraISF Weight")
                                }
                            ),
                            units: state.units,
                            type: .decimal("autoISFhourlyChange"),
                            label: String(localized: "DuraISF Weight", comment: "DuraISF Weight"),
                            miniHint: String(
                                localized:
                                "Rate at which ISF is reduced per hour assuming BG level remains at double target for that time.",
                                comment: "DuraISF Weight miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: 0.6").bold()
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("""
                                        This is the original effect of autoISF in action since August 2020. Because autoISF is now a toolbox of several effects, this original effect was renamed dura_ISF. It addresses situations when:
                                        """)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)

                                        BulletList(
                                            listItems: [
                                                "Glucose is varying within a +/- 5% interval only.",
                                                "The average glucose (dura_ISF_average) within that interval is above target.",
                                                "This situation lasted at least for the last 10 minutes (dura_ISF_minutes)."
                                            ],
                                            listItemSpacing: 10
                                        )

                                        Text("""
                                        This is a classical insulin resistance and is typically caused by free fatty acids which grab available insulin before glucose can. Quite often, users get impatient in such a situation and administer one or even more rage boluses. Again and again, that leads to hypos later which the dura_ISF approach avoids if carefully tuned.

                                        The strengthening of ISF is stronger the longer the situation lasts and the higher the average glucose is above target:

                                        dura_ISF = 1 + (avg05 - target_bg) / target_bg * dura05 * dura_ISF_weight

                                        where:
                                        avg05 = dura_ISF_average
                                        dura05 = dura_ISF_minutes

                                        The user can apply his personal weighting by using dura_ISF_weight. Start cautiously with a value of 0.2 and be very careful when you approach 1.5 or even higher. By using 0 this effect is disabled.
                                        """)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                        Image("duraISF_flow") // Replace "example" with your actual PNG asset name
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 300) // Adjust size as needed
                                            .padding(2)
                                    }
                                }
                            }
                        )
                    } header: { Text("Dura-ISF") }
                    Section {
                        // SMB DeliveryRatio
                        SettingInputSection(
                            decimalValue: $state.smbDeliveryRatio,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "SMB DeliveryRatio", comment: "SMB DeliveryRatio")
                                }
                            ),
                            units: state.units,
                            type: .decimal("smbDeliveryRatio"),
                            label: String(localized: "SMB DeliveryRatio (fixed)", comment: "SMB DeliveryRatio"),
                            miniHint: String(
                                localized:
                                "This is another key OpenAPS safety cap, and specifies what share of the total insulin required can be delivered as SMB.",
                                comment: "SMB DeliveryRatio miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Default: 0.5").bold()
                                Text(
                                    "In oref smb_delivery_ratio is normally hard coded as 0.5 of the insulin requested. This is a safety feature for master/follower setups in case both phones trigger an SMB in the same situation. If this does not apply in your case you may increase this setting to a value above 0.5 and up to even 1.0 if you are very courageous."
                                )
                            }
                        )
                        // SMB DeliveryRatio BG Range
                        SettingInputSection(
                            decimalValue: $state.smbDeliveryRatioBGrange,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(
                                        localized:
                                        "SMB DeliveryRatio BG Range",
                                        comment: "SMB DeliveryRatio BG Range"
                                    )
                                }
                            ),
                            units: state.units,
                            type: .decimal("smbDeliveryRatioBGrange"),
                            label: String(localized: "SMB DeliveryRatio BG Range", comment: "SMB DeliveryRatio BG Range"),
                            miniHint: String(
                                localized:
                                "Sensible is between \(state.units == .mgdL ? "40" : 40.formattedAsMmolL) \(state.units.rawValue) and \(state.units == .mgdL ? "120" : 120.formattedAsMmolL) \(state.units.rawValue). The linearly increasing SMB delivery ratio is mapped to the glucose range [target_bg, target_bg+bg_range]. If set to 0 the SMB DeliveryRatio (fixed) is used instead.",
                                comment: "SMB DeliveryRatio BG Range miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Typical: \(state.units == .mgdL ? "90" : 90.formattedAsMmolL) \(state.units.rawValue)")
                                    .bold()
                                Text(
                                    "Alternatively to a higher but fixed ratio you can use a linearly rising ratio, starting cautiously with smb_delivery_ratio_min at target_bg and rising to a more ambitious smb_delivery_ratio_max at target_bg+smb_delivery_ratio_bg_range."
                                )
                            }
                        )
                        if state.smbDeliveryRatioBGrange != 0 {
                            // SMB DeliveryRatio BG Minimum
                            SettingInputSection(
                                decimalValue: $state.smbDeliveryRatioMin,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(
                                            localized:
                                            "SMB DeliveryRatio BG Minimum",
                                            comment: "SMB DeliveryRatio Minimum"
                                        )
                                    }
                                ),
                                units: state.units,
                                type: .decimal("smbDeliveryRatioMin"),
                                label: String(localized: "SMB DeliveryRatio BG Minimum", comment: "SMB DeliveryRatio Minimum"),
                                miniHint: String(
                                    localized:
                                    "Default value: 0.5 This is the lower end of a linearly increasing SMB Delivery Ratio rather than the fix value above in SMB DeliveryRatio.",
                                    comment: "SMB DeliveryRatio Minimum miniHint"
                                ),
                                verboseHint: VStack(alignment: .leading, spacing: 10) {
                                    Text("Default:  ... ").bold()
                                    Text("Lorem ipsum ...")
                                }
                            )
                            // SMB DeliveryRatio BG Maximum
                            SettingInputSection(
                                decimalValue: $state.smbDeliveryRatioMax,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(
                                            localized:
                                            "SMB DeliveryRatio BG Maximum",
                                            comment: "SMB DeliveryRatio Maximum"
                                        )
                                    }
                                ),
                                units: state.units,
                                type: .decimal("smbDeliveryRatioMax"),
                                label: String(localized: "SMB DeliveryRatio BG Maximum", comment: "SMB DeliveryRatio Maximum"),
                                miniHint: String(
                                    localized:
                                    "Default value: 0.5 This is the higher end of a linearly increasing SMB Delivery Ratio rather than the fix value above in SMB DeliveryRatio.",
                                    comment: "SMB DeliveryRatio Maximum miniHint"
                                ),
                                verboseHint: VStack(alignment: .leading, spacing: 10) {
                                    Text("Default:  ... ").bold()
                                    Text("Lorem ipsum ...")
                                }
                            )
                        }
                        // SMB Max RangeExtension
                        SettingInputSection(
                            decimalValue: $state.smbMaxRangeExtension,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "SMB Max RangeExtension", comment: "SMB Max RangeExtension")
                                }
                            ),
                            units: state.units,
                            type: .decimal("smbMaxRangeExtension"),
                            label: String(localized: "SMB Max RangeExtension", comment: "SMB Max RangeExtension"),
                            miniHint: String(
                                localized: "This specifies by what factor you can exceed the limit of 180 maxSMB/maxUAM minutes.",
                                comment: "SMB Max RangeExtension miniHint"
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Default: 1").bold()
                                Text(
                                    "A factor that multiplies the current maxSMBBasalMinutes and maxUAM/SMBBasalMinutes beyond the 180 minute limit set in Trio."
                                )
                            }
                        )
                    } header: { Text("SMB Delivery Ratios") }
                } else {
                    VStack(alignment: .leading) {
                        Text(
                            "autoISF allows to adapt the insulin sensitivity factor (ISF) in the following scenarios of glucose behaviour:"
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        BulletList(
                            listItems:
                            [
                                "accelerating/decelerating blood glucose",
                                "blood glucose levels according to a predefined polygon, like a Sigmoid",
                                "postprandial (after meal) glucose rise",
                                "blood glucose plateaus above target"
                            ],
                            listItemSpacing: 10
                        )
                        Image("autoISF_factors")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 300)
                            .padding(5)
                        Text("It can also adapt SMB delivery settings.")
                        Text("Read up on it at:").padding(.top)
                        SwiftUI.Link(
                            "autoISF 3.01 Documentation",
                            destination: URL(
                                string: "https://github.com/ga-zelle/autoISF"
                            )!
                        )
                        .accentColor(.blue)
                        Text("Tai as the Trio version of autoISF does not include ActivityTracking.")
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
            .navigationTitle("autoISF Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
