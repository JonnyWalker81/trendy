//
//  Logger.swift
//  trendy
//
//  Structured logging utility using Apple's unified logging system (os.Logger).
//  Provides consistent, categorized logging across the app with environment-aware
//  verbosity levels. Also writes to persistent files via FileLogger for debugging.
//

import Foundation
import os

/// Centralized logging utility for the Trendy app.
/// Uses Apple's unified logging system (os.Logger) for native integration
/// with Console.app and performance-optimized log collection.
/// Also writes to file via FileLogger for persistent storage and export.
enum Log {

    // MARK: - Log Categories

    /// Logger for API/network operations
    static let api = Logger(subsystem: subsystem, category: "api")

    /// Logger for authentication operations
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Logger for data synchronization
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Logger for data migration
    static let migration = Logger(subsystem: subsystem, category: "migration")

    /// Logger for geofence operations
    static let geofence = Logger(subsystem: subsystem, category: "geofence")

    /// Logger for HealthKit integration
    static let healthKit = Logger(subsystem: subsystem, category: "healthkit")

    /// Logger for calendar integration
    static let calendar = Logger(subsystem: subsystem, category: "calendar")

    /// Logger for UI/view operations
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logger for data/storage operations
    static let data = Logger(subsystem: subsystem, category: "data")

    /// General-purpose logger
    static let general = Logger(subsystem: subsystem, category: "general")

    // MARK: - Private Properties

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.trendy.app"

    // MARK: - File Logging Control

    /// Enable or disable file logging (useful for performance-sensitive scenarios)
    static func setFileLoggingEnabled(_ enabled: Bool) {
        FileLogger.shared.setEnabled(enabled)
    }

    // MARK: - Helper Types

    /// Structured context for logging additional metadata
    struct Context: CustomStringConvertible {
        private var fields: [(String, Any)]

        init(_ fields: [(String, Any)] = []) {
            self.fields = fields
        }

        /// Add a string field
        mutating func add(_ key: String, _ value: String?) {
            if let value = value {
                fields.append((key, value))
            }
        }

        /// Add an integer field
        mutating func add(_ key: String, _ value: Int) {
            fields.append((key, value))
        }

        /// Add a boolean field
        mutating func add(_ key: String, _ value: Bool) {
            fields.append((key, value))
        }

        /// Add a double field
        mutating func add(_ key: String, _ value: Double) {
            fields.append((key, value))
        }

        /// Add an error field
        mutating func add(error: Error) {
            fields.append(("error", error.localizedDescription))
        }

        /// Add a UUID field
        mutating func add(_ key: String, _ value: UUID) {
            fields.append((key, value.uuidString))
        }

        /// Add a duration field (in seconds)
        mutating func add(duration: TimeInterval) {
            fields.append(("duration_ms", Int(duration * 1000)))
        }

        var description: String {
            guard !fields.isEmpty else { return "" }
            let pairs = fields.map { "\($0.0)=\($0.1)" }
            return " [\(pairs.joined(separator: ", "))]"
        }
    }
}

// MARK: - Logger Extensions

extension Logger {

    /// The category name extracted from the logger (for file logging)
    private var category: String {
        // Logger doesn't expose category directly, but we can use a workaround
        // by storing category in a computed way or using the description
        String(describing: self).components(separatedBy: "category: ").last?.components(separatedBy: ")").first ?? "general"
    }

    /// Log at debug level with optional context
    func debug(_ message: String, context: Log.Context = Log.Context()) {
        let fullMessage = "\(message)\(context.description)"
        self.log(level: .debug, "\(fullMessage, privacy: .public)")
        FileLogger.shared.log(level: .debug, category: category, message: message, context: context.description)
    }

    /// Log at info level with optional context
    func info(_ message: String, context: Log.Context = Log.Context()) {
        let fullMessage = "\(message)\(context.description)"
        self.log(level: .info, "\(fullMessage, privacy: .public)")
        FileLogger.shared.log(level: .info, category: category, message: message, context: context.description)
    }

    /// Log at notice level with optional context (default level)
    func notice(_ message: String, context: Log.Context = Log.Context()) {
        let fullMessage = "\(message)\(context.description)"
        self.log(level: .default, "\(fullMessage, privacy: .public)")
        FileLogger.shared.log(level: .notice, category: category, message: message, context: context.description)
    }

    /// Log at warning level with optional context
    func warning(_ message: String, context: Log.Context = Log.Context()) {
        let fullMessage = "\(message)\(context.description)"
        self.log(level: .error, "\(fullMessage, privacy: .public)")
        FileLogger.shared.log(level: .warning, category: category, message: message, context: context.description)
    }

    /// Log at error level with optional context
    func error(_ message: String, context: Log.Context = Log.Context()) {
        let fullMessage = "\(message)\(context.description)"
        self.log(level: .error, "\(fullMessage, privacy: .public)")
        FileLogger.shared.log(level: .error, category: category, message: message, context: context.description)
    }

    /// Log at fault level with optional context (critical errors)
    func fault(_ message: String, context: Log.Context = Log.Context()) {
        let fullMessage = "\(message)\(context.description)"
        self.log(level: .fault, "\(fullMessage, privacy: .public)")
        FileLogger.shared.log(level: .fault, category: category, message: message, context: context.description)
    }

    // MARK: - Convenience Methods

    /// Log an API request
    func request(_ method: String, path: String, context: Log.Context = Log.Context()) {
        var ctx = context
        ctx.add("method", method)
        ctx.add("path", path)
        self.debug("API request", context: ctx)
    }

    /// Log an API response
    func response(_ method: String, path: String, statusCode: Int, duration: TimeInterval, context: Log.Context = Log.Context()) {
        var ctx = context
        ctx.add("method", method)
        ctx.add("path", path)
        ctx.add("status", statusCode)
        ctx.add(duration: duration)

        if statusCode >= 500 {
            self.error("API response", context: ctx)
        } else if statusCode >= 400 {
            self.warning("API response", context: ctx)
        } else {
            self.debug("API response", context: ctx)
        }
    }

    /// Log an error with automatic context extraction
    func error(_ message: String, error: Error, context: Log.Context = Log.Context()) {
        var ctx = context
        ctx.add(error: error)
        self.error("\(message)", context: ctx)
    }

    /// Log at debug level with error context
    func debug(_ message: String, error: Error, context: Log.Context = Log.Context()) {
        var ctx = context
        ctx.add(error: error)
        self.debug("\(message)", context: ctx)
    }

    /// Log at warning level with error context
    func warning(_ message: String, error: Error, context: Log.Context = Log.Context()) {
        var ctx = context
        ctx.add(error: error)
        self.warning("\(message)", context: ctx)
    }

    /// Log operation timing
    func timed<T>(_ operation: String, context: Log.Context = Log.Context(), block: () async throws -> T) async rethrows -> T {
        let start = Date()
        let result = try await block()
        let duration = Date().timeIntervalSince(start)

        var ctx = context
        ctx.add("operation", operation)
        ctx.add(duration: duration)
        self.debug("Operation completed", context: ctx)

        return result
    }
}

// MARK: - Context Builder DSL

extension Log.Context {
    /// Create context with inline fields
    static func with(_ builder: (inout Log.Context) -> Void) -> Log.Context {
        var context = Log.Context()
        builder(&context)
        return context
    }
}
