import LoopKit
import LoopKitUI
import SwiftUI
import TidepoolServiceKit

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() var pluginManager: PluginManager!
        @Injected() var fetchCgmManager: FetchGlucoseManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var closedLoop = false
        @Published var debugOptions = false
        @Published var serviceUIType: ServiceUI.Type?
        @Published var setupTidepool = false

        private(set) var buildNumber = ""
        private(set) var versionNumber = ""
        private(set) var branch = ""
        private(set) var copyrightNotice = ""

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.closedLoop, on: $closedLoop) { closedLoop = $0 }

            broadcaster.register(SettingsObserver.self, observer: self)

            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

            versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            branch = BuildDetails.shared.branchAndSha

            copyrightNotice = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

            serviceUIType = TidepoolService.self as? ServiceUI.Type
        }

        func logItems() -> [URL] {
            // Create a directory for our zip file in Documents instead of tmp
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let exportsDirectoryURL = documentsDirectory.appendingPathComponent("LogExports", isDirectory: true)

            do {
                // Create directory if it doesn't exist
                if !fileManager.fileExists(atPath: exportsDirectoryURL.path) {
                    try fileManager.createDirectory(at: exportsDirectoryURL, withIntermediateDirectories: true)
                }

                // Create a unique filename with timestamp
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let timestamp = dateFormatter.string(from: Date())
                let zipFileURL = exportsDirectoryURL.appendingPathComponent("Trio-Logs-\(timestamp).zip")

                // Create a temporary staging directory
                let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                let stagingDirURL = temporaryDirectoryURL.appendingPathComponent(
                    "staging-\(UUID().uuidString)",
                    isDirectory: true
                )
                try fileManager.createDirectory(at: stagingDirURL, withIntermediateDirectories: true)

                // Collect all the log files
                var stagingFileURLs: [URL] = []

                // Use the retention period for log names
                let logNames = SimpleLogReporter.getAllLogNames()

                // Copy all standard log files to staging - keeping original filenames
                for logName in logNames {
                    let logPath = SimpleLogReporter.logFile(name: logName)
                    if fileManager.fileExists(atPath: logPath) {
                        // Use the original filename
                        let destURL = stagingDirURL.appendingPathComponent("\(logName).log")
                        try fileManager.copyItem(at: URL(fileURLWithPath: logPath), to: destURL)
                        stagingFileURLs.append(destURL)
                    }
                }

                // Copy all watch log files to staging - keeping original watch_ prefix
                for logName in logNames {
                    let watchLogPath = SimpleLogReporter.watchLogFile(name: logName)
                    if fileManager.fileExists(atPath: watchLogPath) {
                        // Use the original filename with watch_ prefix
                        let destURL = stagingDirURL.appendingPathComponent("watch_\(logName).log")
                        try fileManager.copyItem(at: URL(fileURLWithPath: watchLogPath), to: destURL)
                        stagingFileURLs.append(destURL)
                    }
                }

                // If no files to share, return empty array
                if stagingFileURLs.isEmpty {
                    debug(.service, "No log files found to share")
                    try? fileManager.removeItem(at: stagingDirURL)
                    return []
                }

                // Create the zip file using the Archive Utility
                if createZipArchive(from: stagingDirURL, to: zipFileURL) {
                    // Clean up staging directory
                    try? fileManager.removeItem(at: stagingDirURL)

                    // Return the zip file URL for sharing
                    return [zipFileURL]
                } else {
                    debug(.service, "Failed to create zip archive, falling back to sharing a single file")

                    // Fall back to sharing just the main log file if zipping fails
                    if !stagingFileURLs.isEmpty {
                        return [stagingFileURLs[0]]
                    } else {
                        return []
                    }
                }

            } catch {
                debug(.service, "Error preparing logs for sharing: \(error.localizedDescription)")

                // Fallback to just the current log as a last resort
                let currentLogPath = SimpleLogReporter.logFile(name: SimpleLogReporter.currentLogName())
                if fileManager.fileExists(atPath: currentLogPath) {
                    return [URL(fileURLWithPath: currentLogPath)]
                }

                // If all else fails, return empty array
                return []
            }
        }

        // Helper function to create a zip archive using NSFileCoordinator
        private func createZipArchive(from sourceURL: URL, to destinationURL: URL) -> Bool {
            let coordinator = NSFileCoordinator()
            var success = false
            var coordinatorError: NSError?

            coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordinatorError) { zippedURL in
                do {
                    // NSFileCoordinator provides the zipped URL for us
                    try fileManager.copyItem(at: zippedURL, to: destinationURL)
                    success = true
                } catch {
                    debug(.service, "Error creating zip archive: \(error.localizedDescription)")
                }
            }

            if coordinatorError != nil {
                debug(.service, "NSFileCoordinator error: \(String(describing: coordinatorError))")
            }

            return success && fileManager.fileExists(atPath: destinationURL.path)
        }

        // Commenting this out for now, as not needed and possibly dangerous for users to be able to nuke their pump pairing informations via the debug menu
        // Leaving it in here, as it may be a handy functionality for further testing or developers.
        // See https://github.com/nightscout/Trio/pull/277 for more information
//
//        func resetLoopDocuments() {
//            guard let localDocuments = try? FileManager.default.url(
//                for: .documentDirectory,
//                in: .userDomainMask,
//                appropriateFor: nil,
//                create: true
//            ) else {
//                preconditionFailure("Could not get a documents directory URL.")
//            }
//            let storageURL = localDocuments.appendingPathComponent("PumpManagerState" + ".plist")
//            try? FileManager.default.removeItem(at: storageURL)
//        }
        func hasCgmAndPump() -> Bool {
            let hasCgm = fetchCgmManager.cgmGlucoseSourceType != .none
            let hasPump = provider.deviceManager.pumpManager != nil
            return hasCgm && hasPump
        }
    }
}

extension Settings.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        closedLoop = settings.closedLoop
        debugOptions = settings.debugOptions
    }
}

extension Settings.StateModel: ServiceOnboardingDelegate {
    func serviceOnboarding(didCreateService service: Service) {
        debug(.nightscout, "Service with identifier \(service.pluginIdentifier) created")
        provider.tidepoolManager.addTidepoolService(service: service)
    }

    func serviceOnboarding(didOnboardService service: Service) {
        precondition(service.isOnboarded)
        debug(.nightscout, "Service with identifier \(service.pluginIdentifier) onboarded")
    }
}

extension Settings.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupTidepool = false
        provider.tidepoolManager.forceTidepoolDataUpload()
    }
}
