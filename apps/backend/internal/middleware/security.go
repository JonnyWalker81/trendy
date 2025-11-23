package middleware

import (
	"os"

	"github.com/gin-gonic/gin"
)

// SecurityHeaders adds security-related HTTP headers to all responses
// These headers help protect against common web vulnerabilities
func SecurityHeaders() gin.HandlerFunc {
	serverEnv := os.Getenv("TRENDY_SERVER_ENV")
	isProduction := serverEnv == "production"

	return func(c *gin.Context) {
		// Prevent MIME type sniffing
		// Stops browsers from trying to guess the MIME type
		c.Header("X-Content-Type-Options", "nosniff")

		// Prevent clickjacking attacks
		// Stops the page from being embedded in iframes on other domains
		c.Header("X-Frame-Options", "DENY")

		// Enable XSS filter in browsers (legacy, but still useful)
		c.Header("X-XSS-Protection", "1; mode=block")

		// Control how much referrer information is sent
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// Prevent caching of sensitive API responses
		c.Header("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate")
		c.Header("Pragma", "no-cache")
		c.Header("Expires", "0")

		// HTTP Strict Transport Security (HSTS)
		// Only set in production with HTTPS
		if isProduction {
			// max-age=31536000 (1 year), includeSubDomains
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}

		// Content Security Policy for API responses
		// APIs typically don't serve HTML, but this provides defense-in-depth
		c.Header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")

		// Permissions Policy (formerly Feature Policy)
		// Disable browser features that aren't needed for an API
		c.Header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")

		c.Next()
	}
}
