package middleware

import (
	"sync"
	"testing"
	"time"
)

// TestRateLimiterConcurrentAccess verifies the rate limiter is safe under concurrent access.
// Run with: go test -race -count=1 ./internal/middleware/ -run TestRateLimiterConcurrentAccess
func TestRateLimiterConcurrentAccess(t *testing.T) {
	limiter := NewRateLimiter(100, time.Minute, "test-concurrent")

	var wg sync.WaitGroup
	// 50 goroutines each making 20 requests with varying IPs
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(goroutineID int) {
			defer wg.Done()
			for j := 0; j < 20; j++ {
				// Mix of same IP and different IPs to stress both paths
				ip := "192.168.1.1"
				if j%3 == 0 {
					ip = "10.0.0." + string(rune('0'+goroutineID%10))
				}
				allowed, count := limiter.isAllowed(ip)
				// Just use the values to prevent compiler optimizations
				_ = allowed
				_ = count
			}
		}(i)
	}
	wg.Wait()
}

// TestRateLimiterConcurrentWithCleanup verifies no race between request handling and cleanup.
func TestRateLimiterConcurrentWithCleanup(t *testing.T) {
	// Use a very short window so cleanup runs during the test
	limiter := NewRateLimiter(5, 50*time.Millisecond, "test-cleanup-race")

	var wg sync.WaitGroup
	// Hammer the limiter while cleanup goroutine is running
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for j := 0; j < 50; j++ {
				ip := "10.0.0." + string(rune('0'+id%10))
				limiter.isAllowed(ip)
				// Small sleep to let cleanup goroutine interleave
				if j%10 == 0 {
					time.Sleep(time.Millisecond)
				}
			}
		}(i)
	}
	wg.Wait()
}
