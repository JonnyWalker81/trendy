package middleware

import (
	"net/url"
	"os"
	"strings"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/gin-gonic/gin"
)

// CORS middleware to handle cross-origin requests
// Reads CORS_ALLOWED_ORIGINS environment variable to restrict origins
// In production, CORS_ALLOWED_ORIGINS must be explicitly set
// In development (TRENDY_SERVER_ENV != "production"), defaults to localhost origins
func CORS() gin.HandlerFunc {
	log := logger.Default()

	// Read allowed origins from environment variable
	allowedOriginsStr := os.Getenv("CORS_ALLOWED_ORIGINS")
	serverEnv := os.Getenv("TRENDY_SERVER_ENV")
	isProduction := serverEnv == "production"

	// Security: In production, CORS_ALLOWED_ORIGINS must be explicitly configured
	if allowedOriginsStr == "" {
		if isProduction {
			log.Error("CORS configuration error: CORS_ALLOWED_ORIGINS must be set in production",
				logger.String("required", "comma-separated list of allowed origins"),
			)
			// Fatal - cannot start server without proper CORS config in production
			panic("SECURITY ERROR: CORS_ALLOWED_ORIGINS must be set in production")
		}
		// Development-only fallback - allow common local development origins
		allowedOriginsStr = "http://localhost:3000,http://localhost:5173,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:5173"
		log.Info("CORS using development defaults",
			logger.String("env", serverEnv),
			logger.String("origins", allowedOriginsStr),
		)
	}

	// Parse and validate comma-separated origins
	var allowedOrigins []string
	for _, origin := range strings.Split(allowedOriginsStr, ",") {
		origin = strings.TrimSpace(origin)
		if origin == "" {
			continue
		}
		// Validate that each origin is a proper URL
		if origin == "*" {
			if isProduction {
				log.Error("CORS configuration error: wildcard origin not allowed in production")
				panic("SECURITY ERROR: Wildcard '*' origin is not allowed in production")
			}
			log.Warn("CORS wildcard origin configured - insecure, use only in development")
		}
		if _, err := url.Parse(origin); err != nil {
			log.Error("CORS configuration error: invalid origin URL",
				logger.String("origin", origin),
				logger.Err(err),
			)
			panic("CORS ERROR: Invalid origin URL: " + origin)
		}
		// Warn about HTTP origins in production
		if isProduction && strings.HasPrefix(origin, "http://") {
			log.Warn("CORS HTTP origin in production - consider using HTTPS",
				logger.String("origin", origin),
			)
		}
		allowedOrigins = append(allowedOrigins, origin)
	}

	if len(allowedOrigins) == 0 {
		log.Error("CORS configuration error: no valid origins configured")
		panic("CORS ERROR: No valid origins configured")
	}

	log.Info("CORS middleware initialized",
		logger.Int("allowed_origins_count", len(allowedOrigins)),
		logger.Bool("is_production", isProduction),
	)

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

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
		} else if origin != "" {
			// Origin not allowed - reject preflight, log for non-preflight
			reqLog := logger.FromContext(c.Request.Context())
			if c.Request.Method == "OPTIONS" {
				reqLog.Debug("CORS preflight rejected: origin not allowed",
					logger.String("origin", origin),
				)
				c.AbortWithStatus(403)
				return
			}
			// For non-preflight requests from disallowed origins, don't set CORS headers
			// The browser will block the response anyway
			reqLog.Debug("CORS request from disallowed origin",
				logger.String("origin", origin),
			)
		}
		// If no Origin header, this is likely a same-origin or non-browser request - allow it

		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With, X-Request-ID")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")
		c.Writer.Header().Set("Access-Control-Expose-Headers", "X-Request-ID")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}
