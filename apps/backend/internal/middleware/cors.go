package middleware

import (
	"net/url"
	"os"
	"strings"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/gin-gonic/gin"
)

// wildcardOrigin represents a wildcard subdomain pattern like https://*.example.com
type wildcardOrigin struct {
	scheme string // e.g., "https://"
	suffix string // e.g., ".example.com"
}

// matches checks if an origin matches this wildcard pattern
func (w wildcardOrigin) matches(origin string) bool {
	if !strings.HasPrefix(origin, w.scheme) {
		return false
	}
	// Extract the host part after the scheme
	host := strings.TrimPrefix(origin, w.scheme)
	// Must end with the suffix and have something before it (the subdomain)
	if !strings.HasSuffix(host, w.suffix) {
		return false
	}
	// Ensure there's actually a subdomain (not just the suffix itself)
	subdomain := strings.TrimSuffix(host, w.suffix)
	// Subdomain must not be empty and must not contain additional dots
	// (to prevent matching nested subdomains if not intended)
	return len(subdomain) > 0 && !strings.Contains(subdomain, ".")
}

// parseWildcardOrigin parses a wildcard origin pattern like https://*.example.com
// Returns nil if the pattern is not a valid wildcard origin
func parseWildcardOrigin(pattern string) *wildcardOrigin {
	// Must contain exactly one * and it must be in the subdomain position
	// Valid: https://*.example.com
	// Invalid: https://*, *.example.com, https://*.*.example.com

	if strings.Count(pattern, "*") != 1 {
		return nil
	}

	// Check for scheme
	var scheme string
	if strings.HasPrefix(pattern, "https://") {
		scheme = "https://"
	} else if strings.HasPrefix(pattern, "http://") {
		scheme = "http://"
	} else {
		return nil
	}

	rest := strings.TrimPrefix(pattern, scheme)

	// Must start with *. for wildcard subdomain
	if !strings.HasPrefix(rest, "*.") {
		return nil
	}

	// Extract the suffix (including the leading dot)
	suffix := strings.TrimPrefix(rest, "*")

	// Validate suffix is a reasonable domain
	if len(suffix) < 2 || !strings.Contains(suffix[1:], ".") {
		return nil // Need at least .x.y (e.g., .example.com)
	}

	return &wildcardOrigin{
		scheme: scheme,
		suffix: suffix,
	}
}

// CORS middleware to handle cross-origin requests
// Reads CORS_ALLOWED_ORIGINS environment variable to restrict origins
// In production, CORS_ALLOWED_ORIGINS must be explicitly set
// In development (TRENDY_SERVER_ENV != "production"), defaults to localhost origins
// Supports wildcard subdomain patterns like https://*.example.com
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
	// Separate exact origins from wildcard patterns
	var exactOrigins []string
	var wildcardOrigins []wildcardOrigin

	for _, origin := range strings.Split(allowedOriginsStr, ",") {
		origin = strings.TrimSpace(origin)
		if origin == "" {
			continue
		}

		// Check if this is a wildcard pattern
		if strings.Contains(origin, "*") {
			// Check for bare wildcard (allow all)
			if origin == "*" {
				if isProduction {
					log.Error("CORS configuration error: wildcard origin not allowed in production")
					panic("SECURITY ERROR: Wildcard '*' origin is not allowed in production")
				}
				log.Warn("CORS wildcard origin configured - insecure, use only in development")
				exactOrigins = append(exactOrigins, origin)
				continue
			}

			// Try to parse as wildcard subdomain pattern
			wildcard := parseWildcardOrigin(origin)
			if wildcard == nil {
				log.Error("CORS configuration error: invalid wildcard pattern",
					logger.String("pattern", origin),
					logger.String("expected_format", "https://*.example.com"),
				)
				panic("CORS ERROR: Invalid wildcard pattern: " + origin)
			}

			log.Info("CORS wildcard pattern configured",
				logger.String("pattern", origin),
				logger.String("scheme", wildcard.scheme),
				logger.String("suffix", wildcard.suffix),
			)
			wildcardOrigins = append(wildcardOrigins, *wildcard)
			continue
		}

		// Validate that each origin is a proper URL
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
		exactOrigins = append(exactOrigins, origin)
	}

	if len(exactOrigins) == 0 && len(wildcardOrigins) == 0 {
		log.Error("CORS configuration error: no valid origins configured")
		panic("CORS ERROR: No valid origins configured")
	}

	log.Info("CORS middleware initialized",
		logger.Int("exact_origins_count", len(exactOrigins)),
		logger.Int("wildcard_patterns_count", len(wildcardOrigins)),
		logger.Bool("is_production", isProduction),
	)

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		// Check if the request origin is allowed
		allowed := false

		// Check exact matches first
		for _, allowedOrigin := range exactOrigins {
			if allowedOrigin == "*" || origin == allowedOrigin {
				allowed = true
				break
			}
		}

		// Check wildcard patterns if no exact match
		if !allowed {
			for _, wildcard := range wildcardOrigins {
				if wildcard.matches(origin) {
					allowed = true
					break
				}
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
