package apierror

// Error type URIs following the urn:trendy:error:* pattern.
// These are used as the "type" field in RFC 9457 Problem Details.
const (
	// TypeValidation indicates request validation failed (400)
	TypeValidation = "urn:trendy:error:validation"

	// TypeNotFound indicates the requested resource was not found (404)
	TypeNotFound = "urn:trendy:error:not_found"

	// TypeConflict indicates a resource conflict (409)
	TypeConflict = "urn:trendy:error:conflict"

	// TypeRateLimit indicates too many requests (429)
	TypeRateLimit = "urn:trendy:error:rate_limit"

	// TypeUnauthorized indicates missing or invalid authentication (401)
	TypeUnauthorized = "urn:trendy:error:unauthorized"

	// TypeForbidden indicates insufficient permissions (403)
	TypeForbidden = "urn:trendy:error:forbidden"

	// TypeInternal indicates an unexpected server error (500)
	TypeInternal = "urn:trendy:error:internal"

	// TypeInvalidUUID indicates an invalid UUID format in request (400)
	TypeInvalidUUID = "urn:trendy:error:invalid_uuid"

	// TypeFutureTimestamp indicates a timestamp too far in the future (400)
	TypeFutureTimestamp = "urn:trendy:error:future_timestamp"

	// TypeBadRequest indicates a malformed or invalid request (400)
	TypeBadRequest = "urn:trendy:error:bad_request"
)

// Titles for each error type - human-readable summaries
const (
	TitleValidation       = "Validation Error"
	TitleNotFound         = "Resource Not Found"
	TitleConflict         = "Resource Conflict"
	TitleRateLimit        = "Rate Limit Exceeded"
	TitleUnauthorized     = "Authentication Required"
	TitleForbidden        = "Permission Denied"
	TitleInternal         = "Internal Server Error"
	TitleInvalidUUID      = "Invalid UUID Format"
	TitleFutureTimestamp  = "Future Timestamp Not Allowed"
	TitleBadRequest       = "Bad Request"
)
