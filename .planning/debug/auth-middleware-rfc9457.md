---
status: diagnosed
trigger: "Auth middleware not using RFC 9457 error format"
created: 2026-01-17T12:00:00Z
updated: 2026-01-17T12:01:00Z
symptoms_prefilled: true
goal: find_root_cause_only
---

## Current Focus

hypothesis: CONFIRMED - Auth middleware uses c.JSON() with gin.H{"error": ...} instead of apierror.WriteProblem()
test: Compared auth.go to apierror/response.go
expecting: Found 3 c.JSON() calls with legacy format
next_action: Report root cause

## Symptoms

expected: Auth errors return RFC 9457 format {"type":"urn:trendy:error:unauthorized","title":"Unauthorized","status":401,"detail":"...","request_id":"..."}
actual: Auth errors return {"error":"Authorization header required"}
errors: None - just wrong format
reproduction: Call any protected endpoint without Authorization header
started: Since auth middleware was created (before apierror package existed)

## Eliminated

## Evidence

- timestamp: 2026-01-17T12:00:30Z
  checked: apps/backend/internal/middleware/auth.go
  found: |
    Three error responses using legacy format:
    Line 20: c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
    Line 29: c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
    Line 42: c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
  implication: Middleware was written before apierror package existed

- timestamp: 2026-01-17T12:00:45Z
  checked: apps/backend/internal/apierror/response.go
  found: |
    NewUnauthorizedError() function exists (lines 119-130)
    WriteProblem() function exists to write RFC 9457 responses
    GetRequestID() helper exists to extract request_id from context
  implication: All tools needed for fix already exist in apierror package

## Resolution

root_cause: Auth middleware uses legacy c.JSON(http.StatusUnauthorized, gin.H{"error": ...}) instead of apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
fix: Replace 3 c.JSON() calls in auth.go with apierror.WriteProblem() using NewUnauthorizedError()
verification:
files_changed: []
