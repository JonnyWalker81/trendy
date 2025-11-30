//
//  ScreenshotTests.swift
//  trendyUITests
//
//  UI Tests specifically for capturing App Store screenshots
//  Run with: fastlane screenshots
//

import XCTest

final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false

        app = XCUIApplication()

        // Configure for screenshot mode
        app.launchArguments = [
            "--screenshot-mode",
            "-FASTLANE_SNAPSHOT", "YES",
            "-ui_testing",
            "-UITestingDarkModeEnabled"  // Custom flag for dark mode
        ]

        app.launchEnvironment = [
            "UITEST_SCREENSHOT_MODE": "1",
            "UITEST_MOCK_DATA": "1",
            "UITEST_SKIP_AUTH": "1"
        ]

        // Set simulator to dark mode before launching (iOS 15+)
        if #available(iOS 15.0, *) {
            XCUIDevice.shared.appearance = .dark
        }

        // Set up Fastlane snapshot helper
        setupSnapshot(app, waitForAnimations: true)

        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Tests

    /// 01: Dashboard with colorful event bubbles
    @MainActor
    func test01_DashboardBubblesView() throws {
        // Wait for dashboard to load - use bubblesGrid since dashboardView on NavigationStack isn't exposed
        let bubblesGrid = app.otherElements["bubblesGrid"]
        XCTAssertTrue(bubblesGrid.waitForExistence(timeout: 15), "Dashboard bubbles grid should appear")

        // Give time for animations to complete
        sleep(1)

        snapshot("01_Dashboard")
    }

    /// 02: Event list with search and filter
    @MainActor
    func test02_EventListWithFilter() throws {
        // Navigate to Event List tab - use label from tabItem since custom identifiers aren't exposed
        let listTab = app.tabBars.buttons["List"]
        XCTAssertTrue(listTab.waitForExistence(timeout: 10), "Event List tab should exist")
        listTab.tap()

        // Wait for list view - use navigation bar title since other identifiers aren't reliably exposed
        let navBar = app.navigationBars["Events"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Events navigation bar should appear")

        // Wait for content to load
        sleep(1)

        snapshot("02_EventList")
    }

    /// 03: Calendar month view with event indicators
    @MainActor
    func test03_CalendarMonthView() throws {
        // Navigate to Calendar tab - use label from tabItem
        let calendarTab = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 10), "Calendar tab should exist")
        calendarTab.tap()

        // Wait for calendar view - use navigation bar title
        let navBar = app.navigationBars["Calendar"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Calendar navigation bar should appear")

        // Ensure we're on month view (default)
        let viewSelector = app.segmentedControls["calendarViewModeSelector"]
        if viewSelector.waitForExistence(timeout: 3) {
            let monthButton = viewSelector.buttons["Month"]
            if monthButton.exists && !monthButton.isSelected {
                monthButton.tap()
                sleep(1)
            }
        }

        sleep(1)
        snapshot("03_CalendarMonth")
    }

    /// 04: Calendar year view showing annual overview
    @MainActor
    func test04_CalendarYearView() throws {
        // Navigate to Calendar tab - use label from tabItem
        let calendarTab = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 10), "Calendar tab should exist")
        calendarTab.tap()

        // Wait for calendar view - use navigation bar title
        let navBar = app.navigationBars["Calendar"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Calendar navigation bar should appear")

        // Switch to Year view
        let viewSelector = app.segmentedControls["calendarViewModeSelector"]
        XCTAssertTrue(viewSelector.waitForExistence(timeout: 5), "View mode selector should exist")
        let yearButton = viewSelector.buttons["Year"]
        XCTAssertTrue(yearButton.exists, "Year button should exist")
        yearButton.tap()

        // Wait for year view to render
        let yearView = app.otherElements["calendarYearView"]
        _ = yearView.waitForExistence(timeout: 5)
        sleep(1)

        snapshot("04_CalendarYear")
    }

    /// 05: Analytics with charts and statistics
    @MainActor
    func test05_AnalyticsChart() throws {
        // Navigate to Analytics tab - use label from tabItem
        let analyticsTab = app.tabBars.buttons["Analytics"]
        XCTAssertTrue(analyticsTab.waitForExistence(timeout: 10), "Analytics tab should exist")
        analyticsTab.tap()

        // Wait for analytics view - use navigation bar title
        let navBar = app.navigationBars["Analytics"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Analytics navigation bar should appear")
        sleep(1)

        snapshot("05_Analytics")
    }

    /// 06: Insights showing streaks and correlations
    @MainActor
    func test06_InsightsBanner() throws {
        // Navigate to Dashboard (insights are shown here) - use label from tabItem
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        if dashboardTab.exists {
            dashboardTab.tap()
        }

        // Wait for insights banner
        let insightsBanner = app.otherElements["insightsBannerView"]
        _ = insightsBanner.waitForExistence(timeout: 5)

        // Also check Analytics view for more detailed insights - use label from tabItem
        let analyticsTab = app.tabBars.buttons["Analytics"]
        if analyticsTab.exists {
            analyticsTab.tap()
            sleep(1)
        }

        snapshot("06_Insights")
    }

    /// 07: Settings with event type customization
    @MainActor
    func test07_SettingsEventTypes() throws {
        // Navigate to Settings tab - use label from tabItem
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab should exist")
        settingsTab.tap()

        // Wait for settings view - use navigation bar title since List button identifiers aren't exposed
        let navBar = app.navigationBars["Settings"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Settings navigation bar should appear")
        sleep(1)

        snapshot("07_Settings")
    }

    /// 08: Widget preview (shown from dashboard)
    @MainActor
    func test08_WidgetPreview() throws {
        // Navigate to Dashboard - use label from tabItem
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        if dashboardTab.exists {
            dashboardTab.tap()
        }

        // Wait for dashboard to load - use bubblesGrid since dashboardView on NavigationStack isn't exposed
        let bubblesGrid = app.otherElements["bubblesGrid"]
        XCTAssertTrue(bubblesGrid.waitForExistence(timeout: 10), "Dashboard bubbles grid should appear")

        sleep(1)

        // For widget screenshot, we capture the dashboard which showcases
        // the bubble UI that mirrors the widget experience
        snapshot("08_WidgetPreview")
    }
}

// MARK: - Screenshot Test Helpers

extension ScreenshotTests {

    /// Navigate to a specific tab by label name (e.g., "Dashboard", "List", "Calendar")
    func navigateToTab(_ label: String) {
        let tab = app.tabBars.buttons[label]
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
        }
    }

    /// Wait for an element and return whether it exists
    @discardableResult
    func waitForElement(_ identifier: String, timeout: TimeInterval = 10) -> Bool {
        let element = app.otherElements[identifier]
        return element.waitForExistence(timeout: timeout)
    }

    /// Wait for app to be idle (no activity indicators)
    func waitForIdle() {
        // Wait for any loading indicators to disappear
        let loadingIndicator = app.activityIndicators.firstMatch
        if loadingIndicator.exists {
            let predicate = NSPredicate(format: "exists == false")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: loadingIndicator)
            _ = XCTWaiter.wait(for: [expectation], timeout: 10)
        }
    }
}
