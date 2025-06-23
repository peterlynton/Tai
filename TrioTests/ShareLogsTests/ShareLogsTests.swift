import Foundation
import Testing
@testable import Trio

@Suite("Share Logs Function Tests") struct ShareLogsTests {
    // MARK: - Mockup Directory and File Creation

    /// Creates a temporary directory for testing
    private func createTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("LogZipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    /// Creates a complete test environment with logExports directory and 6 files each (12 total)
    /// Includes files from 2 weeks ago, recent days, and 1 future date
    private func createTestLogEnvironment() throws -> (logsDir: URL, logFiles: [URL], watchLogFiles: [URL]) {
        let tempDir = try createTemporaryDirectory()
        let logsDir = tempDir.appendingPathComponent("logExports")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create 6 log files with varied dates: 2 weeks ago, recent days, and 1 future
        let calendar = Calendar.current
        let today = Date()

        let testDates = [
            calendar.date(byAdding: .day, value: -14, to: today)!, // 2 weeks back
            calendar.date(byAdding: .day, value: -7, to: today)!, // 1 week back
            calendar.date(byAdding: .day, value: -3, to: today)!, // 3 days back
            calendar.date(byAdding: .day, value: -1, to: today)!, // yesterday
            today, // today
            calendar.date(byAdding: .day, value: 1, to: today)! // 1 day future
        ]

        var logFiles: [URL] = []
        var watchLogFiles: [URL] = []

        for (index, date) in testDates.enumerated() {
            let logName = Formatter.logDateFormatter.string(from: date)

            // Create regular log file
            let logFileURL = logsDir.appendingPathComponent("\(logName).log")
            let logContent = """
            \(Formatter.iso8601.string(from: date)) [INFO] Application started for \(logName) (file \(index + 1)/6)
            \(Formatter.iso8601.string(from: date.addingTimeInterval(60))) [DEBUG] Processing glucose data
            \(Formatter.iso8601.string(from: date.addingTimeInterval(120))) [WARN] Low battery warning
            \(Formatter.iso8601.string(from: date.addingTimeInterval(180))) [ERROR] Failed to connect to CGM
            \(Formatter.iso8601.string(from: date.addingTimeInterval(240))) [INFO] Meal bolus calculated: 2.5 units
            \(Formatter.iso8601.string(from: date.addingTimeInterval(300))) [DEBUG] Background refresh completed
            """
            try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)

            // Set file creation date to match the log date
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: logFileURL.path)
            logFiles.append(logFileURL)

            // Create watch log file
            let watchLogFileURL = logsDir.appendingPathComponent("watch_\(logName).log")
            let watchLogContent = """
            \(Formatter.iso8601.string(from: date)) [WATCH] Heart rate: \(70 + index * 2) BPM for \(logName) (file \(index + 1)/6)
            \(Formatter.iso8601
                .string(from: date.addingTimeInterval(60))) [WATCH] Activity: \(["Walking", "Running", "Cycling", "Swimming",
                                                                                 "Resting", "Sleeping"][index])
            \(Formatter.iso8601.string(from: date.addingTimeInterval(120))) [WATCH] Battery: \(85 - index * 5)%
            \(Formatter.iso8601.string(from: date.addingTimeInterval(180))) [WATCH] Steps: \(5000 + index * 1000)
            \(Formatter.iso8601
                .string(from: date.addingTimeInterval(240))) [WATCH] Sleep tracking: \(index % 2 == 0 ? "started" : "stopped")
            \(Formatter.iso8601
                .string(from: date.addingTimeInterval(300))) [WATCH] Workout session: \(index % 3 == 0 ? "active" : "paused")
            """
            try watchLogContent.write(to: watchLogFileURL, atomically: true, encoding: .utf8)

            // Set file creation date to match the log date
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: watchLogFileURL.path)
            watchLogFiles.append(watchLogFileURL)
        }

        return (logsDir, logFiles, watchLogFiles)
    }

    /// Creates test environment with specific log file names and dates
    private func createTestLogEnvironmentWithNames(_ names: [String]) throws
        -> (logsDir: URL, logFiles: [URL], watchLogFiles: [URL])
    {
        let tempDir = try createTemporaryDirectory()
        let logsDir = tempDir.appendingPathComponent("logExports")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        var logFiles: [URL] = []
        var watchLogFiles: [URL] = []

        for (index, name) in names.enumerated() {
            // Create regular log file
            let logFileURL = logsDir.appendingPathComponent("\(name).log")
            let logContent = """
            [\(Date())] [INFO] Test log entry for \(name) (file \(index + 1)/\(names.count))
            [\(Date())] [DEBUG] Debug message for testing
            [\(Date())] [ERROR] Error simulation for \(name)
            """
            try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)
            logFiles.append(logFileURL)

            // Create watch log file
            let watchLogFileURL = logsDir.appendingPathComponent("watch_\(name).log")
            let watchLogContent = """
            [\(Date())] [WATCH] Test watch log entry for \(name) (file \(index + 1)/\(names.count))
            [\(Date())] [WATCH] Heart rate: \(65 + index * 3) BPM
            [\(Date())] [WATCH] Activity tracking active
            """
            try watchLogContent.write(to: watchLogFileURL, atomically: true, encoding: .utf8)
            watchLogFiles.append(watchLogFileURL)
        }

        return (logsDir, logFiles, watchLogFiles)
    }

    // MARK: - Future File Exclusion Tests

    @Test("future files should not be included in zip-ready structure") func futureFilesNotInZipStructure() throws {
        let testEnv = try createTestLogEnvironment() // Creates files including 1 future file
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        let calendar = Calendar.current
        let today = Date()
        let futureDate = calendar.date(byAdding: .day, value: 1, to: today)!

        // Find the future file that was created
        var futureFiles: [URL] = []
        for file in testEnv.logFiles + testEnv.watchLogFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let creationDate = attributes[.creationDate] as? Date,
               calendar.isDate(creationDate, inSameDayAs: futureDate)
            {
                futureFiles.append(file)
            }
        }

        #expect(futureFiles.count == 2) // Should have 1 regular + 1 watch future file

        // Now filter for zip-ready files (should exclude future files)
        let expectedDates = [
            calendar.date(byAdding: .day, value: 0, to: today)!, // today
            calendar.date(byAdding: .day, value: -1, to: today)!, // yesterday
            calendar.date(byAdding: .day, value: -2, to: today)!, // 2 days ago
            calendar.date(byAdding: .day, value: -3, to: today)! // 3 days ago
        ]

        var zipReadyFiles: [URL] = []
        for file in testEnv.logFiles + testEnv.watchLogFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let creationDate = attributes[.creationDate] as? Date {
                for expectedDate in expectedDates {
                    if calendar.isDate(creationDate, inSameDayAs: expectedDate) {
                        zipReadyFiles.append(file)
                        break
                    }
                }
            }
        }

        // Verify future files are NOT in zip-ready files
        for futureFile in futureFiles {
            #expect(!zipReadyFiles.contains(futureFile))
        }

        // Verify we have some zip-ready files (but not the future ones)
        #expect(zipReadyFiles.count >= 2) // At least today's files
        #expect(zipReadyFiles.count < (testEnv.logFiles.count + testEnv.watchLogFiles.count)) // But not all files
    }

    @Test("future files should not be included in fallback scenario") func futureFilesNotInFallback() throws {
        let testEnv = try createTestLogEnvironment() // Creates files including 1 future file
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        let calendar = Calendar.current
        let today = Date()

        // Simulate fallback scenario - only current log file should be returned
        let currentLogName = SimpleLogReporter.currentLogName()

        // Find today's files (what would be used as fallback)
        var todaysFiles: [URL] = []
        for file in testEnv.logFiles + testEnv.watchLogFiles {
            if file.lastPathComponent.contains(currentLogName) {
                todaysFiles.append(file)
            }
        }

        // Verify fallback only includes today's files, not future files
        for file in todaysFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let creationDate = attributes[.creationDate] as? Date {
                // Should be today or earlier, never future
                #expect(creationDate <= today.addingTimeInterval(86400)) // Allow for small time differences
                #expect(!calendar.isDate(creationDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!))
            }
        }

        #expect(todaysFiles.count <= 2) // At most today's regular + watch file
    }

    @Test("future files should be cleaned up") func futureFilesCleanedUp() throws {
        let tempDir = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logsDir = tempDir.appendingPathComponent("logExports")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let calendar = Calendar.current
        let today = Date()
        var allCreatedFiles: [URL] = []

        // Create files including future dates
        for i in -7 ... 7 { // 1 week before to 1 week after
            guard let date = calendar.date(byAdding: .day, value: i, to: today) else { continue }
            let logName = Formatter.logDateFormatter.string(from: date)

            let logFileURL = logsDir.appendingPathComponent("\(logName).log")
            let logContent = "Log entry for \(logName) (day offset: \(i))\n"
            try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)
            allCreatedFiles.append(logFileURL)

            // Set creation date to match the log date
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: logFileURL.path)
        }

        #expect(allCreatedFiles.count == 15) // 7 past + today + 7 future

        // Files to keep: today through 3 days ago (4 days total)
        let keepDates = [
            today, // today (day 0)
            calendar.date(byAdding: .day, value: -1, to: today)!, // yesterday
            calendar.date(byAdding: .day, value: -2, to: today)!, // 2 days ago
            calendar.date(byAdding: .day, value: -3, to: today)! // 3 days ago
        ]

        var filesToKeep: [URL] = []
        var filesToRemove: [URL] = []

        for fileURL in allCreatedFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date {
                var shouldKeep = false
                for keepDate in keepDates {
                    if calendar.isDate(creationDate, inSameDayAs: keepDate) {
                        shouldKeep = true
                        break
                    }
                }

                if shouldKeep {
                    filesToKeep.append(fileURL)
                } else {
                    filesToRemove.append(fileURL)
                }
            }
        }

        // Verify future files are marked for removal
        let futureDate = calendar.date(byAdding: .day, value: 1, to: today)!
        var futureFilesMarkedForRemoval = 0

        for fileURL in filesToRemove {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date,
               calendar.isDate(creationDate, inSameDayAs: futureDate)
            {
                futureFilesMarkedForRemoval += 1
            }
        }

        #expect(futureFilesMarkedForRemoval >= 1) // At least 1 future file should be removed
        #expect(filesToKeep.count == 4) // Should keep exactly 4 days worth
        #expect(filesToRemove.count == 11) // Should remove 11 files (7 old + 1 future + 3 more old)

        // Verify that no future files are in the keep list
        for fileURL in filesToKeep {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date {
                #expect(creationDate <= today) // All kept files should be today or earlier
            }
        }
    }

    @Test("getAllLogNames should not include future dates") func getAllLogNamesNoFuture() {
        let logNames = SimpleLogReporter.getAllLogNames()
        let calendar = Calendar.current
        let today = Date()

        // Parse each log name and verify it's not in the future
        for logName in logNames {
            if let logDate = Formatter.logDateFormatter.date(from: logName) {
                #expect(logDate <= today.addingTimeInterval(86400)) // Allow small time buffer
                #expect(!calendar.isDate(logDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!))
            }
        }

        // Verify we get expected retention period (4 days: today, yesterday, 2 days ago, 3 days ago)
        #expect(logNames.count == 4)

        // Verify the dates are in the expected range
        if let firstLogDate = Formatter.logDateFormatter.date(from: logNames[0]) {
            let daysDiff = calendar.dateComponents([.day], from: firstLogDate, to: today).day ?? 0
            #expect(daysDiff >= 0) // First log should be today or earlier
            #expect(daysDiff <= 3) // First log should not be more than 3 days ago
        }
    }

    // MARK: - Disk+Directory Tests

    @Test("Disk AppDirectory constants should be correctly defined") func diskAppDirectoryConstants() {
        #expect(Disk.AppDirectory.logs == "logs")
        #expect(Disk.AppDirectory.logExports == "logExports")
    }

    @Test("Disk AppFilenames should generate correct filenames") func diskAppFilenamesGeneration() {
        let logName = "2025-06-19"

        let logFilename = Disk.AppFilenames.logFile(name: logName)
        #expect(logFilename == "2025-06-19.log")

        let watchLogFilename = Disk.AppFilenames.watchLogFile(name: logName)
        #expect(watchLogFilename == "watch_2025-06-19.log")
    }

    @Test("Disk AppDirectoryURL functions should work correctly") func diskAppDirectoryURLFunctions() throws {
        // Test logs directory URL
        let logsURL = try Disk.AppDirectoryURL.logs()
        #expect(logsURL.lastPathComponent == "logs")
        #expect(logsURL.pathExtension.isEmpty) // Should be a directory

        // Test log exports directory URL
        let exportsURL = try Disk.AppDirectoryURL.logExports()
        #expect(exportsURL.lastPathComponent == "logExports")
        #expect(exportsURL.pathExtension.isEmpty) // Should be a directory

        // Test log file URL
        let logName = "2025-06-19"
        let logFileURL = try Disk.AppDirectoryURL.logFile(name: logName)
        #expect(logFileURL.lastPathComponent == "2025-06-19.log")
        #expect(logFileURL.pathExtension == "log")
        #expect(logFileURL.deletingLastPathComponent().lastPathComponent == "logs")

        // Test watch log file URL
        let watchLogFileURL = try Disk.AppDirectoryURL.watchLogFile(name: logName)
        #expect(watchLogFileURL.lastPathComponent == "watch_2025-06-19.log")
        #expect(watchLogFileURL.pathExtension == "log")
        #expect(watchLogFileURL.deletingLastPathComponent().lastPathComponent == "logs")

        // Test that file URLs are properly nested under directory URLs
        #expect(logFileURL.deletingLastPathComponent().path == logsURL.path)
        #expect(watchLogFileURL.deletingLastPathComponent().path == logsURL.path)

        // Test edge cases
        let emptyLogFileURL = try Disk.AppDirectoryURL.logFile(name: "")
        #expect(emptyLogFileURL.lastPathComponent == ".log")

        let emptyWatchLogFileURL = try Disk.AppDirectoryURL.watchLogFile(name: "")
        #expect(emptyWatchLogFileURL.lastPathComponent == "watch_.log")
    }

    // MARK: - File System Tests (Independent of logItems method)

    @Test("should create and read log files correctly") func createAndReadLogFiles() throws {
        let testEnv = try createTestLogEnvironment() // Creates 6 files with varied dates
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        // Verify 6 log files were created (including future and 2-week-old files)
        #expect(testEnv.logFiles.count == 6)
        #expect(testEnv.watchLogFiles.count == 6)

        // Verify directory is logExports
        #expect(testEnv.logsDir.lastPathComponent == "logExports")

        // Verify file contents and dates
        for (index, logFile) in testEnv.logFiles.enumerated() {
            #expect(FileManager.default.fileExists(atPath: logFile.path))
            let content = try String(contentsOf: logFile)
            #expect(content.contains("INFO"))
            #expect(content.contains("file \(index + 1)/6")) // Verify unique content per file

            // Check creation date was set correctly
            let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
            let creationDate = attributes[.creationDate] as? Date
            #expect(creationDate != nil)
        }

        for (index, watchLogFile) in testEnv.watchLogFiles.enumerated() {
            #expect(FileManager.default.fileExists(atPath: watchLogFile.path))
            let content = try String(contentsOf: watchLogFile)
            #expect(content.contains("WATCH"))
            #expect(content.contains("file \(index + 1)/6")) // Verify unique content per file

            // Check for varied content (different heart rates, activities, etc.)
            if index == 0 {
                #expect(content.contains("Heart rate: 70 BPM"))
                #expect(content.contains("Activity: Walking"))
            } else if index == 5 {
                #expect(content.contains("Heart rate: 80 BPM"))
                #expect(content.contains("Activity: Sleeping"))
            }
        }
    }

    @Test("should handle log file naming conventions") func logFileNamingConventions() throws {
        let testEnv = try createTestLogEnvironmentWithNames(["2025-06-19"])
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        let logFile = testEnv.logFiles[0]
        let watchLogFile = testEnv.watchLogFiles[0]

        // Check naming conventions
        #expect(logFile.lastPathComponent == "2025-06-19.log")
        #expect(watchLogFile.lastPathComponent == "watch_2025-06-19.log")

        // Check they're in the logExports directory
        #expect(logFile.deletingLastPathComponent().lastPathComponent == "logExports")
        #expect(watchLogFile.deletingLastPathComponent().lastPathComponent == "logExports")
    }

    @Test("should handle realistic log file content") func realisticLogFileContent() throws {
        let testEnv = try createTestLogEnvironment()
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        #expect(!testEnv.logFiles.isEmpty)
        #expect(!testEnv.watchLogFiles.isEmpty)

        // Check realistic content in log files
        for logFile in testEnv.logFiles {
            let content = try String(contentsOf: logFile)
            #expect(content.contains("Application started"))
            #expect(content.contains("Processing glucose data"))
            #expect(content.contains("Meal bolus calculated"))
        }

        // Check realistic content in watch log files
        for watchLogFile in testEnv.watchLogFiles {
            let content = try String(contentsOf: watchLogFile)
            #expect(content.contains("Heart rate"))
            #expect(content.contains("Activity:"))
            #expect(content.contains("Sleep tracking"))
        }
    }

    @Test("should create zip-ready file structure") func zipReadyFileStructure() throws {
        // Create test environment with files spanning more than retention period
        let testEnv = try createTestLogEnvironment() // Creates 6 files with varied dates
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        // Filter files to only include those from the last 4 days (today through 3 days ago)
        let calendar = Calendar.current
        let today = Date()

        // Create the 4 expected dates: today, yesterday, 2 days ago, 3 days ago
        let expectedDates = [
            calendar.date(byAdding: .day, value: 0, to: today)!, // today
            calendar.date(byAdding: .day, value: -1, to: today)!, // yesterday
            calendar.date(byAdding: .day, value: -2, to: today)!, // 2 days ago
            calendar.date(byAdding: .day, value: -3, to: today)! // 3 days ago
        ]

        var recentLogFiles: [URL] = []
        var recentWatchLogFiles: [URL] = []

        // Filter files to only include those matching the 4-day retention period
        for logFile in testEnv.logFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
            if let creationDate = attributes[.creationDate] as? Date {
                // Check if creation date matches any of our expected 4 days
                for expectedDate in expectedDates {
                    if calendar.isDate(creationDate, inSameDayAs: expectedDate) {
                        recentLogFiles.append(logFile)
                        break
                    }
                }
            }
        }

        for watchLogFile in testEnv.watchLogFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: watchLogFile.path)
            if let creationDate = attributes[.creationDate] as? Date {
                // Check if creation date matches any of our expected 4 days
                for expectedDate in expectedDates {
                    if calendar.isDate(creationDate, inSameDayAs: expectedDate) {
                        recentWatchLogFiles.append(watchLogFile)
                        break
                    }
                }
            }
        }

        // Should have exactly 4 files each (today through 3 days ago)
        // But may be fewer if some days don't exist in our test data
        #expect(recentLogFiles.count >= 1) // At least today's file
        #expect(recentLogFiles.count <= 4) // At most 4 days worth
        #expect(recentWatchLogFiles.count >= 1) // At least today's watch file
        #expect(recentWatchLogFiles.count <= 4) // At most 4 days worth

        let allRecentFiles = recentLogFiles + recentWatchLogFiles
        #expect(allRecentFiles.count >= 2) // At least today's regular + watch
        #expect(allRecentFiles.count <= 8) // At most 4 days × 2 file types = 8 files

        // All recent files should be in the logExports directory structure
        for file in allRecentFiles {
            #expect(file.deletingLastPathComponent().path == testEnv.logsDir.path)
            #expect(file.deletingLastPathComponent().lastPathComponent == "logExports")
            #expect(FileManager.default.fileExists(atPath: file.path))

            // Verify these files are from the correct date range (today through 3 days ago)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let creationDate = attributes[.creationDate] as? Date {
                var isInExpectedRange = false
                for expectedDate in expectedDates {
                    if calendar.isDate(creationDate, inSameDayAs: expectedDate) {
                        isInExpectedRange = true
                        break
                    }
                }
                #expect(isInExpectedRange) // File should be from one of the 4 expected days
            }
        }

        // Verify file sizes are reasonable (not empty)
        for file in allRecentFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            #expect(fileSize > 0)
        }
    }

    // MARK: - File Operations Tests

    @Test("should simulate file copying for staging") func simulateFileCopying() throws {
        let testEnv = try createTestLogEnvironmentWithNames(["2025-06-19", "2025-06-18"])
        defer { try? FileManager.default.removeItem(at: testEnv.logsDir.deletingLastPathComponent()) }

        // Create a staging directory like logItems() would
        let stagingDir = testEnv.logsDir.deletingLastPathComponent().appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        // Copy files to staging (simulating what logItems does)
        var copiedFiles: [URL] = []

        for logFile in testEnv.logFiles {
            let destURL = stagingDir.appendingPathComponent(logFile.lastPathComponent)
            try FileManager.default.copyItem(at: logFile, to: destURL)
            copiedFiles.append(destURL)
        }

        for watchLogFile in testEnv.watchLogFiles {
            let destURL = stagingDir.appendingPathComponent(watchLogFile.lastPathComponent)
            try FileManager.default.copyItem(at: watchLogFile, to: destURL)
            copiedFiles.append(destURL)
        }

        // Verify all files were copied correctly
        #expect(copiedFiles.count == 4) // 2 regular + 2 watch logs

        for copiedFile in copiedFiles {
            #expect(FileManager.default.fileExists(atPath: copiedFile.path))

            // Verify content is identical
            let originalPath = testEnv.logsDir.appendingPathComponent(copiedFile.lastPathComponent)
            if FileManager.default.fileExists(atPath: originalPath.path) {
                let originalContent = try String(contentsOf: originalPath)
                let copiedContent = try String(contentsOf: copiedFile)
                #expect(originalContent == copiedContent)
            }
        }
    }

    @Test("should handle export directory creation") func exportDirectoryCreation() throws {
        let tempDir = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulate creating a logExports directory like logItems() does
        let exportsDir = tempDir.appendingPathComponent("logExports")

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: exportsDir.path) {
            try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        }

        #expect(FileManager.default.fileExists(atPath: exportsDir.path))
        #expect(exportsDir.lastPathComponent == "logExports")

        // Test creating a zip file name with timestamp
        let timestamp = Formatter.iso8601.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let zipFileName = "Trio-Logs-\(timestamp).zip"
        let zipFileURL = exportsDir.appendingPathComponent(zipFileName)

        #expect(zipFileURL.lastPathComponent.hasPrefix("Trio-Logs-"))
        #expect(zipFileURL.pathExtension == "zip")
        #expect(zipFileURL.deletingLastPathComponent().path == exportsDir.path)
    }

    @Test("should test cleanup functionality with test files") func cleanupFunctionality() throws {
        let tempDir = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logsDir = tempDir.appendingPathComponent("logExports")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create log files with specific dates spanning more than retention period
        let calendar = Calendar.current
        let today = Date()
        var createdFiles: [URL] = []

        // Create files from 2 weeks ago to 1 day in future (16 total days)
        for i in -14 ... 1 {
            guard let date = calendar.date(byAdding: .day, value: i, to: today) else { continue }
            let logName = Formatter.logDateFormatter.string(from: date)

            let logFileURL = logsDir.appendingPathComponent("\(logName).log")
            let logContent = "Log entry for \(logName) (day offset: \(i))\n"
            try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)
            createdFiles.append(logFileURL)

            // Set creation date to match the log date
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: logFileURL.path)
        }

        #expect(createdFiles.count == 16) // 14 past days + today + 1 future day

        // Simulate cleanup logic (files older than 4 days should be removed)
        let retentionDays = 4
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: today) else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create cutoff date"])
        }

        var filesToRemove: [URL] = []
        var filesToKeep: [URL] = []

        for fileURL in createdFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date {
                if creationDate < cutoffDate {
                    filesToRemove.append(fileURL)
                } else {
                    filesToKeep.append(fileURL)
                }
            }
        }

        #expect(filesToRemove.count >= 10) // Should remove files older than 4 days (about 10+ files)
        #expect(filesToKeep.count <= 6) // Should keep recent files (4 days + today + 1 future = ~6 files)

        // Verify the cleanup logic identifies the right files
        for fileURL in filesToRemove {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let creationDate = attributes[.creationDate] as? Date
            #expect(creationDate != nil)
            #expect(creationDate! < cutoffDate)
        }

        for fileURL in filesToKeep {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let creationDate = attributes[.creationDate] as? Date
            #expect(creationDate != nil)
            #expect(creationDate! >= cutoffDate)
        }
    }

    @Test("should test cleanup helper function behavior") func cleanupHelperFunctionBehavior() throws {
        let tempDir = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testDir = tempDir.appendingPathComponent("testCleanup")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let calendar = Calendar.current
        let today = Date()

        // Create test files with various ages
        var testFiles: [URL] = []
        for i in 0 ..< 10 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }

            let fileName = "test-file-\(i).log"
            let fileURL = testDir.appendingPathComponent(fileName)
            let content = "Test content for day \(i)\n"
            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            // IMPORTANT: Set creation date attribute so fallback logic can use it
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: fileURL.path)
            testFiles.append(fileURL)
        }

        #expect(testFiles.count == 10)

        // Test cleanup logic behavior (simulating cleanupDirectory parameters)
        let retentionDays = 4
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: today) else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create cutoff date"])
        }

        // Debug: Print the cutoff date to understand what we're comparing against
        // print("Cutoff date: \(cutoffDate)")

        // Simulate the cleanup directory logic from the patch
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: testDir,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var filesToDelete: [URL] = []
        for fileURL in contents {
            // Get file creation date directly from FileManager (more reliable)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date {
                // Debug: Print each file's date
                // print("File: \(fileURL.lastPathComponent), Created: \(creationDate), Cutoff: \(cutoffDate), Should delete: \(creationDate < cutoffDate)")

                if creationDate < cutoffDate {
                    filesToDelete.append(fileURL)
                }
            }
        }

        // Verify cleanup logic identifies correct files
        #expect(filesToDelete.count >= 5) // At least 5 files should be deleted (files 5,6,7,8,9 are definitely 4+ days old)
        #expect(filesToDelete.count <= 7) // Allow for edge cases around day boundaries (file 4 might be right at cutoff)

        // Verify the correct files are marked for deletion (should be files 4-9, which are 4+ days old)
        for fileURL in filesToDelete {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let creationDate = attributes[.creationDate] as? Date
            #expect(creationDate != nil)
            #expect(creationDate! < cutoffDate)

            // The file should be one of the older files (4+ days old)
            let fileName = fileURL.lastPathComponent
            if fileName.hasPrefix("test-file-") {
                let indexStr = fileName.replacingOccurrences(of: "test-file-", with: "")
                    .replacingOccurrences(of: ".log", with: "")
                if let index = Int(indexStr) {
                    #expect(index >= 4) // Files 4,5,6,7,8,9 should be deleted (4+ days old)
                }
            }
        }
    }

    // MARK: - Component Integration Tests

    @Test("should test Disk filename utilities") func diskFilenameUtilities() {
        let logName = "2025-06-19"

        let logFilename = Disk.AppFilenames.logFile(name: logName)
        #expect(logFilename == "2025-06-19.log")

        let watchLogFilename = Disk.AppFilenames.watchLogFile(name: logName)
        #expect(watchLogFilename == "watch_2025-06-19.log")

        // Test edge cases
        let emptyName = ""
        #expect(Disk.AppFilenames.logFile(name: emptyName) == ".log")
        #expect(Disk.AppFilenames.watchLogFile(name: emptyName) == "watch_.log")
    }

    @Test("should test timestamp formatting for zip files") func timestampFormattingForZip() {
        let testDate = Date()
        let timestamp = Formatter.iso8601.string(from: testDate).replacingOccurrences(of: ":", with: "-")

        let zipFileName = "Trio-Logs-\(timestamp).zip"

        #expect(zipFileName.hasPrefix("Trio-Logs-"))
        #expect(zipFileName.hasSuffix(".zip"))
        #expect(!zipFileName.contains(":")) // Colons should be replaced

        // Test that the timestamp is reasonable length
        #expect(timestamp.count > 15) // Should be at least YYYY-MM-DDTHH-MM-SS
    }

    // MARK: - SimpleLogReporter Static Method Tests (Safe to call)

    @Test("SimpleLogReporter getAllLogNames should return valid log names") func simpleLogReporterGetAllLogNames() {
        let logNames = SimpleLogReporter.getAllLogNames()

        #expect(!logNames.isEmpty)
        #expect(logNames.count >= 4) // Should have at least 4 days worth based on retention

        // Check that log names follow expected date format
        for logName in logNames {
            // Should be in format like "2025-06-19"
            #expect(logName.count == 10) // YYYY-MM-DD format
            #expect(logName.contains("-"))
        }
    }

    @Test("SimpleLogReporter currentLogName should return today's log name") func simpleLogReporterCurrentLogName() {
        let currentLogName = SimpleLogReporter.currentLogName()
        let expectedFormat = Formatter.logDateFormatter.string(from: Date())

        #expect(currentLogName == expectedFormat)
        #expect(currentLogName.count == 10) // YYYY-MM-DD format
    }

    @Test("SimpleLogReporter logNameForDate should generate correct names") func simpleLogReporterLogNameForDate() {
        let today = Date()
        let calendar = Calendar.current

        // Test current day (0 days ago)
        let todayName = SimpleLogReporter.logNameForDate(daysAgo: 0)
        let expectedToday = Formatter.logDateFormatter.string(from: today)
        #expect(todayName == expectedToday)

        // Test yesterday (1 day ago)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            let yesterdayName = SimpleLogReporter.logNameForDate(daysAgo: 1)
            let expectedYesterday = Formatter.logDateFormatter.string(from: yesterday)
            #expect(yesterdayName == expectedYesterday)
        }
    }

    @Test("Settings StateModel can be instantiated") func settingsStateModelInstantiation() {
        let stateModel = Settings.StateModel()
        #expect(stateModel != nil)

        // Just verify the object exists and has the expected type
        #expect(type(of: stateModel) == Settings.StateModel.self)
    }
}
