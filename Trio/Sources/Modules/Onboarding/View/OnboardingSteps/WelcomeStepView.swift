import SwiftUI

/// Welcome step view shown at the beginning of onboarding.
struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            PulsingLogoAnimation()

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 20) {
                Text("Hi there!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(
                    "Welcome to Tai - an automated insulin delivery system for iOS based on Trio using the OpenAPS algorithm with autoISF and other adaptations."
                )
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

                Text(
                    "Trio is designed to help manage your diabetes efficiently. To get the most out of the app, we'll guide you through setting up some essential Trio parameters. Tai specific settings need to be done manually after Trio onboarding."
                )
                .multilineTextAlignment(.leading)
                .foregroundColor(.secondary)

                Text(
                    "Tai specific settings like autoISF or Ketoacidosis Protection need to be done manually after Trio onboarding."
                )
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)

                Text("Let's go through a few quick steps to ensure Trio works optimally for you.")
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .bold()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
