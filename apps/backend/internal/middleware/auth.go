package middleware

import (
	"strings"

	"github.com/JonnyWalker81/trendy/backend/internal/apierror"
	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
	"github.com/gin-gonic/gin"
)

// Auth middleware to verify JWT tokens
func Auth(client *supabase.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		log := logger.FromContext(c.Request.Context())

		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			log.Debug("authentication failed: missing authorization header")
			requestID := apierror.GetRequestID(c)
			apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
			c.Abort()
			return
		}

		// Extract token from "Bearer <token>"
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			log.Debug("authentication failed: invalid authorization format")
			requestID := apierror.GetRequestID(c)
			apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
			c.Abort()
			return
		}

		token := parts[1]

		// Verify token with Supabase
		user, err := client.VerifyToken(token)
		if err != nil {
			log.Warn("authentication failed: token verification error",
				logger.Err(err),
			)
			requestID := apierror.GetRequestID(c)
			apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
			c.Abort()
			return
		}

		// Set user in context
		c.Set("user_id", user.ID)
		c.Set("user_email", user.Email)
		c.Set("user_token", token) // Store JWT token for RLS

		// Add user ID to request context for logging
		ctx := logger.WithUserID(c.Request.Context(), user.ID)
		c.Request = c.Request.WithContext(ctx)

		log.Debug("authentication successful",
			logger.String("user_id", user.ID),
			logger.String("user_email", user.Email),
		)

		c.Next()
	}
}
