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
            do {
                // Create a directory for our zip file in Documents
                let exportsDirectoryURL = try Disk.AppDirectoryURL.logExports()

                // Create directory if it doesn't exist
                if !fileManager.fileExists(atPath: exportsDirectoryURL.path) {
                    try fileManager.createDirectory(at: exportsDirectoryURL, withIntermediateDirectories: true)
                }

                // Create a unique filename with timestamp using static formatter
                let timestamp = Formatter.iso8601.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let zipFileURL = exportsDirectoryURL.appendingPathComponent("Trio-Logs-\(timestamp).zip")

                // Create a temporary staging directory
                let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                let stagingDirURL = temporaryDirectoryURL.appendingPathComponent(
                    "staging-\(UUID().uuidString)",
                    isDirectory: true
                )

                // Wrap the entire staging flow with proper cleanup
                do {
                    try fileManager.createDirectory(at: stagingDirURL, withIntermediateDirectories: true)

                    // Collect all the log files
                    var stagingFileURLs: [URL] = []
                    var sourceFileURLs: [URL] = [] // Track original source files for fallback
                    let logNames = SimpleLogReporter.getAllLogNames()

                    // Copy both standard and watch log files to staging
                    try copyLogs(
                        logNames: logNames,
                        to: stagingDirURL,
                        stagingFileURLs: &stagingFileURLs,
                        sourceFileURLs: &sourceFileURLs,
                        isWatchLogs: false
                    )

                    try copyLogs(
                        logNames: logNames,
                        to: stagingDirURL,
                        stagingFileURLs: &stagingFileURLs,
                        sourceFileURLs: &sourceFileURLs,
                        isWatchLogs: true
                    )

                    // If no files to share, return empty array
                    if stagingFileURLs.isEmpty {
                        debug(.service, "No log files found to share")
                        // Clean up empty staging directory
                        try? fileManager.removeItem(at: stagingDirURL)
                        return []
                    }

                    // Create the zip file using the Archive Utility
                    if createZipArchive(from: stagingDirURL, to: zipFileURL) {
                        // Clean up staging directory after successful zip creation
                        try? fileManager.removeItem(at: stagingDirURL)
                        // Return the zip file URL for sharing
                        return [zipFileURL]
                    } else {
                        debug(.service, "Failed to create zip archive, returning all staging files")
                        // Return all staging files (don't clean up staging yet)
                        // Note: Staging cleanup will happen when these files are no longer needed
                        return stagingFileURLs
                    }

                } catch {
                    // Clean up staging directory on any error
                    try? fileManager.removeItem(at: stagingDirURL)
                    debug(.service, "Error in staging/zip process: \(error.localizedDescription)")
                    // Re-throw to be caught by outer catch block for fallback
                    throw error
                }

            } catch {
                debug(.service, "Error preparing logs for sharing: \(error.localizedDescription)")

                // Show alert to user about the error
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "Log Export Error",
                        message: "Failed to prepare logs for sharing. Using current log file as fallback.\n\nError: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))

                    // Present on the topmost view controller
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                       let rootViewController = window.rootViewController
                    {
                        var topController = rootViewController
                        while let presentedViewController = topController.presentedViewController {
                            topController = presentedViewController
                        }
                        topController.present(alert, animated: true)
                    }
                }

                // Fallback to just the current log as a last resort
                let currentLogFileURL = SimpleLogReporter.logFileURL(name: SimpleLogReporter.currentLogName())
                if fileManager.fileExists(atPath: currentLogFileURL.path) {
                    return [currentLogFileURL]
                }
                // If all else fails, return empty array
                return []
            } }

        // Helper function to copy log files to staging directory
        private func copyLogs(
            logNames: [String],
            to stagingDirURL: URL,
            stagingFileURLs: inout [URL],
            sourceFileURLs: inout [URL],
            isWatchLogs: Bool
        ) throws {
            for logName in logNames {
                let sourceURL: URL
                let filename: String

                if isWatchLogs {
                    sourceURL = SimpleLogReporter.watchLogFileURL(name: logName)
                    filename = Disk.AppFilenames.watchLogFile(name: logName)
                } else {
                    sourceURL = SimpleLogReporter.logFileURL(name: logName)
                    filename = Disk.AppFilenames.logFile(name: logName)
                }

                if fileManager.fileExists(atPath: sourceURL.path) {
                    let destURL = stagingDirURL.appendingPathComponent(filename)
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                    stagingFileURLs.append(destURL)
                    sourceFileURLs.append(sourceURL) // Track original source for fallback
                }
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
