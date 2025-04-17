import Foundation
import SwiftDate

final class SimpleLogReporter: IssueReporter {
    private let fileManager = FileManager.default

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }

    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let logName = Formatter.logdateFormatter.string(from: now)
        let twoDaysPrior = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let prevLogName = Formatter.logdateFormatter.string(from: twoDaysPrior)

        if !fileManager.fileExists(atPath: SimpleLogReporter.logDir) {
            try? fileManager.createDirectory(
                atPath: SimpleLogReporter.logDir,
                withIntermediateDirectories: false,
                attributes: nil
            )
        }

        if !fileManager.fileExists(atPath: SimpleLogReporter.logFile(name: logName)) {
            createFile(at: startOfDay)
            try? fileManager.removeItem(atPath: SimpleLogReporter.logFilePrev(name: prevLogName))
            debug(.service, "Removing log file from 2 days ago: \(SimpleLogReporter.logFilePrev(name: prevLogName))")
        }

        let logEntry = "\(dateFormatter.string(from: now)) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n"
        let data = logEntry.data(using: .utf8)!
        try? data.append(fileURL: URL(fileURLWithPath: SimpleLogReporter.logFile(name: logName)))
    }

    private func createFile(at date: Date) {
        let now = Date()
        let logName = Formatter.logdateFormatter.string(from: now)
        fileManager.createFile(atPath: SimpleLogReporter.logFile(name: logName), contents: nil, attributes: [.creationDate: date])
    }

    static func logFile(name: String) -> String {
        let fullpath = getDocumentsDirectory().appendingPathComponent("logs/\(name).log").path
        return fullpath
    }

    static var logDir: String {
        getDocumentsDirectory().appendingPathComponent("logs").path
    }

    static func logFilePrev(name: String) -> String {
        let fullpath = getDocumentsDirectory().appendingPathComponent("logs/\(name).log").path
        return fullpath
    }

    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
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
