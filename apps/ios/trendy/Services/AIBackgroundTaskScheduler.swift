//
//  AIBackgroundTaskScheduler.swift
//  trendy
//
//  Schedules background tasks for AI insight generation
//

import Foundation
import BackgroundTasks
import UIKit

/// Manages background task scheduling for AI insight generation
final class AIBackgroundTaskScheduler {
    // MARK: - Task Identifiers

    static let dailyBriefingIdentifier = "com.trendy.ai.dailyBriefing"
    static let weeklyReflectionIdentifier = "com.trendy.ai.weeklyReflection"

    // MARK: - Singleton

    static let shared = AIBackgroundTaskScheduler()

    // MARK: - Dependencies

    private var insightsViewModel: InsightsViewModel?
    private var eventStore: EventStore?
    private var foundationModelService: FoundationModelService?

    // MARK: - Configuration

    /// Configure with dependencies
    @MainActor
    func configure(
        insightsViewModel: InsightsViewModel,
        eventStore: EventStore,
        foundationModelService: FoundationModelService
    ) {
        self.insightsViewModel = insightsViewModel
        self.eventStore = eventStore
        self.foundationModelService = foundationModelService
    }

    // MARK: - Task Registration

    /// Register background tasks with the system
    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailyBriefingIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleDailyBriefing(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.weeklyReflectionIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleWeeklyReflection(task: task as! BGProcessingTask)
        }

        Log.api.info("AI background tasks registered")
    }

    // MARK: - Task Scheduling

    /// Schedule the daily briefing task for 7:00 AM
    func scheduleDailyBriefing() {
        let request = BGProcessingTaskRequest(identifier: Self.dailyBriefingIdentifier)
        request.earliestBeginDate = nextOccurrence(hour: 7, minute: 0)
        request.requiresNetworkConnectivity = false  // On-device AI
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.api.info("Daily briefing scheduled", context: .with { ctx in
                ctx.add("next_run", request.earliestBeginDate?.description ?? "unknown")
            })
        } catch {
            Log.api.error("Failed to schedule daily briefing", error: error)
        }
    }

    /// Schedule the weekly reflection task for Sunday 7:00 PM
    func scheduleWeeklyReflection() {
        let request = BGProcessingTaskRequest(identifier: Self.weeklyReflectionIdentifier)
        request.earliestBeginDate = nextSunday(hour: 19, minute: 0)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.api.info("Weekly reflection scheduled", context: .with { ctx in
                ctx.add("next_run", request.earliestBeginDate?.description ?? "unknown")
            })
        } catch {
            Log.api.error("Failed to schedule weekly reflection", error: error)
        }
    }

    /// Schedule all AI background tasks
    func scheduleAllTasks() {
        scheduleDailyBriefing()
        scheduleWeeklyReflection()
    }

    /// Cancel all scheduled AI tasks
    func cancelAllTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.dailyBriefingIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.weeklyReflectionIdentifier)
        Log.api.info("All AI background tasks cancelled")
    }

    // MARK: - Task Handlers

    private func handleDailyBriefing(task: BGProcessingTask) {
        Log.api.info("Handling daily briefing background task")

        // Schedule the next occurrence
        scheduleDailyBriefing()

        // Set up expiration handler
        task.expirationHandler = {
            Log.api.warning("Daily briefing task expired before completion")
            task.setTaskCompleted(success: false)
        }

        // Generate briefing
        Task { @MainActor in
            guard let viewModel = self.insightsViewModel else {
                Log.api.warning("InsightsViewModel not configured for background task")
                task.setTaskCompleted(success: false)
                return
            }

            await viewModel.generateDailyBriefing()

            // Send notification if briefing was generated
            if viewModel.dailyBriefing != nil {
                await sendDailyBriefingNotification(viewModel.dailyBriefing!)
            }

            task.setTaskCompleted(success: viewModel.dailyBriefing != nil)
        }
    }

    private func handleWeeklyReflection(task: BGProcessingTask) {
        Log.api.info("Handling weekly reflection background task")

        // Schedule the next occurrence
        scheduleWeeklyReflection()

        // Set up expiration handler
        task.expirationHandler = {
            Log.api.warning("Weekly reflection task expired before completion")
            task.setTaskCompleted(success: false)
        }

        // Generate reflection
        Task { @MainActor in
            guard let viewModel = self.insightsViewModel else {
                Log.api.warning("InsightsViewModel not configured for background task")
                task.setTaskCompleted(success: false)
                return
            }

            await viewModel.generateWeeklyReflection()

            // Send notification if reflection was generated
            if viewModel.weeklyReflection != nil {
                await sendWeeklyReflectionNotification(viewModel.weeklyReflection!)
            }

            task.setTaskCompleted(success: viewModel.weeklyReflection != nil)
        }
    }

    // MARK: - Notifications

    @MainActor
    private func sendDailyBriefingNotification(_ briefing: DailyBriefing) async {
        let content = UNMutableNotificationContent()
        content.title = "Your Daily Briefing"
        content.body = briefing.greeting
        content.sound = .default
        content.categoryIdentifier = "AI_BRIEFING"

        let request = UNNotificationRequest(
            identifier: "daily-briefing-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Log.api.info("Daily briefing notification sent")
        } catch {
            Log.api.error("Failed to send daily briefing notification", error: error)
        }
    }

    @MainActor
    private func sendWeeklyReflectionNotification(_ reflection: WeeklyReflection) async {
        let content = UNMutableNotificationContent()
        content.title = "Your Week in Review"
        content.body = reflection.summary
        content.sound = .default
        content.categoryIdentifier = "AI_REFLECTION"

        let request = UNNotificationRequest(
            identifier: "weekly-reflection-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Log.api.info("Weekly reflection notification sent")
        } catch {
            Log.api.error("Failed to send weekly reflection notification", error: error)
        }
    }

    // MARK: - Date Helpers

    /// Get the next occurrence of a specific time
    private func nextOccurrence(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let scheduled = calendar.date(from: components) else {
            return now.addingTimeInterval(86400)  // Fallback to 24 hours
        }

        // If the time has passed today, schedule for tomorrow
        if scheduled <= now {
            return calendar.date(byAdding: .day, value: 1, to: scheduled) ?? scheduled
        }

        return scheduled
    }

    /// Get the next Sunday at a specific time
    private func nextSunday(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()

        // Find next Sunday
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 1  // Sunday
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let nextSunday = calendar.date(from: components) else {
            return now.addingTimeInterval(7 * 86400)  // Fallback to 7 days
        }

        // If this Sunday has passed, get next week's Sunday
        if nextSunday <= now {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: nextSunday) ?? nextSunday
        }

        return nextSunday
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension AIBackgroundTaskScheduler {
    /// Simulate a daily briefing task for testing
    @MainActor
    func simulateDailyBriefing() async {
        guard let viewModel = insightsViewModel else {
            Log.api.warning("InsightsViewModel not configured")
            return
        }

        await viewModel.generateDailyBriefing()

        if let briefing = viewModel.dailyBriefing {
            await sendDailyBriefingNotification(briefing)
        }
    }

    /// Simulate a weekly reflection task for testing
    @MainActor
    func simulateWeeklyReflection() async {
        guard let viewModel = insightsViewModel else {
            Log.api.warning("InsightsViewModel not configured")
            return
        }

        await viewModel.generateWeeklyReflection()

        if let reflection = viewModel.weeklyReflection {
            await sendWeeklyReflectionNotification(reflection)
        }
    }
}
#endif
