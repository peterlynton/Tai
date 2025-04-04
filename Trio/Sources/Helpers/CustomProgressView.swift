import SwiftUI

struct CustomProgressView: View {
    @State var animate = false

    let text: String

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Text(text)
                .font(.system(.body, design: .rounded))
                .bold()
                .offset(x: 0, y: -25)

            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(.systemGray5), lineWidth: 3)
                .frame(width: 250, height: 3)

            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    TaiStyle.linearGradient(
                        startPoint: .trailing, // Orange on right
                        endPoint: .leading // Cyan on left
                    ),
                    lineWidth: 3
                )
                .frame(width: 250, height: 3)
                .mask(
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: 80, height: 3)
                        .offset(x: self.animate ? 180 : -180, y: 0)
                        .animation(
                            Animation.linear(duration: 1)
                                .repeatForever(autoreverses: false), value: UUID()
                        )
                )
        }
        .onAppear {
            self.animate.toggle()
        }
    }
}

enum ProgressText: String {
    case updatingIOB = "Updating IOB ..."
    case updatingCOB = "Updating COB ..."
    case updatingHistory = "Updating History ..."
    case updatingTreatments = "Updating Treatments ..."
    case updatingIOBandCOB = "Updating IOB and COB ..."
}
