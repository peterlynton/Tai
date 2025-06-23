import Foundation
import SwiftDate

final class SimpleLogReporter: IssueReporter {
    private let fileManager = FileManager.default

    // Constants for maintenance
    private static let logRetentionDays = 4 // Keep logs for last 4 days
    private static let zipRetentionCount = 3 // Keep 3 most recent zip files

    // Property list key for persistent storage
    private static let lastCleanupDateKey = "SimpleLogReporter.lastDailyCleanupDate"

    // Track last cleanup time persistently across app launches
    private static var lastDailyCleanupDate: Date? {
        get {
            UserDefaults.standard.object(forKey: lastCleanupDateKey) as? Date
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date, forKey: lastCleanupDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastCleanupDateKey)
            }
        }
    }

    // MARK: - Date and Name Utilities

    static func currentLogName() -> String {
        let now = Date()
        return Formatter.logDateFormatter.string(from: now)
    }

    static func logNameForDate(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Formatter.logDateFormatter.string(from: date)
    }

    static func getAllLogNames() -> [String] {
        var names: [String] = []
        for i in 0 ..< logRetentionDays {
            names.append(logNameForDate(daysAgo: i))
        }
        return names
    }

    static func currentDate() -> Date {
        Date()
    }

    static func startOfCurrentDay() -> Date {
        let now = Date()
        return Calendar.current.startOfDay(for: now)
    }

    // MARK: - IssueReporter Implementation

    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        let now = SimpleLogReporter.currentDate()
        let startOfDay = SimpleLogReporter.startOfCurrentDay()
        let logName = SimpleLogReporter.currentLogName()

        // Ensure the logs directory exists
        let logsDir = SimpleLogReporter.logsDirectory
        if !fileManager.fileExists(atPath: logsDir.path) {
            do {
                try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            } catch {
                debug(.service, "Failed to create logs directory: \(error.localizedDescription)")
                return
            }
        }

        // Create today's log file if it doesn't exist
        let logFileURL = SimpleLogReporter.logFileURL(name: logName)
        if !fileManager.fileExists(atPath: logFileURL.path) {
            createFile(at: startOfDay)

            // Perform cleanup only when date changes
            SimpleLogReporter.performDailyCleanupIfNeeded()
        }

        // Append the log entry using ISO8601 formatter
        let logEntry = "\(Formatter.iso8601.string(from: now)) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n"
        guard let data = logEntry.data(using: .utf8) else {
            debug(.service, "Failed to encode log entry as UTF-8")
            return
        }

        do {
            try data.append(fileURL: logFileURL)
        } catch {
            debug(.service, "Failed to append log entry to \(logFileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func createFile(at date: Date) {
        let logName = SimpleLogReporter.currentLogName()
        let logFileURL = SimpleLogReporter.logFileURL(name: logName)
        let success = fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: [.creationDate: date])
        if !success {
            debug(.service, "Failed to create log file: \(logFileURL.lastPathComponent)")
        }
    }

    // MARK: - File Path Utilities

    static var documentsDirectory: URL {
        do {
            return try Disk.url(for: nil, in: .documents)
        } catch {
            debug(.service, "Failed to get documents directory: \(error.localizedDescription)")
            // Fallback to FileManager approach
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return paths[0]
        }
    }

    static var logsDirectory: URL {
        do {
            return try Disk.AppDirectoryURL.logs()
        } catch {
            debug(.service, "Failed to get logs directory via Disk: \(error.localizedDescription)")
            // Fallback to manual construction
            return documentsDirectory.appendingPathComponent("logs", isDirectory: true)
        }
    }

    static func logFileURL(name: String) -> URL {
        do {
            return try Disk.AppDirectoryURL.logFile(name: name)
        } catch {
            debug(.service, "Failed to get log file URL via Disk: \(error.localizedDescription)")
            // Fallback to manual construction
            return logsDirectory.appendingPathComponent("\(name).log")
        }
    }

    // Legacy string-based methods for backward compatibility
    static func logFile(name: String) -> String {
        logFileURL(name: name).path
    }

    static var logDir: String {
        logsDirectory.path
    }

    static func getDocumentsDirectory() -> URL {
        documentsDirectory
    }

    // MARK: - Watch Log Functions

    static func watchLogFileURL(name: String) -> URL {
        do {
            return try Disk.AppDirectoryURL.watchLogFile(name: name)
        } catch {
            debug(.service, "Failed to get watch log file URL via Disk: \(error.localizedDescription)")
            // Fallback to manual construction
            return logsDirectory.appendingPathComponent("watch_\(name).log")
        }
    }

    static func watchLogFile(name: String) -> String {
        watchLogFileURL(name: name).path
    }

    static func appendToWatchLog(_ logContent: String) {
        let startOfDay = startOfCurrentDay()
        let logName = currentLogName()

        let fileManager = FileManager.default
        let logsDir = logsDirectory
        let logFileURL = watchLogFileURL(name: logName)

        // Create logs directory if needed
        if !fileManager.fileExists(atPath: logsDir.path) {
            do {
                try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            } catch {
                debug(.service, "Failed to create logs directory for watch logs: \(error.localizedDescription)")
                return
            }
        }

        // Check if need to create a new log file for today
        let needNewFile: Bool
        if fileManager.fileExists(atPath: logFileURL.path) {
            // Check if the file was created on a previous day
            do {
                let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
                if let creationDate = attributes[.creationDate] as? Date,
                   creationDate < startOfDay
                {
                    needNewFile = true
                } else {
                    needNewFile = false
                }
            } catch {
                debug(.service, "Failed to get watch log file attributes: \(error.localizedDescription)")
                needNewFile = true // Default to creating new file if we can't check
            }
        } else {
            needNewFile = true
        }

        if needNewFile {
            let success = fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: [.creationDate: startOfDay])
            if !success {
                debug(.service, "Failed to create watch log file: \(logFileURL.lastPathComponent)")
                return
            }

            // Perform cleanup only when date changes
            performDailyCleanupIfNeeded()
        }

        // Append the log entry
        guard let data = (logContent + "\n").data(using: .utf8) else {
            debug(.service, "Failed to encode watch log content as UTF-8")
            return
        }

        do {
            try data.append(fileURL: logFileURL)
        } catch {
            debug(.service, "Failed to append to watch log \(logFileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Intelligent Cleanup Management

    // Cleanup that runs when date changes - only removes very old logs (beyond retention period)
    private static func performDailyCleanupIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())

        // If we've never done a daily cleanup or it was on a previous day
        if lastDailyCleanupDate == nil || !Calendar.current.isDate(lastDailyCleanupDate!, inSameDayAs: today) {
            // Only remove logs beyond retention period - no zip cleanup here
            cleanupLogs()
            lastDailyCleanupDate = today
            debug(.service, "Performed daily log cleanup on \(Formatter.logDateFormatter.string(from: today))")
        }
    }

    // MARK: - Cleanup Functions

    // Generic helper function for directory cleanup
    private static func cleanupDirectory(
        at directory: URL,
        keepLast: Int? = nil,
        olderThanDays: Int? = nil,
        extensions: [String] = []
    ) throws -> Int {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return 0
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        // Filter by extensions if specified
        let filteredFiles = extensions.isEmpty ? contents : contents.filter { fileURL in
            extensions.contains(fileURL.pathExtension)
        }

        var filesToDelete: [URL] = []

        if let keepLast = keepLast {
            // Sort by creation date (newest first) and keep only the specified number
            let sortedFiles = try filteredFiles.sorted {
                let date1 = try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }

            if sortedFiles.count > keepLast {
                filesToDelete.append(contentsOf: sortedFiles.suffix(from: keepLast))
            }
        }

        if let olderThanDays = olderThanDays {
            // Delete files older than specified days
            let calendar = Calendar.current
            guard let cutoffDate = calendar.date(byAdding: .day, value: -olderThanDays, to: Date()) else {
                return 0
            }

            for fileURL in filteredFiles {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                var fileDate: Date?

                // Special handling for log files with date parsing
                if fileURL.pathExtension == "log" {
                    if filename.hasPrefix("watch_") {
                        // For watch logs, extract the date part after "watch_"
                        let dateStart = filename.index(filename.startIndex, offsetBy: 6)
                        let dateSubstring = String(filename[dateStart...])
                        fileDate = Formatter.logDateFormatter.date(from: dateSubstring)
                    } else {
                        // Regular logs - try to parse the whole filename as a date
                        fileDate = Formatter.logDateFormatter.date(from: filename)
                    }
                }

                // If no date parsed from filename, fall back to file attributes
                if fileDate == nil {
                    do {
                        let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                        // Prefer modification date, fall back to creation date
                        fileDate = attributes.contentModificationDate ?? attributes.creationDate
                    } catch {
                        // If cannot get attributes, skip this file
                        continue
                    }
                }

                if let date = fileDate, date < cutoffDate {
                    filesToDelete.append(fileURL)
                }
            }
        }

        // Remove duplicates (in case a file matches both criteria)
        let uniqueFilesToDelete = Array(Set(filesToDelete))

        var removedCount = 0
        for fileURL in uniqueFilesToDelete {
            do {
                try fileManager.removeItem(at: fileURL)
                removedCount += 1
            } catch {
                debug(
                    .service,
                    "Failed to remove file \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        return removedCount
    }

    // Clean up old log files
    static func cleanupLogs() {
        do {
            let removedCount = try cleanupDirectory(
                at: logsDirectory,
                olderThanDays: logRetentionDays,
                extensions: ["log"]
            )

            if removedCount > 0 {
                debug(.service, "Removed \(removedCount) log file(s) older than \(logRetentionDays) days")
            }
        } catch {
            debug(.service, "Error cleaning up logs: \(error.localizedDescription)")
        }
    }

    // Clean up old zip exports
    static func cleanupZipExports() {
        do {
            let exportsDirectoryURL = try Disk.AppDirectoryURL.logExports()
            let removedCount = try cleanupDirectory(
                at: exportsDirectoryURL,
                keepLast: zipRetentionCount,
                extensions: ["zip"]
            )

            if removedCount > 0 {
                debug(.service, "Removed \(removedCount) old zip files, keeping \(zipRetentionCount) most recent")
            }
        } catch {
            debug(.service, "Error accessing or cleaning up zip exports directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Async Cleanup Methods

    // Combined cleanup method - used by the app's scheduled maintenance
    static func cleanupAllLogsAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                // Full cleanup - both logs and zip files
                cleanupLogs()
                cleanupZipExports()

                // Update daily cleanup date too
                lastDailyCleanupDate = Calendar.current.startOfDay(for: Date())

                debug(.service, "Performed complete log maintenance (scheduled cleanup)")
                continuation.resume()
            }
        }
    }
}

private extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
