import SwiftUI

enum CSFEditor {
    enum Config {}

    final class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var rateIndex: Int
        var timeIndex: Int

        init(rateIndex: Int, timeIndex: Int) {
            self.rateIndex = rateIndex
            self.timeIndex = timeIndex
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.rateIndex == rhs.rateIndex && lhs.timeIndex == rhs.timeIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(rateIndex)
            hasher.combine(timeIndex)
        }
    }
}

protocol CSFEditorProvider: Provider {
    var profile: CarbSensitivities { get }
    func saveProfile(_ profile: CarbSensitivities)
}
