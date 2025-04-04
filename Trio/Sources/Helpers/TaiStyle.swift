import SwiftUI

struct TaiStyle {
    // Colors
    static var orangeColor: Color { Color.orange }
    static var tealColor: Color { Color.teal }
    static var cyanColor: Color { Color.cyan }

    // Angular gradient for the ring
    static func ringGradient(startAngle: Angle = .degrees(60)) -> AngularGradient { AngularGradient(
        stops: [
            .init(color: Color.cyan, location: 0.0), // Blue at 0%
            .init(color: Color.teal, location: 0.2), // Teal at 20%
            .init(color: Color.orange, location: 0.5), // Orange at 50%
            .init(color: Color.teal, location: 0.8), // Teal at 80%
            .init(color: Color.cyan, location: 1.0) // Blue at 100%
        ],
        center: .center,
        startAngle: startAngle,
        endAngle: .degrees(startAngle.degrees + 360)
    )
    }

    // Linear gradient with configurable start and end points
    static func linearGradient(
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: orangeColor, location: 0.0),
                .init(color: orangeColor, location: 0.1),
                .init(color: tealColor, location: 0.75),
                .init(color: cyanColor, location: 1.0)
            ]),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    // Optional: Custom gradient with fully configurable parameters
    static func customLinearGradient(
        orangeLocation: Double = 0.0,
        orangeEndLocation: Double = 0.1,
        tealLocation: Double = 0.75,
        cyanLocation: Double = 1.0,
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: orangeColor, location: orangeLocation),
                .init(color: orangeColor, location: orangeEndLocation),
                .init(color: tealColor, location: tealLocation),
                .init(color: cyanColor, location: cyanLocation)
            ]),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
