import Combine
import Foundation
import LoopKitUI

extension AlgorithmAdvancedSettings {
    final class Provider: BaseProvider, AlgorithmAdvancedSettingsProvider {
        private let processQueue = DispatchQueue(label: "AlgorithmAdvancedSettingsProvider.processQueue")
        @Injected() private var broadcaster: Broadcaster!

        func savePreferences(_ preferences: Preferences) {
            storage.save(preferences, as: OpenAPS.Settings.preferences)
            processQueue.async {
                self.broadcaster.notify(PreferencesObserver.self, on: self.processQueue) {
                    $0.preferencesDidChange(preferences)
                }
            }
        }
    }
}
