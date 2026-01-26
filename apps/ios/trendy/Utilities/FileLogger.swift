//
//  FileLogger.swift
//  trendy
//
//  File-based logging utility for persistent log storage and retrieval.
//  Complements the os.Logger system by writing logs to files that can be
//  exported for debugging production issues.
//

import Foundation
import UIKit

/// Manages file-based logging with automatic rotation and cleanup.
final class FileLogger: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = FileLogger()

    // MARK: - Configuration

    /// Maximum size of a single log file before rotation (5 MB)
    private let maxFileSize: Int64 = 5 * 1024 * 1024

    /// Maximum number of log files to keep (7 days worth)
    private let maxLogFiles = 7

    /// Date formatter for log file names
    private let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Date formatter for log timestamps
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    // MARK: - State

    private let logDirectory: URL
    private var currentLogFile: URL?
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.trendy.filelogger", qos: .utility)
    private var isEnabled: Bool = true

    // MARK: - Initialization

    private init() {
        // Use app's documents directory for logs
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logDirectory = documentsPath.appendingPathComponent("Logs", isDirectory: true)

        // Create logs directory if needed
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // Open current log file
        openCurrentLogFile()

        // Clean up old logs
        cleanupOldLogs()
    }

    deinit {
        fileHandle?.closeFile()
    }

    // MARK: - Public API

    /// Enable or disable file logging
    func setEnabled(_ enabled: Bool) {
        queue.async {
            self.isEnabled = enabled
        }
    }

    /// Write a log entry to file
    func log(
        level: LogLevel,
        category: String,
        message: String,
        context: String
    ) {
        guard isEnabled else { return }

        queue.async {
            self.writeLog(level: level, category: category, message: message, context: context)
        }
    }

    /// Get all available log files sorted by date (newest first)
    func getLogFiles() -> [LogFileInfo] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "log" }
            .compactMap { url -> LogFileInfo? in
                guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? Int64,
                      let date = attrs[.creationDate] as? Date else {
                    return nil
                }
                return LogFileInfo(url: url, size: size, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Read contents of a specific log file
    func readLogFile(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Delete a specific log file
    func deleteLogFile(at url: URL) {
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Delete all log files
    func deleteAllLogs() {
        queue.async {
            self.fileHandle?.closeFile()
            self.fileHandle = nil
            self.currentLogFile = nil

            let files = self.getLogFiles()
            for file in files {
                try? FileManager.default.removeItem(at: file.url)
            }

            // Reopen for new logs
            self.openCurrentLogFile()
        }
    }

    /// Get the logs directory URL for sharing
    var logsDirectoryURL: URL {
        logDirectory
    }

    /// Create a combined log file for export (all logs concatenated)
    func createExportFile() -> URL? {
        let exportURL = logDirectory.appendingPathComponent("trendy-logs-export.txt")

        // Remove existing export file
        try? FileManager.default.removeItem(at: exportURL)

        let files = getLogFiles().reversed() // Oldest first for chronological order
        var combinedContent = "Trendy App Logs Export\n"
        combinedContent += "Generated: \(timestampFormatter.string(from: Date()))\n"
        combinedContent += "Device: \(UIDevice.current.name)\n"
        combinedContent += "iOS: \(UIDevice.current.systemVersion)\n"
        combinedContent += String(repeating: "=", count: 60) + "\n\n"

        for file in files {
            if let content = readLogFile(at: file.url) {
                combinedContent += "--- \(file.url.lastPathComponent) ---\n"
                combinedContent += content
                combinedContent += "\n\n"
            }
        }

        do {
            try combinedContent.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    private func openCurrentLogFile() {
        let dateString = fileDateFormatter.string(from: Date())
        let fileName = "trendy-\(dateString).log"
        currentLogFile = logDirectory.appendingPathComponent(fileName)

        guard let logFile = currentLogFile else { return }

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }

        // Open for appending
        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()
    }

    private func writeLog(level: LogLevel, category: String, message: String, context: String) {
        // Check if we need to rotate (new day or file too large)
        checkRotation()

        guard let handle = fileHandle else { return }

        let timestamp = timestampFormatter.string(from: Date())
        let levelStr = level.symbol
        let contextStr = context.isEmpty ? "" : " \(context)"

        let logLine = "[\(timestamp)] [\(levelStr)] [\(category)] \(message)\(contextStr)\n"

        if let data = logLine.data(using: .utf8) {
            handle.write(data)
        }
    }

    private func checkRotation() {
        let dateString = fileDateFormatter.string(from: Date())
        let expectedFileName = "trendy-\(dateString).log"
        let expectedFile = logDirectory.appendingPathComponent(expectedFileName)

        // Check if we need a new file (new day)
        if currentLogFile != expectedFile {
            fileHandle?.closeFile()
            openCurrentLogFile()
            cleanupOldLogs()
            return
        }

        // Check if file is too large
        if let handle = fileHandle {
            let currentSize = handle.offsetInFile
            if currentSize > UInt64(maxFileSize) {
                // Rotate by adding timestamp suffix
                fileHandle?.closeFile()
                let newName = "trendy-\(dateString)-\(Int(Date().timeIntervalSince1970)).log"
                let rotatedFile = logDirectory.appendingPathComponent(newName)
                try? FileManager.default.moveItem(at: expectedFile, to: rotatedFile)
                openCurrentLogFile()
            }
        }
    }

    private func cleanupOldLogs() {
        let files = getLogFiles()
        if files.count > maxLogFiles {
            let filesToDelete = files.suffix(from: maxLogFiles)
            for file in filesToDelete {
                try? FileManager.default.removeItem(at: file.url)
            }
        }
    }
}

// MARK: - Supporting Types

/// Information about a log file
struct LogFileInfo: Identifiable {
    let url: URL
    let size: Int64
    let date: Date

    var id: String { url.path }

    var name: String {
        url.lastPathComponent
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Log levels for file logging
enum LogLevel: String {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    var symbol: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }
}
