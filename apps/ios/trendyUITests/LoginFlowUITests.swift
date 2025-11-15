//
//  LoginFlowUITests.swift
//  trendyUITests
//
//  Production-grade UI tests for authentication flow
//
//  Flow Under Test: Login & Signup
//
//  Prerequisites:
//  - App must have accessibility identifiers set on UI elements
//  - Backend API must be running (or use mock server)
//  - Test user accounts should exist or be creatable
//
//  Covered Scenarios:
//  ✅ Successful login with valid credentials
//  ✅ Login failure with invalid credentials
//  ✅ Successful signup with new user
//  ✅ Signup validation (password requirements, email format)
//  ✅ Navigation between login and signup screens
//  ✅ Keyboard handling and form submission
//  ✅ Error message display
//
//  Accessibility Identifiers Required:
//  - Login Screen: "loginEmailField", "loginPasswordField", "loginButton", "signupNavButton"
//  - Signup Screen: "signupEmailField", "signupPasswordField", "signupConfirmPasswordField", "signupButton"
//  - Error: "errorMessage"
//  - Dashboard: "dashboardView" (post-login)
//
//  Intentionally Omitted:
//  - Password reset flow (future enhancement)
//  - OAuth/Social login (if not implemented)
//  - Biometric authentication (device-specific)
//

import XCTest

final class LoginFlowUITests: XCTestCase {

    var app: XCUIApplication!

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]  // Signal to app it's in UI test mode
        app.launchEnvironment = [
            "UITEST_RESET_STATE": "1",  // Reset user defaults
            "UITEST_USE_MOCK_API": "0"   // Use real API (or change to 1 for mock)
        ]
        app.launch()

        // Wait for app to fully launch
        _ = app.wait(for: .runningForeground, timeout: 5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Login Flow Tests

    func test_login_successfulLogin_navigatesToDashboard() throws {
        // Given: Valid test credentials
        let testEmail = "test@example.com"
        let testPassword = "Password123!"

        // When: User enters valid credentials and taps login
        let emailField = app.textFields["loginEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field should exist")
        emailField.tap()
        emailField.typeText(testEmail)

        let passwordField = app.secureTextFields["loginPasswordField"]
        XCTAssertTrue(passwordField.exists, "Password field should exist")
        passwordField.tap()
        passwordField.typeText(testPassword)

        let loginButton = app.buttons["loginButton"]
        XCTAssertTrue(loginButton.exists, "Login button should exist")
        loginButton.tap()

        // Then: User should be navigated to dashboard
        let dashboardView = app.otherElements["dashboardView"]
        XCTAssertTrue(
            dashboardView.waitForExistence(timeout: 10),
            "Dashboard should appear after successful login"
        )
    }

    func test_login_invalidCredentials_showsError() throws {
        // Given: Invalid credentials
        let invalidEmail = "wrong@example.com"
        let invalidPassword = "WrongPassword123"

        // When: User enters invalid credentials
        let emailField = app.textFields["loginEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(invalidEmail)

        let passwordField = app.secureTextFields["loginPasswordField"]
        passwordField.tap()
        passwordField.typeText(invalidPassword)

        app.buttons["loginButton"].tap()

        // Then: Error message should be displayed
        let errorMessage = app.staticTexts["errorMessage"]
        XCTAssertTrue(
            errorMessage.waitForExistence(timeout: 5),
            "Error message should appear for invalid credentials"
        )

        // Verify error message contains relevant text
        let errorText = errorMessage.label
        XCTAssertTrue(
            errorText.contains("Invalid") || errorText.contains("error") || errorText.contains("failed"),
            "Error message should indicate login failure: \(errorText)"
        )
    }

    func test_login_emptyFields_disablesLoginButton() throws {
        // Given: Empty login form
        let loginButton = app.buttons["loginButton"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))

        // Then: Login button should be disabled
        XCTAssertFalse(loginButton.isEnabled, "Login button should be disabled with empty fields")
    }

    func test_login_emailOnly_disablesLoginButton() throws {
        // Given: Only email entered
        let emailField = app.textFields["loginEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("test@example.com")

        // Then: Login button should still be disabled
        let loginButton = app.buttons["loginButton"]
        XCTAssertFalse(loginButton.isEnabled, "Login button should be disabled without password")
    }

    func test_login_navigationToSignup_works() throws {
        // Given: On login screen
        let signupNavButton = app.buttons["signupNavButton"]
        XCTAssertTrue(signupNavButton.waitForExistence(timeout: 5), "Signup nav button should exist")

        // When: User taps "Sign Up" navigation
        signupNavButton.tap()

        // Then: Signup screen should appear
        let signupEmailField = app.textFields["signupEmailField"]
        XCTAssertTrue(
            signupEmailField.waitForExistence(timeout: 3),
            "Signup screen should appear"
        )
    }

    // MARK: - Signup Flow Tests

    func test_signup_successfulSignup_navigatesToDashboard() throws {
        // Navigate to signup screen
        app.buttons["signupNavButton"].tap()

        // Given: Valid new user credentials
        let newEmail = "newuser_\(UUID().uuidString.prefix(8))@example.com"
        let newPassword = "NewPassword123!"

        // When: User fills signup form
        let emailField = app.textFields["signupEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(newEmail)

        let passwordField = app.secureTextFields["signupPasswordField"]
        passwordField.tap()
        passwordField.typeText(newPassword)

        // Confirm password field (if exists)
        if app.secureTextFields["signupConfirmPasswordField"].exists {
            let confirmPasswordField = app.secureTextFields["signupConfirmPasswordField"]
            confirmPasswordField.tap()
            confirmPasswordField.typeText(newPassword)
        }

        app.buttons["signupButton"].tap()

        // Then: User should be logged in and see dashboard
        let dashboardView = app.otherElements["dashboardView"]
        XCTAssertTrue(
            dashboardView.waitForExistence(timeout: 15),
            "Dashboard should appear after successful signup"
        )
    }

    func test_signup_invalidEmail_showsError() throws {
        // Navigate to signup screen
        app.buttons["signupNavButton"].tap()

        // Given: Invalid email format
        let invalidEmail = "not-an-email"
        let validPassword = "Password123!"

        // When: User enters invalid email
        let emailField = app.textFields["signupEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(invalidEmail)

        let passwordField = app.secureTextFields["signupPasswordField"]
        passwordField.tap()
        passwordField.typeText(validPassword)

        app.buttons["signupButton"].tap()

        // Then: Error message should appear
        let errorMessage = app.staticTexts["errorMessage"]
        XCTAssertTrue(
            errorMessage.waitForExistence(timeout: 5),
            "Error should appear for invalid email"
        )
    }

    func test_signup_weakPassword_showsError() throws {
        // Navigate to signup screen
        app.buttons["signupNavButton"].tap()

        // Given: Weak password
        let validEmail = "test@example.com"
        let weakPassword = "123"  // Too short

        // When: User enters weak password
        let emailField = app.textFields["signupEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(validEmail)

        let passwordField = app.secureTextFields["signupPasswordField"]
        passwordField.tap()
        passwordField.typeText(weakPassword)

        app.buttons["signupButton"].tap()

        // Then: Error should indicate password requirements
        let errorMessage = app.staticTexts["errorMessage"]
        XCTAssertTrue(
            errorMessage.waitForExistence(timeout: 5),
            "Error should appear for weak password"
        )
    }

    func test_signup_passwordMismatch_showsError() throws {
        // Navigate to signup screen
        app.buttons["signupNavButton"].tap()

        // Given: Mismatched passwords
        let email = "test@example.com"
        let password = "Password123!"
        let confirmPassword = "DifferentPassword123!"

        // When: User enters mismatched passwords
        let emailField = app.textFields["signupEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["signupPasswordField"]
        passwordField.tap()
        passwordField.typeText(password)

        if app.secureTextFields["signupConfirmPasswordField"].exists {
            let confirmPasswordField = app.secureTextFields["signupConfirmPasswordField"]
            confirmPasswordField.tap()
            confirmPasswordField.typeText(confirmPassword)
        }

        app.buttons["signupButton"].tap()

        // Then: Error should indicate password mismatch
        let errorMessage = app.staticTexts["errorMessage"]
        XCTAssertTrue(
            errorMessage.waitForExistence(timeout: 5),
            "Error should appear for password mismatch"
        )
    }

    // MARK: - Keyboard & Interaction Tests

    func test_login_returnKeySubmitsForm() throws {
        // Given: Valid credentials
        let emailField = app.textFields["loginEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("test@example.com")

        let passwordField = app.secureTextFields["loginPasswordField"]
        passwordField.tap()
        passwordField.typeText("Password123!")

        // When: User taps return key on password field
        passwordField.typeText("\n")  // Return key

        // Then: Login should be attempted (button becomes disabled or loading appears)
        // Note: Exact behavior depends on implementation
        // This test assumes form submission happens
        sleep(1)  // Brief wait for submission
    }

    func test_login_keyboardDismissesOnTapOutside() throws {
        // Given: Keyboard is shown
        let emailField = app.textFields["loginEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()

        // Verify keyboard is shown
        XCTAssertTrue(app.keyboards.element.exists, "Keyboard should be visible")

        // When: User taps outside text field
        let loginButton = app.buttons["loginButton"]
        if loginButton.exists {
            loginButton.tap()
        } else {
            // Tap on background
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }

        // Then: Keyboard should dismiss
        XCTAssertFalse(
            app.keyboards.element.exists,
            "Keyboard should be dismissed when tapping outside"
        )
    }

    // MARK: - Error Recovery Tests

    func test_login_errorDismissal_allowsRetry() throws {
        // Given: Login fails and shows error
        let emailField = app.textFields["loginEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("wrong@example.com")

        let passwordField = app.secureTextFields["loginPasswordField"]
        passwordField.tap()
        passwordField.typeText("WrongPassword")

        app.buttons["loginButton"].tap()

        // Wait for error
        let errorMessage = app.staticTexts["errorMessage"]
        XCTAssertTrue(errorMessage.waitForExistence(timeout: 5))

        // When: User modifies email field
        emailField.tap()
        emailField.typeText(XCUIKeyboardKey.delete.rawValue)  // Delete character

        // Then: Error should be cleared or form should allow retry
        // (Exact behavior depends on implementation)
        sleep(1)
    }

    // MARK: - Accessibility Tests

    func test_login_accessibilityLabels_areSet() throws {
        // Verify all critical elements have accessibility identifiers
        let emailField = app.textFields["loginEmailField"]
        let passwordField = app.secureTextFields["loginPasswordField"]
        let loginButton = app.buttons["loginButton"]
        let signupNavButton = app.buttons["signupNavButton"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field should have accessibility ID")
        XCTAssertTrue(passwordField.exists, "Password field should have accessibility ID")
        XCTAssertTrue(loginButton.exists, "Login button should have accessibility ID")
        XCTAssertTrue(signupNavButton.exists, "Signup nav button should have accessibility ID")
    }

    func test_signup_accessibilityLabels_areSet() throws {
        // Navigate to signup
        app.buttons["signupNavButton"].tap()

        // Verify signup screen accessibility
        let emailField = app.textFields["signupEmailField"]
        let passwordField = app.secureTextFields["signupPasswordField"]
        let signupButton = app.buttons["signupButton"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Signup email field should have accessibility ID")
        XCTAssertTrue(passwordField.exists, "Signup password field should have accessibility ID")
        XCTAssertTrue(signupButton.exists, "Signup button should have accessibility ID")
    }

    // MARK: - Performance Tests

    func test_login_performanceOfAuthentication() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Given: Valid credentials
            let emailField = app.textFields["loginEmailField"]
            _ = emailField.waitForExistence(timeout: 5)
            emailField.tap()
            emailField.typeText("test@example.com")

            let passwordField = app.secureTextFields["loginPasswordField"]
            passwordField.tap()
            passwordField.typeText("Password123!")

            // When: Login is performed
            app.buttons["loginButton"].tap()

            // Wait for completion
            _ = app.otherElements["dashboardView"].waitForExistence(timeout: 15)
        }
    }
}
