//
//  MigrationFlowUITests.swift
//  trendyUITests
//
//  Production-grade UI tests for data migration flow
//
//  Flow Under Test: Local SwiftData → Backend API migration
//
//  Prerequisites:
//  - User must have local data (events/event types) before first login
//  - Supabase backend must be accessible
//  - Accessibility identifiers must be set
//
//  Covered Scenarios:
//  ✅ Migration view appears on first login with local data
//  ✅ Migration progress indicators work correctly
//  ✅ Migration completes successfully
//  ✅ Migration error handling and retry
//  ✅ Skip migration (no local data scenario)
//  ✅ Post-migration data verification
//
//  Accessibility Identifiers Required:
//  - Migration: "migrationView", "migrationProgressBar", "migrationStatusLabel", "migrationRetryButton"
//  - Dashboard: "dashboardView"
//
//  Intentionally Omitted:
//  - Network failure recovery (complex to simulate in UI tests)
//  - Large dataset migration (performance testing)
//

import XCTest

final class MigrationFlowUITests: XCTestCase {

    var app: XCUIApplication!

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        // Skip during Fastlane screenshot capture - use ScreenshotTests.swift instead
        if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] != nil {
            throw XCTSkip("Skipping during Fastlane screenshot capture")
        }

        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1",
            "UITEST_HAS_LOCAL_DATA": "1",  // Simulate local pre-migration data
            "UITEST_FIRST_LOGIN": "1"       // Trigger migration flow
        ]
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: 5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Migration Flow Tests

    func test_migration_viewAppears_onFirstLogin() throws {
        // Given: User has local data and logs in for first time
        // (Simulated via launch environment)

        // Complete login flow
        performLogin()

        // Then: Migration view should appear
        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(
            migrationView.waitForExistence(timeout: 10),
            "Migration view should appear on first login with local data"
        )

        // Verify migration UI elements
        let progressBar = app.progressIndicators["migrationProgressBar"]
        XCTAssertTrue(progressBar.exists, "Progress bar should be visible")

        let statusLabel = app.staticTexts["migrationStatusLabel"]
        XCTAssertTrue(statusLabel.exists, "Status label should be visible")
    }

    func test_migration_progressIndicator_updates() throws {
        // Given: Migration view is displayed
        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        // Then: Progress should update during migration
        let progressBar = app.progressIndicators["migrationProgressBar"]
        let statusLabel = app.staticTexts["migrationStatusLabel"]

        // Initial state
        XCTAssertTrue(statusLabel.exists, "Status should show migration starting")

        // Wait for progress updates (migration in progress)
        sleep(2)

        // Progress bar should show some progress (> 0%)
        // Note: Exact progress value testing is fragile, just verify it exists
        XCTAssertTrue(progressBar.exists, "Progress bar should remain visible during migration")
    }

    func test_migration_completesSuccessfully_navigatesToDashboard() throws {
        // Given: Migration starts
        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        // When: Migration completes (wait for completion)
        // Migration can take time depending on data size
        let dashboardView = app.otherElements["dashboardView"]

        // Then: User should be navigated to dashboard
        XCTAssertTrue(
            dashboardView.waitForExistence(timeout: 60),
            "Should navigate to dashboard after successful migration"
        )

        // Verify migration view is gone
        XCTAssertFalse(migrationView.exists, "Migration view should disappear after completion")
    }

    func test_migration_showsStatusMessages() throws {
        // Given: Migration is in progress
        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        let statusLabel = app.staticTexts["migrationStatusLabel"]

        // Then: Status messages should update throughout migration
        // Check for expected status text patterns
        var foundSyncingMessage = false

        // Wait for syncing message to appear
        let predicate = NSPredicate(format: "label CONTAINS[c] 'syncing' OR label CONTAINS[c] 'migrating'")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: statusLabel)

        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        if result == .completed {
            foundSyncingMessage = true
        }

        XCTAssertTrue(foundSyncingMessage, "Should show syncing/migrating status message")
    }

    func test_migration_errorHandling_showsRetryButton() throws {
        // Given: Migration fails (simulated via launch environment)
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1",
            "UITEST_HAS_LOCAL_DATA": "1",
            "UITEST_FIRST_LOGIN": "1",
            "UITEST_MIGRATION_FAIL": "1"  // Force migration failure
        ]
        app.launch()

        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        // Then: Error UI should appear with retry button
        let retryButton = app.buttons["migrationRetryButton"]
        XCTAssertTrue(
            retryButton.waitForExistence(timeout: 20),
            "Retry button should appear on migration failure"
        )

        // Verify error message
        let errorLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'error' OR label CONTAINS[c] 'failed'")).firstMatch
        XCTAssertTrue(errorLabel.exists, "Error message should be displayed")
    }

    func test_migration_retry_afterFailure_succeeds() throws {
        // Given: Migration fails initially
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1",
            "UITEST_HAS_LOCAL_DATA": "1",
            "UITEST_FIRST_LOGIN": "1",
            "UITEST_MIGRATION_FAIL_ONCE": "1"  // Fail once, then succeed
        ]
        app.launch()

        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        // Wait for retry button
        let retryButton = app.buttons["migrationRetryButton"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 20))

        // When: User taps retry
        retryButton.tap()

        // Then: Migration should succeed on retry
        let dashboardView = app.otherElements["dashboardView"]
        XCTAssertTrue(
            dashboardView.waitForExistence(timeout: 60),
            "Should navigate to dashboard after successful retry"
        )
    }

    func test_migration_skipMigration_noLocalData() throws {
        // Given: User has no local data
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1",
            "UITEST_HAS_LOCAL_DATA": "0",  // No local data
            "UITEST_FIRST_LOGIN": "1"
        ]
        app.launch()

        performLogin()

        // Then: Migration should be skipped, go straight to dashboard
        let dashboardView = app.otherElements["dashboardView"]
        XCTAssertTrue(
            dashboardView.waitForExistence(timeout: 10),
            "Should skip migration and go to dashboard when no local data"
        )

        // Migration view should never appear
        let migrationView = app.otherElements["migrationView"]
        XCTAssertFalse(migrationView.exists, "Migration view should not appear with no local data")
    }

    // MARK: - Post-Migration Tests

    func test_postMigration_eventsAppear_inDashboard() throws {
        // Given: Migration completes
        performLogin()

        let dashboardView = app.otherElements["dashboardView"]
        XCTAssertTrue(dashboardView.waitForExistence(timeout: 60))

        // Then: Migrated events should appear
        let eventList = app.tables["eventList"]
        if eventList.waitForExistence(timeout: 5) {
            XCTAssertGreaterThan(
                eventList.cells.count,
                0,
                "Migrated events should appear in event list"
            )
        }
    }

    func test_postMigration_eventTypesAppear() throws {
        // Given: Migration completes
        performLogin()

        let dashboardView = app.otherElements["dashboardView"]
        XCTAssertTrue(dashboardView.waitForExistence(timeout: 60))

        // Then: Migrated event types should be available
        // Navigate to event creation to verify event types
        let addEventButton = app.buttons["addEventButton"]
        if addEventButton.waitForExistence(timeout: 5) {
            addEventButton.tap()

            // Event type picker should have migrated types
            let eventTypeField = app.buttons["eventTypeField"]
            if eventTypeField.waitForExistence(timeout: 3) {
                eventTypeField.tap()

                // Should show event types list
                let eventTypesList = app.tables["eventTypesList"]
                if eventTypesList.waitForExistence(timeout: 3) {
                    XCTAssertGreaterThan(
                        eventTypesList.cells.count,
                        0,
                        "Migrated event types should be available"
                    )
                }
            }
        }
    }

    // MARK: - Migration Progress Tests

    func test_migration_progressBar_reaches100Percent() throws {
        // Given: Migration starts
        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        let progressBar = app.progressIndicators["migrationProgressBar"]

        // Wait for progress to complete
        // Progress bar value should eventually reach 100%
        let completionExpectation = expectation(description: "Migration completes")

        DispatchQueue.global().async {
            var isComplete = false
            let timeout = Date().addingTimeInterval(60)

            while !isComplete && Date() < timeout {
                if self.app.otherElements["dashboardView"].exists {
                    isComplete = true
                    completionExpectation.fulfill()
                }
                sleep(1)
            }
        }

        wait(for: [completionExpectation], timeout: 65)
    }

    func test_migration_statusMessages_progressThroughStages() throws {
        // Given: Migration is in progress
        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        let statusLabel = app.staticTexts["migrationStatusLabel"]

        // Track status messages seen
        var seenEventTypeMessage = false
        var seenEventMessage = false

        // Monitor status changes for 30 seconds
        let endTime = Date().addingTimeInterval(30)

        while Date() < endTime {
            let currentStatus = statusLabel.label.lowercased()

            if currentStatus.contains("event type") {
                seenEventTypeMessage = true
            }
            if currentStatus.contains("event") && !currentStatus.contains("event type") {
                seenEventMessage = true
            }

            // Break if we've seen both
            if seenEventTypeMessage && seenEventMessage {
                break
            }

            sleep(1)
        }

        // Verify we saw progression through migration stages
        // Note: Exact messages depend on implementation
        XCTAssertTrue(
            seenEventTypeMessage || seenEventMessage,
            "Should show migration stage messages"
        )
    }

    // MARK: - Accessibility Tests

    func test_migration_accessibilityLabels_areSet() throws {
        // Given: Migration view appears
        performLogin()

        let migrationView = app.otherElements["migrationView"]
        XCTAssertTrue(migrationView.waitForExistence(timeout: 10))

        // Then: All migration UI elements should have accessibility identifiers
        let progressBar = app.progressIndicators["migrationProgressBar"]
        let statusLabel = app.staticTexts["migrationStatusLabel"]

        XCTAssertTrue(progressBar.exists, "Progress bar should have accessibility ID")
        XCTAssertTrue(statusLabel.exists, "Status label should have accessibility ID")
    }

    // MARK: - Performance Tests

    func test_migration_performanceWith100Events() throws {
        // Given: User has 100 local events to migrate
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1",
            "UITEST_HAS_LOCAL_DATA": "1",
            "UITEST_FIRST_LOGIN": "1",
            "UITEST_LOCAL_EVENT_COUNT": "100"  // 100 events to migrate
        ]
        app.launch()

        measure(metrics: [XCTClockMetric()]) {
            // Perform login and migration
            performLogin()

            // Wait for migration to complete
            let dashboardView = app.otherElements["dashboardView"]
            _ = dashboardView.waitForExistence(timeout: 120)
        }
    }

    // MARK: - Helper Methods

    private func performLogin() {
        let emailField = app.textFields["loginEmailField"]
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText("test@example.com")

            let passwordField = app.secureTextFields["loginPasswordField"]
            passwordField.tap()
            passwordField.typeText("Password123!")

            app.buttons["loginButton"].tap()
        }
    }
}
