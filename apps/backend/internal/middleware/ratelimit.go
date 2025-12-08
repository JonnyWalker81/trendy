package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/gin-gonic/gin"
)

// RateLimiter provides request rate limiting per IP address
type RateLimiter struct {
	requests map[string]*clientInfo
	mu       sync.RWMutex
	rate     int           // requests per window
	window   time.Duration // time window
	name     string        // identifier for logging
}

type clientInfo struct {
	count    int
	lastSeen time.Time
}

// NewRateLimiter creates a new rate limiter
// rate: maximum requests allowed per window
// window: time window for rate limiting
// name: identifier for logging (e.g., "general", "auth", "strict")
func NewRateLimiter(rate int, window time.Duration, name string) *RateLimiter {
	rl := &RateLimiter{
		requests: make(map[string]*clientInfo),
		rate:     rate,
		window:   window,
		name:     name,
	}

	// Start cleanup goroutine to prevent memory leaks
	go rl.cleanup()

	logger.Default().Debug("rate limiter initialized",
		logger.String("name", name),
		logger.Int("rate", rate),
		logger.Duration("window", window),
	)

	return rl
}

// cleanup removes stale entries periodically
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(rl.window * 2)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		cleaned := 0
		for ip, info := range rl.requests {
			if now.Sub(info.lastSeen) > rl.window*2 {
				delete(rl.requests, ip)
				cleaned++
			}
		}
		remaining := len(rl.requests)
		rl.mu.Unlock()

		if cleaned > 0 {
			logger.Default().Debug("rate limiter cleanup completed",
				logger.String("name", rl.name),
				logger.Int("cleaned", cleaned),
				logger.Int("remaining", remaining),
			)
		}
	}
}

// isAllowed checks if a request from the given IP is allowed
func (rl *RateLimiter) isAllowed(ip string) (bool, int) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	info, exists := rl.requests[ip]

	if !exists {
		rl.requests[ip] = &clientInfo{count: 1, lastSeen: now}
		return true, 1
	}

	// Reset count if window has passed
	if now.Sub(info.lastSeen) > rl.window {
		info.count = 1
		info.lastSeen = now
		return true, 1
	}

	// Increment count
	info.count++
	info.lastSeen = now

	return info.count <= rl.rate, info.count
}

// RateLimit returns a middleware handler that limits requests per IP
// Default: 300 requests per minute for general endpoints
// Increased from 100 to support iOS full-sync with many events
func RateLimit() gin.HandlerFunc {
	limiter := NewRateLimiter(300, time.Minute, "general")
	return rateLimitMiddleware(limiter)
}

// RateLimitAuth returns a stricter rate limiter for authentication endpoints
// Default: 10 requests per minute to prevent brute force attacks
func RateLimitAuth() gin.HandlerFunc {
	limiter := NewRateLimiter(10, time.Minute, "auth")
	return rateLimitMiddleware(limiter)
}

// RateLimitStrict returns an even stricter rate limiter
// Default: 5 requests per minute for sensitive operations like password reset
func RateLimitStrict() gin.HandlerFunc {
	limiter := NewRateLimiter(5, time.Minute, "strict")
	return rateLimitMiddleware(limiter)
}

// rateLimitMiddleware creates the actual middleware handler
func rateLimitMiddleware(limiter *RateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get client IP (handles X-Forwarded-For for reverse proxies)
		ip := c.ClientIP()

		allowed, count := limiter.isAllowed(ip)
		if !allowed {
			log := logger.FromContext(c.Request.Context())
			log.Warn("rate limit exceeded",
				logger.String("limiter", limiter.name),
				logger.String("client_ip", ip),
				logger.Int("request_count", count),
				logger.Int("limit", limiter.rate),
				logger.Duration("window", limiter.window),
			)

			c.Header("Retry-After", "60")
			c.Header("X-RateLimit-Limit", string(rune(limiter.rate)))
			c.Header("X-RateLimit-Remaining", "0")
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}
