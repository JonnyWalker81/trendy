// Package apierror provides RFC 9457 Problem Details error response types
// for consistent API error handling across the trendy backend.
package apierror

// ProblemDetails represents an RFC 9457 Problem Details response.
// See https://www.rfc-editor.org/rfc/rfc9457.html
type ProblemDetails struct {
	// RFC 9457 standard fields
	Type     string `json:"type"`               // URI reference identifying the problem type
	Title    string `json:"title"`              // Short human-readable summary
	Status   int    `json:"status"`             // HTTP status code
	Detail   string `json:"detail,omitempty"`   // Human-readable explanation specific to this occurrence
	Instance string `json:"instance,omitempty"` // URI reference for this specific occurrence

	// Extension fields for trendy API
	RequestID   string       `json:"request_id,omitempty"`   // Correlation ID from X-Request-ID header
	UserMessage string       `json:"user_message,omitempty"` // UI-safe message for client display
	RetryAfter  *int         `json:"retry_after,omitempty"`  // Seconds until retry allowed (429, 503)
	Action      string       `json:"action,omitempty"`       // Client action hint: "refresh_token", "refresh_event_types"
	Errors      []FieldError `json:"errors,omitempty"`       // Validation errors list (multiple fields)
}

// FieldError represents a validation error for a specific field.
type FieldError struct {
	Field   string `json:"field"`          // Field name that failed validation
	Message string `json:"message"`        // Human-readable error message
	Code    string `json:"code,omitempty"` // Machine-readable error code
}

// Error implements the error interface for ProblemDetails.
func (p *ProblemDetails) Error() string {
	if p.Detail != "" {
		return p.Detail
	}
	return p.Title
}
