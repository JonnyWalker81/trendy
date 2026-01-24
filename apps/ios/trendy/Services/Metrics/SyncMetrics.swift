//
//  SyncMetrics.swift
//  trendy
//
//  Centralized metrics collection for SyncEngine operations using Apple's native
//  telemetry frameworks: OSSignposter for development profiling (Instruments) and
//  MetricKit for production telemetry.
//
//  Usage:
//    let id = SyncMetrics.beginFullSync()
//    defer { SyncMetrics.endFullSync(id) }
//

import Foundation
import os
import MetricKit

/// Centralized metrics collection for SyncEngine operations.
/// Uses both OSSignposter (development) and mxSignpost (production).
///
/// OSSignposter intervals are viewable in Instruments Time Profiler during development.
/// mxSignpost events are captured by MetricKit for production telemetry.
final class SyncMetrics {

    // MARK: - Signpost Names

    /// Constants for signpost names to ensure begin/end names match exactly.
    /// Using constants prevents the common pitfall of mismatched interval names.
    enum SignpostName {
        static let fullSync = "FullSync"
        static let flushMutations = "FlushMutations"
        static let pullChanges = "PullChanges"
        static let bootstrapFetch = "BootstrapFetch"
        static let healthCheck = "HealthCheck"
    }

    /// Constants for event names.
    enum EventName {
        static let rateLimitHit = "RateLimitHit"
        static let retryAttempt = "RetryAttempt"
        static let circuitBreakerTrip = "CircuitBreakerTrip"
        static let syncSuccess = "SyncSuccess"
        static let syncFailure = "SyncFailure"
    }

    // MARK: - MetricKit Log Handle

    /// Log handle for MetricKit production telemetry.
    /// Category "SyncEngine" groups all sync-related signposts in MetricKit payloads.
    static let logHandle = MXMetricManager.makeLogHandle(category: "SyncEngine")

    // MARK: - OSSignposter for Development

    /// OSSignposter tied to Log.sync for consistent subsystem/category.
    /// Viewable in Instruments Time Profiler.
    private static let signposter = OSSignposter(logger: Log.sync)

    // MARK: - Interval Tracking - FullSync

    /// Active intervals for fullSync operations
    private static var fullSyncIntervals: [UInt64: OSSignposter.IntervalState] = [:]
    private static let fullSyncLock = NSLock()

    /// Begin tracking a full sync operation.
    /// - Returns: OSSignpostID to pass to endFullSync
    static func beginFullSync() -> OSSignpostID {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("FullSync", id: id)

        fullSyncLock.lock()
        fullSyncIntervals[id.rawValue] = interval
        fullSyncLock.unlock()

        // Also record to MetricKit for production telemetry
        mxSignpost(.begin, log: logHandle, name: "FullSync")

        Log.sync.debug("Metrics: began FullSync interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })

        return id
    }

    /// End tracking a full sync operation.
    /// - Parameter id: The OSSignpostID returned from beginFullSync
    static func endFullSync(_ id: OSSignpostID) {
        fullSyncLock.lock()
        let interval = fullSyncIntervals.removeValue(forKey: id.rawValue)
        fullSyncLock.unlock()

        if let interval = interval {
            signposter.endInterval("FullSync", interval)
        }

        // Also record to MetricKit for production telemetry
        mxSignpost(.end, log: logHandle, name: "FullSync")

        Log.sync.debug("Metrics: ended FullSync interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })
    }

    // MARK: - Interval Tracking - FlushMutations

    private static var flushMutationsIntervals: [UInt64: OSSignposter.IntervalState] = [:]
    private static let flushMutationsLock = NSLock()

    /// Begin tracking a flush mutations operation.
    static func beginFlushMutations() -> OSSignpostID {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("FlushMutations", id: id)

        flushMutationsLock.lock()
        flushMutationsIntervals[id.rawValue] = interval
        flushMutationsLock.unlock()

        mxSignpost(.begin, log: logHandle, name: "FlushMutations")

        Log.sync.debug("Metrics: began FlushMutations interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })

        return id
    }

    /// End tracking a flush mutations operation.
    static func endFlushMutations(_ id: OSSignpostID) {
        flushMutationsLock.lock()
        let interval = flushMutationsIntervals.removeValue(forKey: id.rawValue)
        flushMutationsLock.unlock()

        if let interval = interval {
            signposter.endInterval("FlushMutations", interval)
        }

        mxSignpost(.end, log: logHandle, name: "FlushMutations")

        Log.sync.debug("Metrics: ended FlushMutations interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })
    }

    // MARK: - Interval Tracking - PullChanges

    private static var pullChangesIntervals: [UInt64: OSSignposter.IntervalState] = [:]
    private static let pullChangesLock = NSLock()

    /// Begin tracking a pull changes operation.
    static func beginPullChanges() -> OSSignpostID {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("PullChanges", id: id)

        pullChangesLock.lock()
        pullChangesIntervals[id.rawValue] = interval
        pullChangesLock.unlock()

        mxSignpost(.begin, log: logHandle, name: "PullChanges")

        Log.sync.debug("Metrics: began PullChanges interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })

        return id
    }

    /// End tracking a pull changes operation.
    static func endPullChanges(_ id: OSSignpostID) {
        pullChangesLock.lock()
        let interval = pullChangesIntervals.removeValue(forKey: id.rawValue)
        pullChangesLock.unlock()

        if let interval = interval {
            signposter.endInterval("PullChanges", interval)
        }

        mxSignpost(.end, log: logHandle, name: "PullChanges")

        Log.sync.debug("Metrics: ended PullChanges interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })
    }

    // MARK: - Interval Tracking - BootstrapFetch

    private static var bootstrapFetchIntervals: [UInt64: OSSignposter.IntervalState] = [:]
    private static let bootstrapFetchLock = NSLock()

    /// Begin tracking a bootstrap fetch operation.
    static func beginBootstrapFetch() -> OSSignpostID {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("BootstrapFetch", id: id)

        bootstrapFetchLock.lock()
        bootstrapFetchIntervals[id.rawValue] = interval
        bootstrapFetchLock.unlock()

        mxSignpost(.begin, log: logHandle, name: "BootstrapFetch")

        Log.sync.debug("Metrics: began BootstrapFetch interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })

        return id
    }

    /// End tracking a bootstrap fetch operation.
    static func endBootstrapFetch(_ id: OSSignpostID) {
        bootstrapFetchLock.lock()
        let interval = bootstrapFetchIntervals.removeValue(forKey: id.rawValue)
        bootstrapFetchLock.unlock()

        if let interval = interval {
            signposter.endInterval("BootstrapFetch", interval)
        }

        mxSignpost(.end, log: logHandle, name: "BootstrapFetch")

        Log.sync.debug("Metrics: ended BootstrapFetch interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })
    }

    // MARK: - Interval Tracking - HealthCheck

    private static var healthCheckIntervals: [UInt64: OSSignposter.IntervalState] = [:]
    private static let healthCheckLock = NSLock()

    /// Begin tracking a health check operation.
    static func beginHealthCheck() -> OSSignpostID {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("HealthCheck", id: id)

        healthCheckLock.lock()
        healthCheckIntervals[id.rawValue] = interval
        healthCheckLock.unlock()

        mxSignpost(.begin, log: logHandle, name: "HealthCheck")

        Log.sync.debug("Metrics: began HealthCheck interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })

        return id
    }

    /// End tracking a health check operation.
    static func endHealthCheck(_ id: OSSignpostID) {
        healthCheckLock.lock()
        let interval = healthCheckIntervals.removeValue(forKey: id.rawValue)
        healthCheckLock.unlock()

        if let interval = interval {
            signposter.endInterval("HealthCheck", interval)
        }

        mxSignpost(.end, log: logHandle, name: "HealthCheck")

        Log.sync.debug("Metrics: ended HealthCheck interval", context: .with { ctx in
            ctx.add("id", Int(id.rawValue))
        })
    }

    // MARK: - Event Recording

    /// Record a rate limit hit event (429 response received).
    static func recordRateLimitHit() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("RateLimitHit", id: id)
        mxSignpost(.event, log: logHandle, name: "RateLimitHit")

        Log.sync.debug("Metrics: recorded RateLimitHit event")
    }

    /// Record a retry attempt event.
    static func recordRetry() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("RetryAttempt", id: id)
        mxSignpost(.event, log: logHandle, name: "RetryAttempt")

        Log.sync.debug("Metrics: recorded RetryAttempt event")
    }

    /// Record a circuit breaker trip event (too many consecutive rate limits).
    static func recordCircuitBreakerTrip() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("CircuitBreakerTrip", id: id)
        mxSignpost(.event, log: logHandle, name: "CircuitBreakerTrip")

        Log.sync.debug("Metrics: recorded CircuitBreakerTrip event")
    }

    /// Record a sync success event.
    static func recordSyncSuccess() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("SyncSuccess", id: id)
        mxSignpost(.event, log: logHandle, name: "SyncSuccess")

        Log.sync.debug("Metrics: recorded SyncSuccess event")
    }

    /// Record a sync failure event.
    static func recordSyncFailure() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("SyncFailure", id: id)
        mxSignpost(.event, log: logHandle, name: "SyncFailure")

        Log.sync.debug("Metrics: recorded SyncFailure event")
    }
}
