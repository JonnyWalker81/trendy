//
//  DeviceInfoCollector.swift
//  trendy
//
//  Collects comprehensive device and app information for bug reports.
//  Designed to gather all relevant debugging context while respecting privacy.
//

import Foundation
import UIKit
import Network
import CoreLocation
import HealthKit
import EventKit
import UserNotifications

/// Collects device, app, and runtime information for bug reports.
final class DeviceInfoCollector {

    // MARK: - Singleton

    static let shared = DeviceInfoCollector()

    private let networkMonitor = NWPathMonitor()
    private var currentNetworkStatus: NWPath?

    private init() {
        // Start network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.currentNetworkStatus = path
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Public API

    /// Collect all device info as a formatted string for bug reports
    func collectBugReportHeader() async -> String {
        var sections: [String] = []

        sections.append(generateHeaderLine())
        sections.append(collectDeviceInfo())
        sections.append(collectAppInfo())
        sections.append(collectRuntimeInfo())
        sections.append(await collectUserStatus())
        sections.append(collectAppState())
        sections.append(await collectPermissions())
        sections.append(collectLogSummary())
        sections.append(generateFooterLine())

        return sections.joined(separator: "\n\n")
    }

    /// Collect info as a dictionary (for JSON export if needed)
    func collectAsDict() async -> [String: Any] {
        var info: [String: Any] = [:]

        info["device"] = collectDeviceDict()
        info["app"] = collectAppDict()
        info["runtime"] = collectRuntimeDict()
        info["permissions"] = await collectPermissionsDict()

        return info
    }

    // MARK: - Header/Footer

    private func generateHeaderLine() -> String {
        let reportId = UUID().uuidString.prefix(8)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        return """
        ════════════════════════════════════════════════════════════
        TRENDY BUG REPORT
        ════════════════════════════════════════════════════════════
        Generated: \(timestamp)
        Report ID: \(reportId)
        """
    }

    private func generateFooterLine() -> String {
        """
        ════════════════════════════════════════════════════════════
        END OF REPORT HEADER — LOG ENTRIES FOLLOW
        ════════════════════════════════════════════════════════════
        """
    }

    // MARK: - Device Information

    private func collectDeviceInfo() -> String {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo

        // Get detailed model info
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }

        let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824

        return """
        ┌─ DEVICE INFORMATION ─────────────────────────────────────
        │ Device Name:      \(device.name)
        │ Model:            \(device.model) (\(modelCode))
        │ iOS Version:      \(device.systemName) \(device.systemVersion)
        │ Processor Cores:  \(processInfo.activeProcessorCount) active / \(processInfo.processorCount) total
        │ Physical Memory:  \(String(format: "%.1f", memoryGB)) GB
        └──────────────────────────────────────────────────────────
        """
    }

    private func collectDeviceDict() -> [String: Any] {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo

        return [
            "name": device.name,
            "model": device.model,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "processorCount": processInfo.processorCount,
            "activeProcessorCount": processInfo.activeProcessorCount,
            "physicalMemory": processInfo.physicalMemory
        ]
    }

    // MARK: - App Information

    private func collectAppInfo() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let bundleId = bundle.bundleIdentifier ?? "Unknown"
        let environment = AppEnvironment.current

        // Read API base URL from Info.plist (set via xcconfig)
        let apiBaseURL = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "Not configured"

        return """
        ┌─ APP INFORMATION ────────────────────────────────────────
        │ App Version:      \(version) (Build \(build))
        │ Bundle ID:        \(bundleId)
        │ Environment:      \(environment.displayName)
        │ API Base URL:     \(maskUrl(apiBaseURL))
        └──────────────────────────────────────────────────────────
        """
    }

    private func collectAppDict() -> [String: Any] {
        let bundle = Bundle.main
        return [
            "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            "bundleId": bundle.bundleIdentifier ?? "Unknown",
            "environment": AppEnvironment.current.rawValue
        ]
    }

    // MARK: - Runtime Information

    private func collectRuntimeInfo() -> String {
        // Memory
        let memoryUsage = getMemoryUsage()
        let memoryString = memoryUsage.map { "\(String(format: "%.1f", Double($0) / 1_048_576)) MB" } ?? "Unknown"

        // Disk
        let diskInfo = getDiskSpace()
        let diskUsed = diskInfo.used.map { formatBytes($0) } ?? "Unknown"
        let diskFree = diskInfo.free.map { formatBytes($0) } ?? "Unknown"
        let diskTotal = diskInfo.total.map { formatBytes($0) } ?? "Unknown"

        // Network
        let networkStatus = getNetworkStatus()

        // Battery
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        let batteryString = batteryLevel >= 0 ? "\(Int(batteryLevel * 100))% (\(batteryStateString(batteryState)))" : "Unknown"
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled ? "Yes" : "No"

        // Thermal state
        let thermalState = ProcessInfo.processInfo.thermalState
        let thermalString = thermalStateString(thermalState)

        return """
        ┌─ RUNTIME STATUS ─────────────────────────────────────────
        │ Memory Used:      \(memoryString)
        │ Disk Used:        \(diskUsed) / \(diskTotal) (\(diskFree) free)
        │ Network:          \(networkStatus)
        │ Battery:          \(batteryString)
        │ Low Power Mode:   \(lowPowerMode)
        │ Thermal State:    \(thermalString)
        └──────────────────────────────────────────────────────────
        """
    }

    private func collectRuntimeDict() -> [String: Any] {
        let diskInfo = getDiskSpace()
        UIDevice.current.isBatteryMonitoringEnabled = true

        return [
            "memoryUsed": getMemoryUsage() ?? 0,
            "diskUsed": diskInfo.used ?? 0,
            "diskFree": diskInfo.free ?? 0,
            "diskTotal": diskInfo.total ?? 0,
            "batteryLevel": UIDevice.current.batteryLevel,
            "batteryState": batteryStateString(UIDevice.current.batteryState),
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": thermalStateString(ProcessInfo.processInfo.thermalState)
        ]
    }

    // MARK: - User Status

    private func collectUserStatus() async -> String {
        let locale = Locale.current
        let timezone = TimeZone.current

        // Get user ID if logged in
        var userIdString = "Not logged in"
        // Note: Would need SupabaseService injected to get actual user ID

        // UI preferences
        let darkMode = UITraitCollection.current.userInterfaceStyle == .dark ? "Dark" : "Light"
        let textSize = UIApplication.shared.preferredContentSizeCategory.rawValue

        return """
        ┌─ USER CONTEXT ───────────────────────────────────────────
        │ Locale:           \(locale.identifier)
        │ Language:         \(Locale.preferredLanguages.first ?? "Unknown")
        │ Timezone:         \(timezone.identifier) (UTC\(formatTimezoneOffset(timezone)))
        │ Appearance:       \(darkMode) Mode
        │ Text Size:        \(textSize)
        └──────────────────────────────────────────────────────────
        """
    }

    // MARK: - App State

    private func collectAppState() -> String {
        let defaults = UserDefaults.standard
        let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"

        let onboardingComplete = defaults.bool(forKey: "onboarding_complete") ? "Yes" : "No"
        let syncCursor = defaults.integer(forKey: cursorKey)

        // App container size
        let containerSize = getAppContainerSize()
        let containerString = containerSize.map { formatBytes($0) } ?? "Unknown"

        return """
        ┌─ APP STATE ──────────────────────────────────────────────
        │ Onboarding:       \(onboardingComplete)
        │ Sync Cursor:      \(syncCursor)
        │ App Storage:      \(containerString)
        └──────────────────────────────────────────────────────────
        """
    }

    // MARK: - Permissions

    private func collectPermissions() async -> String {
        let location = await getLocationPermission()
        let notifications = await getNotificationPermission()
        let calendar = getCalendarPermission()
        let healthKit = "See HealthKit settings"

        return """
        ┌─ PERMISSIONS ────────────────────────────────────────────
        │ Location:         \(location)
        │ Notifications:    \(notifications)
        │ Calendar:         \(calendar)
        │ HealthKit:        \(healthKit)
        └──────────────────────────────────────────────────────────
        """
    }

    private func collectPermissionsDict() async -> [String: String] {
        return [
            "location": await getLocationPermission(),
            "notifications": await getNotificationPermission(),
            "calendar": getCalendarPermission()
        ]
    }

    // MARK: - Log Summary

    private func collectLogSummary() -> String {
        let files = FileLogger.shared.getLogFiles()
        let totalSize = files.reduce(0) { $0 + $1.size }
        let oldestDate = files.map(\.date).min()
        let newestDate = files.map(\.date).max()

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let oldestString = oldestDate.map { dateFormatter.string(from: $0) } ?? "N/A"
        let newestString = newestDate.map { dateFormatter.string(from: $0) } ?? "N/A"

        return """
        ┌─ LOG INFORMATION ────────────────────────────────────────
        │ Log Files:        \(files.count)
        │ Total Size:       \(formatBytes(totalSize))
        │ Oldest Log:       \(oldestString)
        │ Newest Log:       \(newestString)
        └──────────────────────────────────────────────────────────
        """
    }

    // MARK: - Helper Methods

    private func getMemoryUsage() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : nil
    }

    private func getDiskSpace() -> (used: Int64?, free: Int64?, total: Int64?) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (nil, nil, nil)
        }

        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])

            let free = values.volumeAvailableCapacityForImportantUsage
            let total = values.volumeTotalCapacity.map { Int64($0) }
            let used = (free != nil && total != nil) ? total! - free! : nil

            return (used, free, total)
        } catch {
            return (nil, nil, nil)
        }
    }

    private func getNetworkStatus() -> String {
        guard let path = currentNetworkStatus else { return "Unknown" }

        if path.status != .satisfied {
            return "No Connection"
        }

        var types: [String] = []
        if path.usesInterfaceType(.wifi) { types.append("WiFi") }
        if path.usesInterfaceType(.cellular) { types.append("Cellular") }
        if path.usesInterfaceType(.wiredEthernet) { types.append("Ethernet") }

        var status = types.isEmpty ? "Connected" : types.joined(separator: ", ")

        if path.isExpensive { status += " (Expensive)" }
        if path.isConstrained { status += " (Low Data)" }

        return status
    }

    private func getLocationPermission() async -> String {
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        @unknown default: return "Unknown"
        }
    }

    private func getNotificationPermission() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private func getCalendarPermission() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .fullAccess: return "Full Access"
        case .writeOnly: return "Write Only"
        @unknown default: return "Unknown"
        }
    }

    private func getAppContainerSize() -> Int64? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }

        var totalSize: Int64 = 0
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(
            at: containerURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   values.isDirectory == false,
                   let size = values.fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatTimezoneOffset(_ timezone: TimeZone) -> String {
        let hours = timezone.secondsFromGMT() / 3600
        let minutes = abs(timezone.secondsFromGMT() / 60 % 60)
        let sign = hours >= 0 ? "+" : ""
        return minutes == 0 ? "\(sign)\(hours)" : "\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    private func maskUrl(_ url: String) -> String {
        // Show host only, mask path details
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url
        }
        return url
    }

    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious (Throttling)"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
