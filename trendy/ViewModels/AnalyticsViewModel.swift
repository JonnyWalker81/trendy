//
//  AnalyticsViewModel.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import SwiftUI
import Charts

struct DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct Statistics {
    let totalCount: Int
    let averagePerDay: Double
    let averagePerWeek: Double
    let averagePerMonth: Double
    let averagePerYear: Double
    let trend: Trend
    let lastOccurrence: Date?
    let timeRange: TimeRange
    
    enum Trend {
        case increasing
        case decreasing
        case stable
    }
}

@Observable
@MainActor
class AnalyticsViewModel {
    private(set) var dailyData: [DataPoint] = []
    private(set) var weeklyData: [DataPoint] = []
    private(set) var monthlyData: [DataPoint] = []
    private(set) var statistics: Statistics?
    var isCalculating = false
    
    func calculateFrequency(for eventType: EventType, events: [Event], timeRange: TimeRange = .month) async -> [DataPoint] {
        isCalculating = true
        
        let filteredEvents = events.filter { $0.eventType?.id == eventType.id }
        let dataPoints = await withCheckedContinuation { continuation in
            Task {
                let points = generateDataPoints(from: filteredEvents, timeRange: timeRange)
                continuation.resume(returning: points)
            }
        }
        
        switch timeRange {
        case .week:
            dailyData = dataPoints
        case .month:
            weeklyData = dataPoints
        case .year:
            monthlyData = dataPoints
        }
        
        isCalculating = false
        return dataPoints
    }
    
    func generateStatistics(for eventType: EventType, events: [Event], timeRange: TimeRange) async -> Statistics {
        let filteredEvents = events.filter { $0.eventType?.id == eventType.id }
        
        let totalCount = filteredEvents.count
        let lastOccurrence = filteredEvents.first?.timestamp
        
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate date range
        guard let firstEvent = filteredEvents.last else {
            return Statistics(
                totalCount: 0,
                averagePerDay: 0,
                averagePerWeek: 0,
                averagePerMonth: 0,
                averagePerYear: 0,
                trend: .stable,
                lastOccurrence: nil,
                timeRange: timeRange
            )
        }
        
        // Calculate days from first event to now, inclusive
        let startOfFirstDay = calendar.startOfDay(for: firstEvent.timestamp)
        let startOfToday = calendar.startOfDay(for: now)
        let daysBetween = calendar.dateComponents([.day], from: startOfFirstDay, to: startOfToday).day ?? 0
        let totalDays = daysBetween + 1 // Include both start and end days
        
        let averagePerDay = Double(totalCount) / Double(totalDays)
        let averagePerWeek = averagePerDay * 7.0
        let averagePerMonth = averagePerDay * 30.0
        let averagePerYear = averagePerDay * 365.0
        
        // Calculate trend
        let trend = calculateTrend(events: filteredEvents)
        
        return Statistics(
            totalCount: totalCount,
            averagePerDay: averagePerDay,
            averagePerWeek: averagePerWeek,
            averagePerMonth: averagePerMonth,
            averagePerYear: averagePerYear,
            trend: trend,
            lastOccurrence: lastOccurrence,
            timeRange: timeRange
        )
    }
    
    private func generateDataPoints(from events: [Event], timeRange: TimeRange) -> [DataPoint] {
        let calendar = Calendar.current
        let now = Date()
        var dataPoints: [DataPoint] = []
        
        switch timeRange {
        case .week:
            // Daily data for last 7 days
            for dayOffset in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) {
                    let dayStart = calendar.startOfDay(for: date)
                    let count = events.filter { event in
                        calendar.isDate(event.timestamp, inSameDayAs: dayStart)
                    }.count
                    dataPoints.append(DataPoint(date: dayStart, count: count))
                }
            }
            
        case .month:
            // Weekly data for last 4 weeks
            for weekOffset in 0..<4 {
                if let weekEnd = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                   let weekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekEnd) {
                    let count = events.filter { event in
                        event.timestamp >= weekStart && event.timestamp < weekEnd
                    }.count
                    dataPoints.append(DataPoint(date: weekStart, count: count))
                }
            }
            
        case .year:
            // Monthly data for last 12 months
            for monthOffset in 0..<12 {
                if let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: now) {
                    let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
                    let count = events.filter { event in
                        event.timestamp >= monthStart && event.timestamp < monthEnd
                    }.count
                    dataPoints.append(DataPoint(date: monthStart, count: count))
                }
            }
        }
        
        return dataPoints.reversed()
    }
    
    private func calculateTrend(events: [Event]) -> Statistics.Trend {
        guard events.count >= 2 else { return .stable }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Compare last 2 weeks with previous 2 weeks
        let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now) ?? now
        let fourWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        
        let recentEvents = events.filter { $0.timestamp >= twoWeeksAgo }
        let previousEvents = events.filter { $0.timestamp >= fourWeeksAgo && $0.timestamp < twoWeeksAgo }
        
        // Calculate daily averages for each period
        let recentDailyAvg = Double(recentEvents.count) / 14.0
        let previousDailyAvg = Double(previousEvents.count) / 14.0
        
        // Calculate percentage change
        guard previousDailyAvg > 0 else {
            // If no events in previous period but events in recent period, it's increasing
            return recentDailyAvg > 0 ? .increasing : .stable
        }
        
        let percentageChange = ((recentDailyAvg - previousDailyAvg) / previousDailyAvg) * 100
        
        if percentageChange > 20 {
            return .increasing
        } else if percentageChange < -20 {
            return .decreasing
        } else {
            return .stable
        }
    }
}

enum TimeRange: String {
    case week = "week"
    case month = "month"
    case year = "year"
}