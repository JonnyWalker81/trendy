//
//  AIInsightCache.swift
//  trendy
//
//  Caches AI-generated insights to avoid redundant regeneration
//

import Foundation

/// Caches AI-generated insights with configurable expiration
actor AIInsightCache {
    // MARK: - Cache Entry

    private struct CacheEntry<T: Codable>: Codable {
        let value: T
        let timestamp: Date
        let expiresAt: Date

        var isExpired: Bool {
            Date() > expiresAt
        }
    }

    // MARK: - Storage Keys

    private enum StorageKey {
        static let dailyBriefing = "ai_cache_daily_briefing"
        static let weeklyReflection = "ai_cache_weekly_reflection"
        static let patternExplanations = "ai_cache_pattern_explanations"
        static let eventTypeAnalyses = "ai_cache_event_type_analyses"
    }

    // MARK: - Expiration Durations

    private enum ExpirationDuration {
        static let dailyBriefing: TimeInterval = 6 * 60 * 60  // 6 hours
        static let weeklyReflection: TimeInterval = 7 * 24 * 60 * 60  // 1 week
        static let patternExplanation: TimeInterval = 24 * 60 * 60  // 24 hours
        static let eventTypeAnalysis: TimeInterval = 12 * 60 * 60  // 12 hours
    }

    // MARK: - Singleton

    static let shared = AIInsightCache()

    // MARK: - In-Memory Cache

    private var dailyBriefingCache: CacheEntry<DailyBriefing>?
    private var weeklyReflectionCache: CacheEntry<WeeklyReflection>?
    private var patternExplanationsCache: [String: CacheEntry<PatternExplanation>] = [:]
    private var eventTypeAnalysesCache: [String: CacheEntry<EventTypeAnalysis>] = [:]

    // MARK: - UserDefaults for Persistence

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    private init() {
        Task {
            await loadFromDisk()
        }
    }

    // MARK: - Daily Briefing

    func getDailyBriefing() -> DailyBriefing? {
        guard let entry = dailyBriefingCache, !entry.isExpired else {
            dailyBriefingCache = nil
            return nil
        }
        return entry.value
    }

    func setDailyBriefing(_ briefing: DailyBriefing) {
        let entry = CacheEntry(
            value: briefing,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(ExpirationDuration.dailyBriefing)
        )
        dailyBriefingCache = entry
        saveToDisk()
    }

    func invalidateDailyBriefing() {
        dailyBriefingCache = nil
        defaults.removeObject(forKey: StorageKey.dailyBriefing)
    }

    // MARK: - Weekly Reflection

    func getWeeklyReflection() -> WeeklyReflection? {
        guard let entry = weeklyReflectionCache, !entry.isExpired else {
            weeklyReflectionCache = nil
            return nil
        }
        return entry.value
    }

    func setWeeklyReflection(_ reflection: WeeklyReflection) {
        let entry = CacheEntry(
            value: reflection,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(ExpirationDuration.weeklyReflection)
        )
        weeklyReflectionCache = entry
        saveToDisk()
    }

    func invalidateWeeklyReflection() {
        weeklyReflectionCache = nil
        defaults.removeObject(forKey: StorageKey.weeklyReflection)
    }

    // MARK: - Pattern Explanations

    func getPatternExplanation(for insightId: String) -> PatternExplanation? {
        guard let entry = patternExplanationsCache[insightId], !entry.isExpired else {
            patternExplanationsCache.removeValue(forKey: insightId)
            return nil
        }
        return entry.value
    }

    func setPatternExplanation(_ explanation: PatternExplanation, for insightId: String) {
        let entry = CacheEntry(
            value: explanation,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(ExpirationDuration.patternExplanation)
        )
        patternExplanationsCache[insightId] = entry
        saveToDisk()
    }

    func invalidatePatternExplanation(for insightId: String) {
        patternExplanationsCache.removeValue(forKey: insightId)
        saveToDisk()
    }

    func invalidateAllPatternExplanations() {
        patternExplanationsCache.removeAll()
        defaults.removeObject(forKey: StorageKey.patternExplanations)
    }

    // MARK: - Event Type Analyses

    func getEventTypeAnalysis(for eventTypeName: String) -> EventTypeAnalysis? {
        guard let entry = eventTypeAnalysesCache[eventTypeName], !entry.isExpired else {
            eventTypeAnalysesCache.removeValue(forKey: eventTypeName)
            return nil
        }
        return entry.value
    }

    func setEventTypeAnalysis(_ analysis: EventTypeAnalysis, for eventTypeName: String) {
        let entry = CacheEntry(
            value: analysis,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(ExpirationDuration.eventTypeAnalysis)
        )
        eventTypeAnalysesCache[eventTypeName] = entry
        saveToDisk()
    }

    // MARK: - Cache Management

    /// Clear all cached insights
    func clearAll() {
        dailyBriefingCache = nil
        weeklyReflectionCache = nil
        patternExplanationsCache.removeAll()
        eventTypeAnalysesCache.removeAll()

        defaults.removeObject(forKey: StorageKey.dailyBriefing)
        defaults.removeObject(forKey: StorageKey.weeklyReflection)
        defaults.removeObject(forKey: StorageKey.patternExplanations)
        defaults.removeObject(forKey: StorageKey.eventTypeAnalyses)
    }

    /// Prune expired entries
    func pruneExpired() {
        if let entry = dailyBriefingCache, entry.isExpired {
            dailyBriefingCache = nil
        }

        if let entry = weeklyReflectionCache, entry.isExpired {
            weeklyReflectionCache = nil
        }

        for (key, entry) in patternExplanationsCache where entry.isExpired {
            patternExplanationsCache.removeValue(forKey: key)
        }

        for (key, entry) in eventTypeAnalysesCache where entry.isExpired {
            eventTypeAnalysesCache.removeValue(forKey: key)
        }

        saveToDisk()
    }

    /// Get cache statistics
    func stats() -> CacheStats {
        CacheStats(
            dailyBriefingCached: dailyBriefingCache != nil && !dailyBriefingCache!.isExpired,
            weeklyReflectionCached: weeklyReflectionCache != nil && !weeklyReflectionCache!.isExpired,
            patternExplanationsCount: patternExplanationsCache.filter { !$0.value.isExpired }.count,
            eventTypeAnalysesCount: eventTypeAnalysesCache.filter { !$0.value.isExpired }.count
        )
    }

    // MARK: - Persistence

    private func saveToDisk() {
        // Save daily briefing
        if let entry = dailyBriefingCache,
           let data = try? encoder.encode(entry) {
            defaults.set(data, forKey: StorageKey.dailyBriefing)
        }

        // Save weekly reflection
        if let entry = weeklyReflectionCache,
           let data = try? encoder.encode(entry) {
            defaults.set(data, forKey: StorageKey.weeklyReflection)
        }

        // Save pattern explanations
        if let data = try? encoder.encode(patternExplanationsCache) {
            defaults.set(data, forKey: StorageKey.patternExplanations)
        }

        // Save event type analyses
        if let data = try? encoder.encode(eventTypeAnalysesCache) {
            defaults.set(data, forKey: StorageKey.eventTypeAnalyses)
        }
    }

    private func loadFromDisk() {
        // Load daily briefing
        if let data = defaults.data(forKey: StorageKey.dailyBriefing),
           let entry = try? decoder.decode(CacheEntry<DailyBriefing>.self, from: data),
           !entry.isExpired {
            dailyBriefingCache = entry
        }

        // Load weekly reflection
        if let data = defaults.data(forKey: StorageKey.weeklyReflection),
           let entry = try? decoder.decode(CacheEntry<WeeklyReflection>.self, from: data),
           !entry.isExpired {
            weeklyReflectionCache = entry
        }

        // Load pattern explanations
        if let data = defaults.data(forKey: StorageKey.patternExplanations),
           let entries = try? decoder.decode([String: CacheEntry<PatternExplanation>].self, from: data) {
            patternExplanationsCache = entries.filter { !$0.value.isExpired }
        }

        // Load event type analyses
        if let data = defaults.data(forKey: StorageKey.eventTypeAnalyses),
           let entries = try? decoder.decode([String: CacheEntry<EventTypeAnalysis>].self, from: data) {
            eventTypeAnalysesCache = entries.filter { !$0.value.isExpired }
        }
    }
}

// MARK: - Cache Statistics

struct CacheStats {
    let dailyBriefingCached: Bool
    let weeklyReflectionCached: Bool
    let patternExplanationsCount: Int
    let eventTypeAnalysesCount: Int
}
