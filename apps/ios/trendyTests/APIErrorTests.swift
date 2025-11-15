//
//  APIErrorTests.swift
//  trendyTests
//
//  Production-grade tests for APIError enum
//
//  SUT: APIError (HTTP client error handling)
//
//  Assumptions:
//  - APIError is a Swift enum conforming to LocalizedError
//  - Cases: invalidResponse, httpError(Int), serverError(String, Int), decodingError(Error), networkError(Error), noConnection
//  - errorDescription provides user-friendly messages
//  - Associated values contain diagnostic information (status codes, messages)
//
//  Covered Behaviors:
//  ✅ All error cases have descriptive errorDescription
//  ✅ httpError includes HTTP status code
//  ✅ serverError includes server message and status code
//  ✅ decodingError wraps underlying error
//  ✅ networkError wraps underlying error
//  ✅ Error messages are user-friendly and actionable
//
//  Intentionally Omitted:
//  - Network request execution (tested in APIClient integration tests)
//  - Error presentation UI (tested in UI tests)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Suite

@Suite("APIError Error Descriptions")
struct APIErrorDescriptionTests {

    @Test("APIError invalidResponse has descriptive message")
    func test_apiError_invalidResponse_hasDescriptiveMessage() {
        let error = APIError.invalidResponse

        let description = error.errorDescription ?? ""
        #expect(description.contains("Invalid response"), "Error should mention 'Invalid response'")
        #expect(!description.isEmpty, "Error description should not be empty")
    }

    @Test("APIError httpError includes status code")
    func test_apiError_httpError_includesStatusCode() {
        let error = APIError.httpError(404)

        let description = error.errorDescription ?? ""
        #expect(description.contains("404"), "Error should include status code 404")
        #expect(description.contains("HTTP error"), "Error should mention HTTP error")
    }

    @Test("APIError serverError includes message and status code")
    func test_apiError_serverError_includesMessageAndCode() {
        let error = APIError.serverError("Invalid event type", 400)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Invalid event type"), "Error should include server message")
        #expect(description.contains("400"), "Error should include status code 400")
        #expect(description.contains("Server error"), "Error should mention server error")
    }

    @Test("APIError decodingError includes underlying error")
    func test_apiError_decodingError_includesUnderlyingError() {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test decoding failed" }
        }

        let underlyingError = TestError()
        let error = APIError.decodingError(underlyingError)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Failed to decode"), "Error should mention decoding failure")
        #expect(description.contains("Test decoding failed"), "Error should include underlying error message")
    }

    @Test("APIError networkError includes underlying error")
    func test_apiError_networkError_includesUnderlyingError() {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Connection timeout" }
        }

        let underlyingError = TestError()
        let error = APIError.networkError(underlyingError)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Network error"), "Error should mention network error")
        #expect(description.contains("Connection timeout"), "Error should include underlying error message")
    }

    @Test("APIError noConnection has descriptive message")
    func test_apiError_noConnection_hasDescriptiveMessage() {
        let error = APIError.noConnection

        let description = error.errorDescription ?? ""
        #expect(description.contains("No internet connection"), "Error should mention no internet connection")
        #expect(!description.isEmpty, "Error description should not be empty")
    }
}

@Suite("APIError HTTP Status Codes")
struct APIErrorHTTPStatusCodeTests {

    @Test("APIError httpError with common status codes", arguments: [
        (200, "200"),  // OK (shouldn't normally error, but test handles it)
        (400, "400"),  // Bad Request
        (401, "401"),  // Unauthorized
        (403, "403"),  // Forbidden
        (404, "404"),  // Not Found
        (500, "500"),  // Internal Server Error
        (502, "502"),  // Bad Gateway
        (503, "503")   // Service Unavailable
    ])
    func test_apiError_httpError_commonStatusCodes(code: Int, expectedString: String) {
        let error = APIError.httpError(code)

        let description = error.errorDescription ?? ""
        #expect(description.contains(expectedString), "Error should include status code \(code)")
    }

    @Test("APIError serverError with different status codes", arguments: [
        (400, "Bad Request"),
        (401, "Unauthorized"),
        (404, "Not Found"),
        (500, "Internal Server Error")
    ])
    func test_apiError_serverError_differentStatusCodes(code: Int, message: String) {
        let error = APIError.serverError(message, code)

        let description = error.errorDescription ?? ""
        #expect(description.contains("\(code)"), "Error should include status code \(code)")
        #expect(description.contains(message), "Error should include message '\(message)'")
    }
}

@Suite("APIError Pattern Matching")
struct APIErrorPatternMatchingTests {

    @Test("APIError invalidResponse can be pattern matched")
    func test_apiError_invalidResponse_patternMatches() {
        let error = APIError.invalidResponse

        switch error {
        case .invalidResponse:
            #expect(true, "Should match .invalidResponse")
        default:
            #expect(false, "Should not match other cases")
        }
    }

    @Test("APIError httpError can extract status code")
    func test_apiError_httpError_extractsStatusCode() {
        let error = APIError.httpError(404)

        switch error {
        case .httpError(let code):
            #expect(code == 404, "Should extract status code 404")
        default:
            #expect(false, "Should match .httpError")
        }
    }

    @Test("APIError serverError can extract message and code")
    func test_apiError_serverError_extractsMessageAndCode() {
        let error = APIError.serverError("Invalid input", 400)

        switch error {
        case .serverError(let message, let code):
            #expect(message == "Invalid input", "Should extract message")
            #expect(code == 400, "Should extract status code 400")
        default:
            #expect(false, "Should match .serverError")
        }
    }

    @Test("APIError decodingError can extract underlying error")
    func test_apiError_decodingError_extractsUnderlyingError() {
        struct TestError: Error {}
        let underlyingError = TestError()
        let error = APIError.decodingError(underlyingError)

        switch error {
        case .decodingError(let innerError):
            #expect(innerError is TestError, "Should extract underlying error")
        default:
            #expect(false, "Should match .decodingError")
        }
    }

    @Test("APIError networkError can extract underlying error")
    func test_apiError_networkError_extractsUnderlyingError() {
        struct TestError: Error {}
        let underlyingError = TestError()
        let error = APIError.networkError(underlyingError)

        switch error {
        case .networkError(let innerError):
            #expect(innerError is TestError, "Should extract underlying error")
        default:
            #expect(false, "Should match .networkError")
        }
    }

    @Test("APIError noConnection can be pattern matched")
    func test_apiError_noConnection_patternMatches() {
        let error = APIError.noConnection

        switch error {
        case .noConnection:
            #expect(true, "Should match .noConnection")
        default:
            #expect(false, "Should not match other cases")
        }
    }
}

@Suite("APIError Use Cases")
struct APIErrorUseCaseTests {

    @Test("Use case: 401 Unauthorized error")
    func test_useCase_401Unauthorized() {
        let error = APIError.httpError(401)

        let description = error.errorDescription ?? ""
        #expect(description.contains("401"), "Should indicate authentication failure")

        // In real app, this would trigger re-authentication
    }

    @Test("Use case: 404 Not Found error")
    func test_useCase_404NotFound() {
        let error = APIError.httpError(404)

        let description = error.errorDescription ?? ""
        #expect(description.contains("404"), "Should indicate resource not found")
    }

    @Test("Use case: Server validation error")
    func test_useCase_serverValidationError() {
        let error = APIError.serverError("Event type name is required", 400)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Event type name is required"), "Should show server validation message")
        #expect(description.contains("400"), "Should show Bad Request status")
    }

    @Test("Use case: Network timeout")
    func test_useCase_networkTimeout() {
        struct TimeoutError: Error, LocalizedError {
            var errorDescription: String? { "The request timed out." }
        }

        let error = APIError.networkError(TimeoutError())

        let description = error.errorDescription ?? ""
        #expect(description.contains("Network error"), "Should indicate network issue")
        #expect(description.contains("timed out"), "Should mention timeout")
    }

    @Test("Use case: JSON decoding failure")
    func test_useCase_jsonDecodingFailure() {
        enum DecodingError: Error, LocalizedError {
            case typeMismatch

            var errorDescription: String? { "Type mismatch" }
        }

        let error = APIError.decodingError(DecodingError.typeMismatch)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Failed to decode"), "Should indicate decoding failure")
    }

    @Test("Use case: Offline mode (no connection)")
    func test_useCase_offlineMode() {
        let error = APIError.noConnection

        let description = error.errorDescription ?? ""
        #expect(description.contains("No internet connection"), "Should indicate offline state")

        // In real app, this would trigger offline queue
    }
}

@Suite("APIError LocalizedError Conformance")
struct APIErrorLocalizedErrorTests {

    @Test("APIError conforms to LocalizedError")
    func test_apiError_conformsToLocalizedError() {
        let error: any LocalizedError = APIError.invalidResponse

        #expect(error.errorDescription != nil, "LocalizedError should provide errorDescription")
    }

    @Test("APIError errorDescription never nil", arguments: [
        APIError.invalidResponse,
        APIError.httpError(404),
        APIError.serverError("Test", 400),
        APIError.noConnection
    ])
    func test_apiError_errorDescription_neverNil(error: APIError) {
        #expect(error.errorDescription != nil, "errorDescription should never be nil for \(error)")
        #expect(!error.errorDescription!.isEmpty, "errorDescription should not be empty")
    }
}

@Suite("APIError Edge Cases")
struct APIErrorEdgeCaseTests {

    @Test("APIError httpError with unusual status code")
    func test_apiError_httpError_unusualStatusCode() {
        let error = APIError.httpError(999)

        let description = error.errorDescription ?? ""
        #expect(description.contains("999"), "Should handle unusual status code")
    }

    @Test("APIError httpError with negative status code")
    func test_apiError_httpError_negativeStatusCode() {
        let error = APIError.httpError(-1)

        let description = error.errorDescription ?? ""
        #expect(description.contains("-1"), "Should handle negative status code")
    }

    @Test("APIError serverError with empty message")
    func test_apiError_serverError_emptyMessage() {
        let error = APIError.serverError("", 500)

        let description = error.errorDescription ?? ""
        #expect(!description.isEmpty, "Error description should not be empty even with empty message")
        #expect(description.contains("500"), "Should still include status code")
    }

    @Test("APIError serverError with very long message")
    func test_apiError_serverError_veryLongMessage() {
        let longMessage = String(repeating: "Error ", count: 1000)
        let error = APIError.serverError(longMessage, 400)

        let description = error.errorDescription ?? ""
        #expect(description.contains(longMessage), "Should include full long message")
    }

    @Test("APIError decodingError with NSError")
    func test_apiError_decodingError_withNSError() {
        let nsError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = APIError.decodingError(nsError)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Test error"), "Should include NSError description")
    }
}

@Suite("APIError Equality")
struct APIErrorEqualityTests {

    // Note: APIError doesn't conform to Equatable in the source, but we can test pattern matching

    @Test("APIError invalidResponse instances match")
    func test_apiError_invalidResponse_instancesMatch() {
        let error1 = APIError.invalidResponse
        let error2 = APIError.invalidResponse

        // Both should match the same case
        var matches1 = false
        var matches2 = false

        if case .invalidResponse = error1 { matches1 = true }
        if case .invalidResponse = error2 { matches2 = true }

        #expect(matches1 && matches2, "Both should be .invalidResponse")
    }

    @Test("APIError httpError with same code matches")
    func test_apiError_httpError_sameCode_matches() {
        let error1 = APIError.httpError(404)
        let error2 = APIError.httpError(404)

        if case .httpError(let code1) = error1,
           case .httpError(let code2) = error2 {
            #expect(code1 == code2, "Both should have same status code")
        } else {
            #expect(false, "Both should be .httpError")
        }
    }

    @Test("APIError httpError with different codes don't match")
    func test_apiError_httpError_differentCodes_dontMatch() {
        let error1 = APIError.httpError(404)
        let error2 = APIError.httpError(500)

        if case .httpError(let code1) = error1,
           case .httpError(let code2) = error2 {
            #expect(code1 != code2, "Status codes should be different")
        } else {
            #expect(false, "Both should be .httpError")
        }
    }
}

@Suite("APIError in APIClient Context")
struct APIErrorInAPIClientTests {

    @Test("APIClient would throw invalidResponse for non-HTTP response")
    func test_apiClient_invalidResponse_scenario() {
        // Scenario: URLSession returns non-HTTPURLResponse
        let error = APIError.invalidResponse

        #expect(error.errorDescription != nil, "Should have descriptive error")
        // In APIClient, this would be thrown when response is not HTTPURLResponse
    }

    @Test("APIClient would throw httpError for non-2xx status")
    func test_apiClient_httpError_scenario() {
        // Scenario: Server returns 404
        let error = APIError.httpError(404)

        let description = error.errorDescription ?? ""
        #expect(description.contains("404"), "Should indicate 404 status")
    }

    @Test("APIClient would throw serverError with parsed error response")
    func test_apiClient_serverError_scenario() {
        // Scenario: Server returns 400 with JSON error body
        let error = APIError.serverError("Invalid event type ID", 400)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Invalid event type ID"), "Should include server message")
    }

    @Test("APIClient would throw decodingError when JSON decode fails")
    func test_apiClient_decodingError_scenario() {
        struct DecodingIssue: Error, LocalizedError {
            var errorDescription: String? { "Key 'event_type_id' not found" }
        }

        let error = APIError.decodingError(DecodingIssue())

        let description = error.errorDescription ?? ""
        #expect(description.contains("Failed to decode"), "Should indicate decoding failure")
        #expect(description.contains("event_type_id"), "Should include decoding details")
    }

    @Test("APIClient would throw networkError for URLSession errors")
    func test_apiClient_networkError_scenario() {
        let urlError = URLError(.timedOut)
        let error = APIError.networkError(urlError)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Network error"), "Should indicate network issue")
    }

    @Test("APIClient would throw noConnection when offline")
    func test_apiClient_noConnection_scenario() {
        // Scenario: Network monitor detects offline state
        let error = APIError.noConnection

        let description = error.errorDescription ?? ""
        #expect(description.contains("No internet connection"), "Should indicate offline state")
    }
}

@Suite("APIError User-Facing Messages")
struct APIErrorUserFacingMessagesTests {

    @Test("APIError messages are user-friendly, not technical jargon")
    func test_apiError_messages_areUserFriendly() {
        let errors: [APIError] = [
            .invalidResponse,
            .httpError(404),
            .serverError("Validation failed", 400),
            .noConnection
        ]

        for error in errors {
            let description = error.errorDescription ?? ""

            // Should not contain overly technical terms
            #expect(!description.contains("nil"), "Should not mention 'nil'")
            #expect(!description.contains("null"), "Should not mention 'null'")
            // Should be descriptive
            #expect(description.count > 10, "Message should be descriptive, not just a code")
        }
    }

    @Test("APIError httpError messages mention 'HTTP error'")
    func test_apiError_httpError_mentionsHTTPError() {
        let error = APIError.httpError(500)

        let description = error.errorDescription ?? ""
        #expect(description.contains("HTTP error"), "Should mention 'HTTP error' for clarity")
    }

    @Test("APIError serverError messages mention 'Server error'")
    func test_apiError_serverError_mentionsServerError() {
        let error = APIError.serverError("Test", 500)

        let description = error.errorDescription ?? ""
        #expect(description.contains("Server error"), "Should mention 'Server error' for clarity")
    }
}

// MARK: - Test Helpers

/// Helper to create common HTTP errors
struct HTTPErrorFixture {
    static let badRequest = APIError.httpError(400)
    static let unauthorized = APIError.httpError(401)
    static let forbidden = APIError.httpError(403)
    static let notFound = APIError.httpError(404)
    static let internalServerError = APIError.httpError(500)
    static let serviceUnavailable = APIError.httpError(503)
}
