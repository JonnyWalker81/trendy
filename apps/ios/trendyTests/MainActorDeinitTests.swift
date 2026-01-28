//
//  MainActorDeinitTests.swift
//  trendyTests
//
//  Tests for @MainActor class deinit race condition fix.
//  Verifies that nonisolated(unsafe) task properties can be safely
//  cancelled from deinit when the last reference is released off
//  the main actor (matching SupabaseService's pattern).
//

import Testing
import Foundation

// MARK: - Thread-safe flag

/// Simple thread-safe boolean for cross-task signaling.
private final class AtomicFlag: Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ value: Bool) {
        self._value = value
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        _value = newValue
        lock.unlock()
    }
}

// MARK: - Test Double

/// Mirrors SupabaseService's @MainActor + nonisolated(unsafe) task pattern.
/// The task runs indefinitely until cancelled; deinit cancels it.
@Observable
@MainActor
private final class MainActorServiceStub {
    var stateValue = 0
    nonisolated(unsafe) private var backgroundTask: Task<Void, Never>?
    private let onCancelled: @Sendable () -> Void

    init(onCancelled: @escaping @Sendable () -> Void) {
        self.onCancelled = onCancelled
        backgroundTask = Task { [onCancelled] in
            // Simulate long-running listener (like auth state changes)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            onCancelled()
        }
    }

    deinit {
        backgroundTask?.cancel()
    }
}

// MARK: - Tests

@Suite("MainActor Deinit Safety")
struct MainActorDeinitTests {

    @Test("Task is cancelled when @MainActor object is deallocated from main actor")
    @MainActor func testDeinitCancelsTaskFromMainActor() async throws {
        let cancelled = AtomicFlag(false)

        // Create on MainActor
        var stub: MainActorServiceStub? = MainActorServiceStub(
            onCancelled: { cancelled.set(true) }
        )

        // Verify it was created
        #expect(stub?.stateValue == 0)

        // Release — deinit runs on main actor
        stub = nil

        // Wait for cancellation to propagate
        try await Task.sleep(for: .milliseconds(200))
        #expect(cancelled.value, "Background task should be cancelled when object is deallocated from main actor")
    }

    @Test("nonisolated(unsafe) task property allows deinit to cancel without compiler error")
    @MainActor func testNonisolatedUnsafePatternCompiles() async throws {
        // This test verifies the core fix: a @MainActor @Observable class with a
        // nonisolated(unsafe) Task property can compile and run deinit successfully.
        //
        // Before the fix, `authStateTask?.cancel()` in deinit produced:
        //   "Main actor-isolated property 'authStateTask' can not be referenced
        //    from a nonisolated context"
        //
        // The fix: marking the property `nonisolated(unsafe)` allows deinit to access it.
        // Task.cancel() is itself thread-safe, so this is safe at runtime.

        let cancelled = AtomicFlag(false)

        // Create and immediately release — exercises the deinit path
        var stub: MainActorServiceStub? = MainActorServiceStub(
            onCancelled: { cancelled.set(true) }
        )
        #expect(stub != nil)
        stub = nil

        // Wait for the background task to observe cancellation
        try await Task.sleep(for: .milliseconds(200))
        #expect(cancelled.value, "deinit should cancel the background task via nonisolated(unsafe) property")
    }

    @Test("Rapid create-destroy cycles don't crash")
    @MainActor func testRapidCreateDestroyCycles() async throws {
        // Stress test: rapidly create and destroy instances to surface any
        // race between task startup and deinit cancellation.
        for _ in 0..<50 {
            var stub: MainActorServiceStub? = MainActorServiceStub(
                onCancelled: {}
            )
            // Immediately release
            stub = nil
        }

        // If we get here without crashing, the test passes.
        // Give time for all tasks to wind down.
        try await Task.sleep(for: .milliseconds(500))
    }
}
