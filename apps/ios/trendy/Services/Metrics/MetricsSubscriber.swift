//
//  MetricsSubscriber.swift
//  trendy
//
//  Receives daily MetricKit payloads containing aggregated telemetry data.
//  MetricKit collects performance data in production and delivers payloads
//  approximately once per day.
//
//  IMPORTANT: MetricKit only works on physical devices, not Simulator.
//  Use Xcode > Debug > Simulate MetricKit Payloads for testing.
//

import Foundation
import MetricKit

/// Singleton that receives daily MetricKit payloads.
/// Initialize early in app lifecycle (e.g., App.init) to ensure all metrics are captured.
///
/// MetricKit provides:
/// - Custom signpost metrics (from mxSignpost calls)
/// - App launch metrics
/// - Responsiveness metrics (hang time)
/// - Crash diagnostics
///
/// Note: Payloads arrive "at most once per day" after approximately 24 hours
/// of data collection on physical devices.
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {

    // MARK: - Singleton

    /// Shared singleton instance.
    /// Access this early in app lifecycle to register with MXMetricManager.
    static let shared = MetricsSubscriber()

    // MARK: - Initialization

    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
        Log.sync.info("MetricsSubscriber registered with MXMetricManager")
    }

    deinit {
        MXMetricManager.shared.remove(self)
        Log.sync.info("MetricsSubscriber removed from MXMetricManager")
    }

    // MARK: - MXMetricManagerSubscriber

    /// Called when MetricKit delivers new metric payloads.
    /// Payloads contain aggregated 24-hour data.
    func didReceive(_ payloads: [MXMetricPayload]) {
        Log.sync.info("Received MetricKit payloads", context: .with { ctx in
            ctx.add("count", payloads.count)
        })

        for payload in payloads {
            // Skip mixed-version payloads to avoid polluted data
            // This happens when user updates the app mid-collection period
            if payload.includesMultipleApplicationVersions {
                Log.sync.debug("Skipping mixed-version MetricKit payload")
                continue
            }

            processPayload(payload)
        }
    }

    /// Called when MetricKit delivers diagnostic payloads.
    /// Contains crash reports and other diagnostic data.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Log.sync.info("Received diagnostic payloads", context: .with { ctx in
            ctx.add("count", payloads.count)
        })

        for payload in payloads {
            processDiagnosticPayload(payload)
        }
    }

    // MARK: - Payload Processing

    /// Process a single metric payload.
    private func processPayload(_ payload: MXMetricPayload) {
        let timeRange = payload.timeStampEnd.timeIntervalSince(payload.timeStampBegin)
        let durationHours = Int(timeRange / 3600)

        // Extract app version from metadata
        let appVersion = payload.metaData?.applicationBuildVersion ?? "unknown"

        Log.sync.info("Processing MetricKit payload", context: .with { ctx in
            ctx.add("duration_hours", durationHours)
            ctx.add("app_version", appVersion)
        })

        // Process custom signpost metrics (from SyncMetrics calls)
        processSignpostMetrics(payload.signpostMetrics)

        // Process app launch metrics
        if let launchMetrics = payload.applicationLaunchMetrics {
            processLaunchMetrics(launchMetrics)
        }

        // Process responsiveness metrics (hangs)
        if let responsivenessMetrics = payload.applicationResponsivenessMetrics {
            processResponsivenessMetrics(responsivenessMetrics)
        }
    }

    /// Process custom signpost metrics from SyncMetrics.
    private func processSignpostMetrics(_ signpostMetrics: [MXSignpostMetric]?) {
        guard let signpostMetrics = signpostMetrics else {
            Log.sync.debug("No signpost metrics in payload")
            return
        }

        Log.sync.info("Processing signpost metrics", context: .with { ctx in
            ctx.add("count", signpostMetrics.count)
        })

        for metric in signpostMetrics {
            // Log each signpost metric
            Log.sync.info("Signpost metric", context: .with { ctx in
                ctx.add("category", metric.signpostCategory)
                ctx.add("name", metric.signpostName)
                ctx.add("total_count", Int(metric.totalCount))
            })

            // The metric.signpostIntervalData contains histograms for duration
            // metric.signpostIntervalData?.histogrammedSignpostDuration provides
            // p50, p90, p99 percentile data for interval duration
        }
    }

    /// Process app launch metrics.
    private func processLaunchMetrics(_ metrics: MXAppLaunchMetric) {
        // MXHistogram provides bucketEnumerator for accessing buckets
        // We check if there are any buckets by enumerating
        let hasTimeToFirstDraw = metrics.histogrammedTimeToFirstDraw.bucketEnumerator.nextObject() != nil
        let hasResumeTime = metrics.histogrammedApplicationResumeTime.bucketEnumerator.nextObject() != nil

        Log.sync.info("Launch metrics received", context: .with { ctx in
            ctx.add("has_time_to_first_draw", hasTimeToFirstDraw)
            ctx.add("has_application_resume", hasResumeTime)
        })
    }

    /// Process responsiveness metrics (hang detection).
    private func processResponsivenessMetrics(_ metrics: MXAppResponsivenessMetric) {
        let hasHangTime = metrics.histogrammedApplicationHangTime.bucketEnumerator.nextObject() != nil

        Log.sync.info("Responsiveness metrics received", context: .with { ctx in
            ctx.add("has_hang_time", hasHangTime)
        })
    }

    /// Process a diagnostic payload (crash reports, etc).
    private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        let crashCount = payload.crashDiagnostics?.count ?? 0
        let hangCount = payload.hangDiagnostics?.count ?? 0
        let cpuExceptionCount = payload.cpuExceptionDiagnostics?.count ?? 0
        let diskWriteCount = payload.diskWriteExceptionDiagnostics?.count ?? 0

        Log.sync.info("Diagnostic payload", context: .with { ctx in
            ctx.add("crashes", crashCount)
            ctx.add("hangs", hangCount)
            ctx.add("cpu_exceptions", cpuExceptionCount)
            ctx.add("disk_write_exceptions", diskWriteCount)
        })

        // Log crash diagnostics if present
        if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
            for crash in crashes {
                Log.sync.warning("Crash diagnostic received", context: .with { ctx in
                    // exceptionType and signal are NSNumber, use intValue
                    ctx.add("exception_type", crash.exceptionType?.intValue ?? -1)
                    ctx.add("signal", crash.signal?.intValue ?? -1)
                })
            }
        }
    }
}
