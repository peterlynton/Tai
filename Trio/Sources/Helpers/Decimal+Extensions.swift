import CoreGraphics
import Foundation

extension Decimal {
    /// Rounds the Decimal to the nearest BuolisIncrment ncrement, ensuring it does not exceed maxBolus.
    func roundedToBolusIncrement(
        increment: Decimal,
        maxBolus: Decimal? = nil,
        roundingMode: NSDecimalNumber.RoundingMode = .down
    ) -> Decimal {
        guard increment > 0 else { return self }

        let doubleValue = (self as NSDecimalNumber).doubleValue
        let doubleIncrement = (increment as NSDecimalNumber).doubleValue

        let adjustedDouble: Double
        if roundingMode == .down {
            adjustedDouble = floor(doubleValue / doubleIncrement) * doubleIncrement // Always round down
        } else {
            adjustedDouble = (doubleValue / doubleIncrement).rounded() * doubleIncrement // Round to nearest
        }

        var adjustedDecimal = Decimal(adjustedDouble)
        var result = Decimal()
        NSDecimalRound(&result, &adjustedDecimal, 3, roundingMode)

        if let maxBolus = maxBolus {
            return min(result, maxBolus)
        }

        return result
    }
}

// MARK: - Double Initializer for Decimal

extension Double {
    /// Initializes a Double from a Decimal.
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }
}

// MARK: - Int Initializer for Decimal

extension Int {
    /// Initializes an Int from a Decimal.
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

// MARK: - CGFloat Initializer for Decimal

extension CGFloat {
    /// Initializes a CGFloat from a Decimal.
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

// MARK: - Time Interval Conversion for Int16

extension Int16 {
    /// Converts Int16 minutes to a TimeInterval in seconds.
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}
