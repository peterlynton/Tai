import Foundation

/// App-specific directory extensions for the Disk library
public extension Disk {
    /// App-specific subdirectories within standard iOS directories
    enum AppDirectory {
        /// Subdirectory for log files within Documents directory
        /// Files here are backed up by iCloud and persist across app updates
        static let logs = "logs"

        /// Subdirectory for exported log zip files within Documents directory
        /// Files here are backed up by iCloud and can be shared with users
        static let logExports = "logExports"
    }

    /// Convenience methods for accessing app-specific directories
    enum AppDirectoryURL {
        /// URL for the logs directory within Documents
        /// - Returns: URL pointing to Documents/logs/
        /// - Throws: Error if URL creation fails
        static func logs() throws -> URL {
            try Disk.url(for: AppDirectory.logs, in: .documents)
        }

        /// URL for the log exports directory within Documents
        /// - Returns: URL pointing to Documents/LogExports/
        /// - Throws: Error if URL creation fails
        static func logExports() throws -> URL {
            try Disk.url(for: AppDirectory.logExports, in: .documents)
        }

        /// URL for a specific log file within the logs directory
        /// - Parameter name: Log file name (without extension)
        /// - Returns: URL pointing to Documents/logs/{name}.log
        /// - Throws: Error if URL creation fails
        static func logFile(name: String) throws -> URL {
            let logsURL = try logs()
            return logsURL.appendingPathComponent("\(name).log")
        }

        /// URL for a specific watch log file within the logs directory
        /// - Parameter name: Log file name (without extension or watch_ prefix)
        /// - Returns: URL pointing to Documents/logs/watch_{name}.log
        /// - Throws: Error if URL creation fails
        static func watchLogFile(name: String) throws -> URL {
            let logsURL = try logs()
            return logsURL.appendingPathComponent("watch_\(name).log")
        }
    }

    /// Helper methods for consistent filename generation
    enum AppFilenames {
        /// Generate log filename with extension
        /// - Parameter name: Log file name (without extension)
        /// - Returns: Filename string like "2025-06-19.log"
        static func logFile(name: String) -> String {
            "\(name).log"
        }

        /// Generate watch log filename with extension
        /// - Parameter name: Log file name (without extension or watch_ prefix)
        /// - Returns: Filename string like "watch_2025-06-19.log"
        static func watchLogFile(name: String) -> String {
            "watch_\(name).log"
        }
    }
}
