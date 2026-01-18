package apierror

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	// Set gin to test mode to reduce noise in test output
	gin.SetMode(gin.TestMode)
}

func TestProblemDetailsJSON(t *testing.T) {
	retryAfter := 60
	problem := &ProblemDetails{
		Type:        TypeValidation,
		Title:       TitleValidation,
		Status:      http.StatusBadRequest,
		Detail:      "Field validation failed",
		Instance:    "/api/v1/events/123",
		RequestID:   "req-abc123",
		UserMessage: "Please fix the errors",
		RetryAfter:  &retryAfter,
		Action:      "fix_validation",
		Errors: []FieldError{
			{Field: "name", Message: "is required", Code: "required"},
			{Field: "timestamp", Message: "must be a valid date", Code: "invalid_date"},
		},
	}

	data, err := json.Marshal(problem)
	if err != nil {
		t.Fatalf("Failed to marshal ProblemDetails: %v", err)
	}

	// Verify RFC 9457 standard fields
	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	// Check standard RFC 9457 fields
	if result["type"] != TypeValidation {
		t.Errorf("Expected type=%q, got %q", TypeValidation, result["type"])
	}
	if result["title"] != TitleValidation {
		t.Errorf("Expected title=%q, got %q", TitleValidation, result["title"])
	}
	if result["status"] != float64(http.StatusBadRequest) {
		t.Errorf("Expected status=%d, got %v", http.StatusBadRequest, result["status"])
	}
	if result["detail"] != "Field validation failed" {
		t.Errorf("Expected detail=%q, got %q", "Field validation failed", result["detail"])
	}
	if result["instance"] != "/api/v1/events/123" {
		t.Errorf("Expected instance=%q, got %q", "/api/v1/events/123", result["instance"])
	}

	// Check extension fields
	if result["request_id"] != "req-abc123" {
		t.Errorf("Expected request_id=%q, got %q", "req-abc123", result["request_id"])
	}
	if result["user_message"] != "Please fix the errors" {
		t.Errorf("Expected user_message=%q, got %q", "Please fix the errors", result["user_message"])
	}
	if result["retry_after"] != float64(60) {
		t.Errorf("Expected retry_after=%d, got %v", 60, result["retry_after"])
	}
	if result["action"] != "fix_validation" {
		t.Errorf("Expected action=%q, got %q", "fix_validation", result["action"])
	}

	// Check errors array
	errors, ok := result["errors"].([]interface{})
	if !ok || len(errors) != 2 {
		t.Errorf("Expected 2 errors, got %v", result["errors"])
	}
}

func TestProblemDetailsJSONOmitsEmpty(t *testing.T) {
	// Minimal problem - should omit empty fields
	problem := &ProblemDetails{
		Type:   TypeInternal,
		Title:  TitleInternal,
		Status: http.StatusInternalServerError,
	}

	data, err := json.Marshal(problem)
	if err != nil {
		t.Fatalf("Failed to marshal ProblemDetails: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	// These fields should be omitted (not present) when empty
	omittedFields := []string{"detail", "instance", "request_id", "user_message", "retry_after", "action", "errors"}
	for _, field := range omittedFields {
		if _, exists := result[field]; exists {
			t.Errorf("Expected field %q to be omitted when empty, but it was present", field)
		}
	}

	// Required fields should always be present
	requiredFields := []string{"type", "title", "status"}
	for _, field := range requiredFields {
		if _, exists := result[field]; !exists {
			t.Errorf("Expected required field %q to be present", field)
		}
	}
}

func TestWriteProblemContentType(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	problem := NewInternalError("req-123")
	WriteProblem(c, problem)

	contentType := w.Header().Get("Content-Type")
	if contentType != ContentTypeProblemJSON {
		t.Errorf("Expected Content-Type=%q, got %q", ContentTypeProblemJSON, contentType)
	}
}

func TestWriteProblemRetryAfter(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	problem := NewRateLimitError("req-456", 120)
	WriteProblem(c, problem)

	// Check header
	retryAfterHeader := w.Header().Get("Retry-After")
	if retryAfterHeader != "120" {
		t.Errorf("Expected Retry-After header=%q, got %q", "120", retryAfterHeader)
	}

	// Check body field
	var result map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("Failed to unmarshal response body: %v", err)
	}

	if result["retry_after"] != float64(120) {
		t.Errorf("Expected retry_after in body=%d, got %v", 120, result["retry_after"])
	}
}

func TestWriteProblemNoRetryAfterWhenNil(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	problem := NewInternalError("req-789")
	WriteProblem(c, problem)

	retryAfterHeader := w.Header().Get("Retry-After")
	if retryAfterHeader != "" {
		t.Errorf("Expected no Retry-After header, got %q", retryAfterHeader)
	}
}

func TestNewValidationErrorMultipleFields(t *testing.T) {
	errors := []FieldError{
		{Field: "name", Message: "is required", Code: "required"},
		{Field: "email", Message: "must be valid email", Code: "invalid_email"},
		{Field: "timestamp", Message: "must be in the past", Code: "future_timestamp"},
	}

	problem := NewValidationError("req-abc", errors)

	if problem.Type != TypeValidation {
		t.Errorf("Expected type=%q, got %q", TypeValidation, problem.Type)
	}
	if problem.Status != http.StatusBadRequest {
		t.Errorf("Expected status=%d, got %d", http.StatusBadRequest, problem.Status)
	}
	if len(problem.Errors) != 3 {
		t.Errorf("Expected 3 field errors, got %d", len(problem.Errors))
	}

	// Verify all errors are included, not just the first
	fieldNames := make(map[string]bool)
	for _, e := range problem.Errors {
		fieldNames[e.Field] = true
	}
	if !fieldNames["name"] || !fieldNames["email"] || !fieldNames["timestamp"] {
		t.Errorf("Not all field errors were included: %v", fieldNames)
	}
}

func TestNewInternalErrorHidesDetails(t *testing.T) {
	problem := NewInternalError("req-xyz")

	// Should not contain any sensitive information
	if problem.Detail == "" {
		t.Error("Expected a generic detail message, got empty string")
	}

	// The detail should be generic, not exposing internal error information
	expectedDetail := "An unexpected error occurred"
	if problem.Detail != expectedDetail {
		t.Errorf("Expected detail=%q, got %q", expectedDetail, problem.Detail)
	}

	// Should have user-friendly message
	if problem.UserMessage == "" {
		t.Error("Expected user_message to be set")
	}
}

func TestNewNotFoundError(t *testing.T) {
	problem := NewNotFoundError("req-123", "Event", "evt-456")

	if problem.Type != TypeNotFound {
		t.Errorf("Expected type=%q, got %q", TypeNotFound, problem.Type)
	}
	if problem.Status != http.StatusNotFound {
		t.Errorf("Expected status=%d, got %d", http.StatusNotFound, problem.Status)
	}
	if problem.Detail != "Event with ID 'evt-456' was not found" {
		t.Errorf("Unexpected detail: %q", problem.Detail)
	}
}

func TestNewRateLimitError(t *testing.T) {
	problem := NewRateLimitError("req-789", 60)

	if problem.Type != TypeRateLimit {
		t.Errorf("Expected type=%q, got %q", TypeRateLimit, problem.Type)
	}
	if problem.Status != http.StatusTooManyRequests {
		t.Errorf("Expected status=%d, got %d", http.StatusTooManyRequests, problem.Status)
	}
	if problem.RetryAfter == nil || *problem.RetryAfter != 60 {
		t.Errorf("Expected retry_after=60, got %v", problem.RetryAfter)
	}
}

func TestNewUnauthorizedError(t *testing.T) {
	problem := NewUnauthorizedError("req-abc")

	if problem.Type != TypeUnauthorized {
		t.Errorf("Expected type=%q, got %q", TypeUnauthorized, problem.Type)
	}
	if problem.Status != http.StatusUnauthorized {
		t.Errorf("Expected status=%d, got %d", http.StatusUnauthorized, problem.Status)
	}
	if problem.Action != "authenticate" {
		t.Errorf("Expected action=%q, got %q", "authenticate", problem.Action)
	}
}

func TestNewForbiddenError(t *testing.T) {
	problem := NewForbiddenError("req-def")

	if problem.Type != TypeForbidden {
		t.Errorf("Expected type=%q, got %q", TypeForbidden, problem.Type)
	}
	if problem.Status != http.StatusForbidden {
		t.Errorf("Expected status=%d, got %d", http.StatusForbidden, problem.Status)
	}
}

func TestNewInvalidUUIDError(t *testing.T) {
	problem := NewInvalidUUIDError("req-ghi", "event_id", "not-a-uuid")

	if problem.Type != TypeInvalidUUID {
		t.Errorf("Expected type=%q, got %q", TypeInvalidUUID, problem.Type)
	}
	if problem.Status != http.StatusBadRequest {
		t.Errorf("Expected status=%d, got %d", http.StatusBadRequest, problem.Status)
	}
	if len(problem.Errors) != 1 {
		t.Errorf("Expected 1 field error, got %d", len(problem.Errors))
	}
	if problem.Errors[0].Field != "event_id" {
		t.Errorf("Expected error field=%q, got %q", "event_id", problem.Errors[0].Field)
	}
}

func TestNewFutureTimestampError(t *testing.T) {
	problem := NewFutureTimestampError("req-jkl", "timestamp")

	if problem.Type != TypeFutureTimestamp {
		t.Errorf("Expected type=%q, got %q", TypeFutureTimestamp, problem.Type)
	}
	if problem.Status != http.StatusBadRequest {
		t.Errorf("Expected status=%d, got %d", http.StatusBadRequest, problem.Status)
	}
	if len(problem.Errors) != 1 {
		t.Errorf("Expected 1 field error, got %d", len(problem.Errors))
	}
}

func TestProblemDetailsError(t *testing.T) {
	// Test Error() with detail
	p1 := &ProblemDetails{
		Type:   TypeValidation,
		Title:  TitleValidation,
		Detail: "Custom error message",
	}
	if p1.Error() != "Custom error message" {
		t.Errorf("Expected Error()=%q, got %q", "Custom error message", p1.Error())
	}

	// Test Error() without detail (falls back to title)
	p2 := &ProblemDetails{
		Type:  TypeValidation,
		Title: TitleValidation,
	}
	if p2.Error() != TitleValidation {
		t.Errorf("Expected Error()=%q, got %q", TitleValidation, p2.Error())
	}
}

func TestGetRequestID(t *testing.T) {
	// Test with request_id in gin context
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Set("request_id", "ctx-req-123")

	requestID := GetRequestID(c)
	if requestID != "ctx-req-123" {
		t.Errorf("Expected request_id=%q, got %q", "ctx-req-123", requestID)
	}

	// Test with X-Request-ID header fallback
	c2, _ := gin.CreateTestContext(httptest.NewRecorder())
	c2.Request = httptest.NewRequest("GET", "/test", nil)
	c2.Request.Header.Set("X-Request-ID", "header-req-456")

	requestID2 := GetRequestID(c2)
	if requestID2 != "header-req-456" {
		t.Errorf("Expected request_id from header=%q, got %q", "header-req-456", requestID2)
	}

	// Test with neither (returns empty)
	c3, _ := gin.CreateTestContext(httptest.NewRecorder())
	c3.Request = httptest.NewRequest("GET", "/test", nil)

	requestID3 := GetRequestID(c3)
	if requestID3 != "" {
		t.Errorf("Expected empty request_id, got %q", requestID3)
	}
}

func TestNewServiceUnavailableError(t *testing.T) {
	problem := NewServiceUnavailableError("req-mno", 300)

	if problem.Status != http.StatusServiceUnavailable {
		t.Errorf("Expected status=%d, got %d", http.StatusServiceUnavailable, problem.Status)
	}
	if problem.RetryAfter == nil || *problem.RetryAfter != 300 {
		t.Errorf("Expected retry_after=300, got %v", problem.RetryAfter)
	}
}
