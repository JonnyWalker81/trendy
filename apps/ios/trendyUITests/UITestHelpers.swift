//
//  UITestHelpers.swift
//  trendyUITests
//
//  Shared utilities and helpers for UI tests
//
//  Purpose:
//  - Reusable test helpers to reduce duplication
//  - Common UI interaction patterns
//  - Wait helpers and expectations
//  - Test data builders
//
//  Usage:
//  import XCTest
//  @testable import trendy
//
//  let app = XCUIApplication()
//  UITestHelpers.login(app: app, email: "test@example.com", password: "pass")
//

import XCTest

/// Shared helpers for UI testing
struct UITestHelpers {

    // MARK: - Authentication Helpers

    /// Perform login with given credentials
    /// - Parameters:
    ///   - app: XCUIApplication instance
    ///   - email: User email
    ///   - password: User password
    ///   - timeout: Maximum wait time for login to complete
    /// - Returns: True if login succeeded, false otherwise
    @discardableResult
    static func login(
        app: XCUIApplication,
        email: String = "test@example.com",
        password: String = "Password123!",
        timeout: TimeInterval = 15
    ) -> Bool {
        let emailField = app.textFields["loginEmailField"]
        guard emailField.waitForExistence(timeout: timeout) else {
            return false
        }

        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["loginPasswordField"]
        guard passwordField.exists else {
            return false
        }

        passwordField.tap()
        passwordField.typeText(password)

        let loginButton = app.buttons["loginButton"]
        guard loginButton.exists else {
            return false
        }

        loginButton.tap()

        // Wait for dashboard to appear
        let dashboardView = app.otherElements["dashboardView"]
        return dashboardView.waitForExistence(timeout: timeout)
    }

    /// Perform signup with given credentials
    /// - Parameters:
    ///   - app: XCUIApplication instance
    ///   - email: New user email (defaults to random UUID-based email)
    ///   - password: User password
    ///   - timeout: Maximum wait time
    /// - Returns: True if signup succeeded
    @discardableResult
    static func signup(
        app: XCUIApplication,
        email: String? = nil,
        password: String = "NewPassword123!",
        timeout: TimeInterval = 15
    ) -> Bool {
        // Navigate to signup screen
        let signupNavButton = app.buttons["signupNavButton"]
        guard signupNavButton.waitForExistence(timeout: 5) else {
            return false
        }
        signupNavButton.tap()

        // Use random email if not provided
        let signupEmail = email ?? "test_\(UUID().uuidString.prefix(8))@example.com"

        let emailField = app.textFields["signupEmailField"]
        guard emailField.waitForExistence(timeout: 5) else {
            return false
        }

        emailField.tap()
        emailField.typeText(signupEmail)

        let passwordField = app.secureTextFields["signupPasswordField"]
        guard passwordField.exists else {
            return false
        }

        passwordField.tap()
        passwordField.typeText(password)

        // Confirm password if field exists
        if app.secureTextFields["signupConfirmPasswordField"].exists {
            let confirmPasswordField = app.secureTextFields["signupConfirmPasswordField"]
            confirmPasswordField.tap()
            confirmPasswordField.typeText(password)
        }

        let signupButton = app.buttons["signupButton"]
        guard signupButton.exists else {
            return false
        }

        signupButton.tap()

        // Wait for dashboard
        let dashboardView = app.otherElements["dashboardView"]
        return dashboardView.waitForExistence(timeout: timeout)
    }

    // MARK: - Navigation Helpers

    /// Navigate to event creation form
    /// - Parameter app: XCUIApplication instance
    /// - Returns: True if navigation succeeded
    @discardableResult
    static func navigateToEventCreation(app: XCUIApplication) -> Bool {
        let addEventButton = app.buttons["addEventButton"]
        guard addEventButton.waitForExistence(timeout: 5) else {
            return false
        }

        addEventButton.tap()

        // Verify form appeared
        let saveButton = app.buttons["saveEventButton"]
        return saveButton.waitForExistence(timeout: 3)
    }

    /// Navigate to calendar view
    /// - Parameter app: XCUIApplication instance
    /// - Returns: True if navigation succeeded
    @discardableResult
    static func navigateToCalendar(app: XCUIApplication) -> Bool {
        let calendarTab = app.buttons["calendarTab"]
        guard calendarTab.waitForExistence(timeout: 5) else {
            return false
        }

        calendarTab.tap()

        let calendarView = app.otherElements["calendarView"]
        return calendarView.waitForExistence(timeout: 3)
    }

    /// Navigate to settings
    /// - Parameter app: XCUIApplication instance
    /// - Returns: True if navigation succeeded
    @discardableResult
    static func navigateToSettings(app: XCUIApplication) -> Bool {
        let settingsTab = app.buttons["settingsTab"]
        guard settingsTab.waitForExistence(timeout: 5) else {
            return false
        }

        settingsTab.tap()

        let settingsView = app.otherElements["settingsView"]
        return settingsView.waitForExistence(timeout: 3)
    }

    // MARK: - Event Creation Helpers

    /// Create a quick event with minimal data
    /// - Parameters:
    ///   - app: XCUIApplication instance
    ///   - eventTypeName: Optional event type name to select
    /// - Returns: True if event creation succeeded
    @discardableResult
    static func createQuickEvent(
        app: XCUIApplication,
        eventTypeName: String? = nil
    ) -> Bool {
        guard navigateToEventCreation(app: app) else {
            return false
        }

        // Select event type if specified
        if let typeName = eventTypeName {
            let eventTypeButton = app.buttons["eventTypeField"]
            if eventTypeButton.exists {
                eventTypeButton.tap()

                // Find and tap the specified event type
                let typeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS '\(typeName)'")).firstMatch
                if typeButton.exists {
                    typeButton.tap()
                }
            }
        }

        // Save
        let saveButton = app.buttons["saveEventButton"]
        guard saveButton.exists else {
            return false
        }

        saveButton.tap()

        // Verify return to event list
        let eventList = app.tables["eventList"]
        return eventList.waitForExistence(timeout: 5)
    }

    /// Create event with notes
    /// - Parameters:
    ///   - app: XCUIApplication instance
    ///   - notes: Event notes text
    /// - Returns: True if event creation succeeded
    @discardableResult
    static func createEventWithNotes(
        app: XCUIApplication,
        notes: String
    ) -> Bool {
        guard navigateToEventCreation(app: app) else {
            return false
        }

        // Add notes
        let notesField = app.textViews["eventNotesField"]
        if notesField.waitForExistence(timeout: 3) {
            notesField.tap()
            notesField.typeText(notes)
        }

        // Save
        app.buttons["saveEventButton"].tap()

        let eventList = app.tables["eventList"]
        return eventList.waitForExistence(timeout: 5)
    }

    // MARK: - Keyboard Helpers

    /// Dismiss keyboard by tapping outside
    /// - Parameter app: XCUIApplication instance
    static func dismissKeyboard(app: XCUIApplication) {
        if app.keyboards.element.exists {
            // Tap on a neutral area
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }
    }

    /// Type text and dismiss keyboard
    /// - Parameters:
    ///   - element: Text field or text view
    ///   - text: Text to type
    ///   - app: XCUIApplication instance
    static func typeAndDismiss(
        element: XCUIElement,
        text: String,
        app: XCUIApplication
    ) {
        element.tap()
        element.typeText(text)
        dismissKeyboard(app: app)
    }

    // MARK: - Wait Helpers

    /// Wait for element to exist and be hittable
    /// - Parameters:
    ///   - element: UI element to wait for
    ///   - timeout: Maximum wait time
    /// - Returns: True if element became hittable within timeout
    static func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for element to disappear
    /// - Parameters:
    ///   - element: UI element to wait for
    ///   - timeout: Maximum wait time
    /// - Returns: True if element disappeared within timeout
    static func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    // MARK: - Assertion Helpers

    /// Assert element exists with custom message
    /// - Parameters:
    ///   - element: UI element to check
    ///   - message: Custom assertion message
    ///   - file: Source file
    ///   - line: Source line
    static func assertExists(
        _ element: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, message, file: file, line: line)
    }

    /// Assert element is hittable
    /// - Parameters:
    ///   - element: UI element to check
    ///   - message: Custom assertion message
    ///   - file: Source file
    ///   - line: Source line
    static func assertHittable(
        _ element: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.isHittable, message, file: file, line: line)
    }

    // MARK: - Screenshot Helpers

    /// Take and attach screenshot with name
    /// - Parameters:
    ///   - name: Screenshot name
    ///   - app: XCUIApplication instance
    static func screenshot(
        name: String,
        app: XCUIApplication
    ) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Screenshot: \(name)") { activity in
            activity.add(attachment)
        }
    }

    // MARK: - Test Data Helpers

    /// Generate random email for testing
    /// - Returns: Random email address
    static func randomEmail() -> String {
        return "test_\(UUID().uuidString.prefix(8))@example.com"
    }

    /// Generate random password that meets requirements
    /// - Returns: Valid password
    static func randomPassword() -> String {
        return "Test\(Int.random(in: 1000...9999))!"
    }

    // MARK: - Cleanup Helpers

    /// Reset app state for fresh test
    /// - Parameter app: XCUIApplication instance
    static func resetAppState(app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1"
        ]
        app.launch()
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    /// Tap element if it exists and is hittable
    /// - Returns: True if tap succeeded
    @discardableResult
    func tapIfPossible() -> Bool {
        guard exists && isHittable else {
            return false
        }
        tap()
        return true
    }

    /// Clear text and type new text
    /// - Parameter text: New text to type
    func clearAndType(_ text: String) {
        guard exists else { return }

        tap()

        // Select all text
        if let stringValue = value as? String {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            typeText(deleteString)
        }

        // Type new text
        typeText(text)
    }
}

// MARK: - XCUIApplication Extensions

extension XCUIApplication {
    /// Check if app is in foreground
    var isInForeground: Bool {
        return state == .runningForeground
    }

    /// Launch with default UI test configuration
    func launchForUITesting(resetState: Bool = true, loggedIn: Bool = false) {
        launchArguments = ["--uitesting"]
        launchEnvironment = [
            "UITEST_RESET_STATE": resetState ? "1" : "0",
            "UITEST_LOGGED_IN": loggedIn ? "1" : "0"
        ]
        launch()
    }
}
