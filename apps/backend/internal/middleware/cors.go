package middleware

import (
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

// CORS middleware to handle cross-origin requests
// Reads CORS_ALLOWED_ORIGINS environment variable to restrict origins
// If not set, defaults to "*" (allow all origins)
func CORS() gin.HandlerFunc {
	// Read allowed origins from environment variable
	allowedOriginsStr := os.Getenv("CORS_ALLOWED_ORIGINS")
	allowAll := allowedOriginsStr == ""

	// Parse comma-separated origins
	var allowedOrigins []string
	if !allowAll {
		allowedOrigins = strings.Split(allowedOriginsStr, ",")
		for i, origin := range allowedOrigins {
			allowedOrigins[i] = strings.TrimSpace(origin)
		}
	}

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		// Determine if this origin is allowed
		if allowAll {
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		} else {
			// Check if the request origin is in the allowed list
			allowed := false
			for _, allowedOrigin := range allowedOrigins {
				if origin == allowedOrigin {
					allowed = true
					break
				}
			}

			if allowed {
				c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
				c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
			} else {
				// Origin not allowed, but still need to set headers for preflight
				if c.Request.Method == "OPTIONS" {
					c.AbortWithStatus(403)
					return
				}
			}
		}

		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}
