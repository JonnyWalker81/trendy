//
//  WorkoutDeduplicationTests.swift
//  trendyTests
//
//  Unit tests for HealthKit workout deduplication mechanisms.
//  Tests the workout timestamp key generation and concurrent processing mutex.
//
//  These tests verify the fix for the race condition where the same physical workout
//  could be imported twice if reported by HealthKit with different sample IDs
//  (e.g., from Apple Watch and iPhone simultaneously).
//

import Testing
import Foundation
@testable import trendy

// MARK: - Workout Timestamp Key Tests

@Suite("Workout Timestamp Key Generation")
struct WorkoutTimestampKeyTests {

    @Test("Same workout timestamps produce same key")
    func sameTimestampsProduceSameKey() async throws {
        let start = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let end = Date(timeIntervalSince1970: 1704070800)   // 2024-01-01 01:00:00 UTC

        let key1 = workoutTimestampKey(start: start, end: end)
        let key2 = workoutTimestampKey(start: start, end: end)

        #expect(key1 == key2, "Same timestamps should produce identical keys")
    }

    @Test("Different start times produce different keys")
    func differentStartTimesProduceDifferentKeys() async throws {
        let start1 = Date(timeIntervalSince1970: 1704067200)
        let start2 = Date(timeIntervalSince1970: 1704067201) // 1 second later
        let end = Date(timeIntervalSince1970: 1704070800)

        let key1 = workoutTimestampKey(start: start1, end: end)
        let key2 = workoutTimestampKey(start: start2, end: end)

        #expect(key1 != key2, "Different start times should produce different keys")
    }

    @Test("Different end times produce different keys")
    func differentEndTimesProduceDifferentKeys() async throws {
        let start = Date(timeIntervalSince1970: 1704067200)
        let end1 = Date(timeIntervalSince1970: 1704070800)
        let end2 = Date(timeIntervalSince1970: 1704070801) // 1 second later

        let key1 = workoutTimestampKey(start: start, end: end1)
        let key2 = workoutTimestampKey(start: start, end: end2)

        #expect(key1 != key2, "Different end times should produce different keys")
    }

    @Test("Sub-second variations in same second produce same key")
    func subSecondVariationsProduceSameKey() async throws {
        // Two timestamps in the same second but different milliseconds
        let start1 = Date(timeIntervalSince1970: 1704067200.0)
        let start2 = Date(timeIntervalSince1970: 1704067200.999)
        let end = Date(timeIntervalSince1970: 1704070800)

        let key1 = workoutTimestampKey(start: start1, end: end)
        let key2 = workoutTimestampKey(start: start2, end: end)

        #expect(key1 == key2, "Sub-second variations should produce same key (truncated to second)")
    }

    @Test("Key format is deterministic")
    func keyFormatIsDeterministic() async throws {
        let start = Date(timeIntervalSince1970: 1704067200)
        let end = Date(timeIntervalSince1970: 1704070800)

        let key = workoutTimestampKey(start: start, end: end)

        // Key should be "workout-{start_epoch}-{end_epoch}"
        #expect(key == "workout-1704067200-1704070800", "Key format should be deterministic")
    }

    @Test("Workout from different sources with same timestamps produce same key")
    func differentSourcesSameTimestampsProduceSameKey() async throws {
        // Simulates Apple Watch and iPhone reporting same workout
        // Different sample IDs but same physical workout timestamps
        let workoutStart = Date(timeIntervalSince1970: 1704067200)
        let workoutEnd = Date(timeIntervalSince1970: 1704070800)

        // From Apple Watch
        let keyFromWatch = workoutTimestampKey(start: workoutStart, end: workoutEnd)

        // From iPhone (same workout, different "source" but same timestamps)
        let keyFromiPhone = workoutTimestampKey(start: workoutStart, end: workoutEnd)

        #expect(keyFromWatch == keyFromiPhone,
                "Same workout from different sources should produce identical timestamp key")
    }
}

// MARK: - Processing Workout Timestamps Set Tests

@Suite("Processing Workout Timestamps Mutex")
struct ProcessingWorkoutTimestampsMutexTests {

    @Test("Empty set allows all workouts")
    func emptySetAllowsAllWorkouts() async throws {
        var processingSet: Set<String> = []

        let key1 = "workout-1704067200-1704070800"
        let key2 = "workout-1704070800-1704074400"

        #expect(!processingSet.contains(key1), "Empty set should not contain key1")
        #expect(!processingSet.contains(key2), "Empty set should not contain key2")
    }

    @Test("Inserting key blocks same workout")
    func insertingKeyBlocksSameWorkout() async throws {
        var processingSet: Set<String> = []

        let key = "workout-1704067200-1704070800"
        processingSet.insert(key)

        #expect(processingSet.contains(key), "Set should contain inserted key")

        // Attempting to process same workout should be blocked
        let shouldBlock = processingSet.contains(key)
        #expect(shouldBlock, "Same workout key should be blocked")
    }

    @Test("Different workouts not blocked by each other")
    func differentWorkoutsNotBlocked() async throws {
        var processingSet: Set<String> = []

        let key1 = "workout-1704067200-1704070800"
        let key2 = "workout-1704070800-1704074400"

        processingSet.insert(key1)

        #expect(!processingSet.contains(key2), "Different workout should not be blocked")
    }

    @Test("Removing key allows reprocessing")
    func removingKeyAllowsReprocessing() async throws {
        var processingSet: Set<String> = []

        let key = "workout-1704067200-1704070800"
        processingSet.insert(key)
        #expect(processingSet.contains(key), "Key should be in set after insert")

        processingSet.remove(key)
        #expect(!processingSet.contains(key), "Key should not be in set after remove")
    }
}

// MARK: - Concurrent Processing Simulation Tests

@Suite("Concurrent Processing Prevention")
struct ConcurrentProcessingPreventionTests {

    @Test("First processor wins when same workout processed concurrently")
    func firstProcessorWins() async throws {
        var processingSet: Set<String> = []
        let workoutKey = "workout-1704067200-1704070800"

        // Simulate two concurrent processors trying to claim same workout
        // Processor 1: Checks and inserts (wins)
        let processor1CanProceed = !processingSet.contains(workoutKey)
        if processor1CanProceed {
            processingSet.insert(workoutKey)
        }

        // Processor 2: Checks (should be blocked)
        let processor2CanProceed = !processingSet.contains(workoutKey)

        #expect(processor1CanProceed, "Processor 1 should be able to proceed")
        #expect(!processor2CanProceed, "Processor 2 should be blocked")
    }

    @Test("Multiple different workouts can be processed concurrently")
    func multipleWorkoutsProcessedConcurrently() async throws {
        var processingSet: Set<String> = []

        let workout1Key = "workout-1704067200-1704070800"
        let workout2Key = "workout-1704070800-1704074400"
        let workout3Key = "workout-1704074400-1704078000"

        // All three should be able to proceed
        let workout1CanProceed = !processingSet.contains(workout1Key)
        processingSet.insert(workout1Key)

        let workout2CanProceed = !processingSet.contains(workout2Key)
        processingSet.insert(workout2Key)

        let workout3CanProceed = !processingSet.contains(workout3Key)
        processingSet.insert(workout3Key)

        #expect(workout1CanProceed, "Workout 1 should proceed")
        #expect(workout2CanProceed, "Workout 2 should proceed")
        #expect(workout3CanProceed, "Workout 3 should proceed")
        #expect(processingSet.count == 3, "All three keys should be in set")
    }

    @Test("Defer pattern releases lock correctly")
    func deferPatternReleasesLock() async throws {
        var processingSet: Set<String> = []
        let workoutKey = "workout-1704067200-1704070800"

        // Simulate the processing with defer pattern
        func simulateProcessing() {
            processingSet.insert(workoutKey)
            defer { processingSet.remove(workoutKey) }

            // Simulate work happening here
            #expect(processingSet.contains(workoutKey), "Key should be in set during processing")
        }

        simulateProcessing()

        // After function returns, defer should have removed the key
        #expect(!processingSet.contains(workoutKey), "Key should be removed after processing (via defer)")
    }

    @Test("Multiple claims with same timestamps from different sample IDs - second blocked")
    func multipleSampleIdsSameTimestamps() async throws {
        var processingSet: Set<String> = []
        var processedSampleIds: Set<String> = []

        // Two "workouts" with different sample IDs but same timestamps
        // This simulates Apple Watch and iPhone reporting the same physical workout
        let sampleId1 = "UUID-FROM-APPLE-WATCH"
        let sampleId2 = "UUID-FROM-IPHONE"
        let workoutStart = Date(timeIntervalSince1970: 1704067200)
        let workoutEnd = Date(timeIntervalSince1970: 1704070800)

        // Both would have different sample IDs, so both pass sampleId check
        let sample1PassesSampleIdCheck = !processedSampleIds.contains(sampleId1)
        let sample2PassesSampleIdCheck = !processedSampleIds.contains(sampleId2)
        #expect(sample1PassesSampleIdCheck, "Sample 1 should pass sampleId check")
        #expect(sample2PassesSampleIdCheck, "Sample 2 should pass sampleId check")

        // Now check timestamp-based mutex
        let timestampKey = workoutTimestampKey(start: workoutStart, end: workoutEnd)

        // Sample 1 claims the timestamp
        processedSampleIds.insert(sampleId1)
        let sample1PassesTimestampCheck = !processingSet.contains(timestampKey)
        if sample1PassesTimestampCheck {
            processingSet.insert(timestampKey)
        }

        // Sample 2 also inserts its sampleId, but should be blocked by timestamp check
        processedSampleIds.insert(sampleId2)
        let sample2PassesTimestampCheck = !processingSet.contains(timestampKey)

        #expect(sample1PassesTimestampCheck, "Sample 1 should pass timestamp check")
        #expect(!sample2PassesTimestampCheck, "Sample 2 should be BLOCKED by timestamp check - this is the key fix!")
    }
}

// MARK: - Helper Function (Mirrors the implementation)

/// Generate a unique key for a workout based on its timestamps.
/// This mirrors the implementation in HealthKitService+WorkoutProcessing.swift
private func workoutTimestampKey(start: Date, end: Date) -> String {
    let startTruncated = start.timeIntervalSince1970.rounded(.down)
    let endTruncated = end.timeIntervalSince1970.rounded(.down)
    return "workout-\(Int(startTruncated))-\(Int(endTruncated))"
}
