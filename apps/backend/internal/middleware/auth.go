package middleware

import (
	"net/http"
	"strings"

	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
	"github.com/gin-gonic/gin"
)

// Auth middleware to verify JWT tokens
func Auth(client *supabase.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
			c.Abort()
			return
		}

		// Extract token from "Bearer <token>"
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
			c.Abort()
			return
		}

		token := parts[1]

		// Verify token with Supabase
		user, err := client.VerifyToken(token)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			c.Abort()
			return
		}

		// Set user in context
		c.Set("user_id", user.ID)
		c.Set("user_email", user.Email)
		c.Set("user_token", token) // Store JWT token for RLS

		c.Next()
	}
}
