import Foundation
import SwiftDate

final class SimpleLogReporter: IssueReporter {
    private let fileManager = FileManager.default

    // Constants for maintenance
    private static let logRetentionDays = 4
    private static let zipRetentionCount = 3

    // Track last cleanup time to avoid redundant cleanups during normal operation
    private static var lastDailyCleanupDate: Date?

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
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
        var names = [currentLogName()]
        for i in 1 ..< logRetentionDays {
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
        if !fileManager.fileExists(atPath: SimpleLogReporter.logDir) {
            try? fileManager.createDirectory(
                atPath: SimpleLogReporter.logDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Create today's log file if it doesn't exist
        if !fileManager.fileExists(atPath: SimpleLogReporter.logFile(name: logName)) {
            createFile(at: startOfDay)

            // Perform cleanup only when date changes
            SimpleLogReporter.performDailyCleanupIfNeeded()
        }

        // Append the log entry
        let logEntry = "\(dateFormatter.string(from: now)) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n"
        let data = logEntry.data(using: .utf8)!
        try? data.append(fileURL: URL(fileURLWithPath: SimpleLogReporter.logFile(name: logName)))
    }

    private func createFile(at date: Date) {
        let logName = SimpleLogReporter.currentLogName()
        fileManager.createFile(atPath: SimpleLogReporter.logFile(name: logName), contents: nil, attributes: [.creationDate: date])
    }

    // MARK: - File Path Utilities

    static func logFile(name: String) -> String {
        let fullpath = getDocumentsDirectory().appendingPathComponent("logs/\(name).log").path
        return fullpath
    }

    static var logDir: String {
        getDocumentsDirectory().appendingPathComponent("logs").path
    }

    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }

    // MARK: - Watch Log Functions

    static func watchLogFile(name: String) -> String {
        getDocumentsDirectory().appendingPathComponent("logs/watch_\(name).log").path
    }

    static func appendToWatchLog(_ logContent: String) {
        let startOfDay = startOfCurrentDay()
        let logName = currentLogName()

        let fileManager = FileManager.default
        let logDir = getDocumentsDirectory().appendingPathComponent("logs")
        let logFile = URL(fileURLWithPath: watchLogFile(name: logName))

        // Create logs directory if needed
        if !fileManager.fileExists(atPath: logDir.path) {
            try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        }

        // Check if need to create a new log file for today
        let needNewFile: Bool
        if fileManager.fileExists(atPath: logFile.path) {
            // Check if the file was created on a previous day
            if let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < startOfDay
            {
                needNewFile = true
            } else {
                needNewFile = false
            }
        } else {
            needNewFile = true
        }

        if needNewFile {
            fileManager.createFile(atPath: logFile.path, contents: nil, attributes: [.creationDate: startOfDay])

            // Perform cleanup only when date changes
            performDailyCleanupIfNeeded()
        }

        // Append the log entry
        if let data = (logContent + "\n").data(using: .utf8) {
            try? data.append(fileURL: logFile)
        }
    }

    // MARK: - Intelligent Cleanup Management

    // Cleanup that runs when date changes - only removes very old logs (beyond retention period)
    private static func performDailyCleanupIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())

        // If we've never done a daily cleanup or it was on a previous day
        if lastDailyCleanupDate == nil || !Calendar.current.isDate(lastDailyCleanupDate!, inSameDayAs: today) {
            // Only remove logs beyond retention period - no zip cleanup here
            cleanupLogDirectory()
            lastDailyCleanupDate = today
            debug(.service, "Performed daily log cleanup on \(Formatter.logDateFormatter.string(from: today))")
        }
    }

    // MARK: - Cleanup Functions

    // Cleanup log files to match retention period
    static func cleanupLogDirectory(retentionDays: Int = logRetentionDays) {
        let fileManager = FileManager.default

        let logDirPath = logDir

        guard fileManager.fileExists(atPath: logDirPath) else {
            return
        }

        do {
            let logDirURL = URL(fileURLWithPath: logDirPath)
            let contents = try fileManager.contentsOfDirectory(
                at: logDirURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let calendar = Calendar.current
            let now = Date()
            guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: now) else {
                return
            }

            let cutoffDateString = Formatter.logDateFormatter.string(from: cutoffDate)
            debug(.service, "Cleaning up log files older than \(cutoffDateString)")

            var removedCount = 0
            for fileURL in contents {
                guard fileURL.pathExtension == "log" else {
                    continue
                }

                let filename = fileURL.deletingPathExtension().lastPathComponent
                var fileDate: Date?

                if filename.hasPrefix("watch_") {
                    // For watch logs, extract the date part after "watch_"
                    let dateStart = filename.index(filename.startIndex, offsetBy: 6)
                    let dateSubstring = String(filename[dateStart...])
                    fileDate = Formatter.logDateFormatter.date(from: dateSubstring)
                } else {
                    // Regular logs - try to parse the whole filename as a date
                    fileDate = Formatter.logDateFormatter.date(from: filename)
                }

                // If no parsing the date from the filename, fall back to file attributes
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
                    do {
                        try fileManager.removeItem(at: fileURL)
                        removedCount += 1
                    } catch {
                        debug(
                            .service,
                            "Failed to remove old log file \(fileURL.lastPathComponent): \(error.localizedDescription)"
                        )
                    }
                }
            }

            if removedCount > 0 {
                debug(.service, "Removed \(removedCount) log files older than the \(retentionDays)-day retention period")
            }

        } catch {
            debug(.service, "Error cleaning up log directory: \(error.localizedDescription)")
        }
    }

    // Clean up zip exports to keep only the most recent ones
    static func cleanupZipExports(maxToKeep: Int = zipRetentionCount) {
        let fileManager = FileManager.default

        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let exportsDirectoryURL = documentsDirectory.appendingPathComponent("LogExports", isDirectory: true)

        // Check if directory exists
        guard fileManager.fileExists(atPath: exportsDirectoryURL.path) else {
            return
        }

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: exportsDirectoryURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Filter and sort zip files by creation date
            let zipFiles = fileURLs.filter { $0.pathExtension == "zip" }
            let sortedFiles = try zipFiles.sorted {
                let date1 = try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }

            if sortedFiles.count > maxToKeep {
                var removedCount = 0
                for fileURL in sortedFiles.suffix(from: maxToKeep) {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        removedCount += 1
                    } catch {
                        debug(
                            .service,
                            "Failed to remove old zip file \(fileURL.lastPathComponent): \(error.localizedDescription)"
                        )
                    }
                }

                if removedCount > 0 {
                    debug(.service, "Removed \(removedCount) old zip files, keeping the \(maxToKeep) most recent")
                }
            }
        } catch {
            debug(.service, "Error cleaning up zip exports: \(error.localizedDescription)")
        }
    }

    // MARK: - Async Cleanup Methods

    static func cleanupLogDirectoryAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                cleanupLogDirectory()
                continuation.resume()
            }
        }
    }

    static func cleanupZipExportsAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                cleanupZipExports()
                continuation.resume()
            }
        }
    }

    // Combined cleanup method - used by the app's scheduled maintenance
    static func cleanupAllLogsAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                // Full cleanup - both logs and zip files
                cleanupLogDirectory()
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
