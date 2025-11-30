//
//  trendyUITests.swift
//  trendyUITests
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import XCTest

final class trendyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Skip these tests during Fastlane screenshot capture
        // Use ScreenshotTests.swift instead for screenshots
        try skipIfScreenshotMode()

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Helpers

    private func skipIfScreenshotMode() throws {
        if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] != nil {
            throw XCTSkip("Skipping during Fastlane screenshot capture")
        }
    }
}
