package main

import (
	"fmt"
	"log"

	"github.com/JonnyWalker81/trendy/backend/internal/config"
	"github.com/JonnyWalker81/trendy/backend/internal/handlers"
	"github.com/JonnyWalker81/trendy/backend/internal/middleware"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
	"github.com/gin-gonic/gin"
	"github.com/spf13/cobra"
)

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start the API server",
	Long:  `Start the HTTP API server and listen for requests.`,
	RunE:  runServe,
}

var (
	port string
)

func init() {
	serveCmd.Flags().StringVarP(&port, "port", "p", "", "Port to listen on (overrides config)")
}

func runServe(cmd *cobra.Command, args []string) error {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}

	// Override port from flag if provided
	if port != "" {
		cfg.Server.Port = port
	}

	log.Printf("Starting Trendy API server in %s mode", cfg.Server.Env)
	log.Printf("Supabase URL: %s", cfg.Supabase.URL)

	// Initialize Supabase client
	supabaseClient := supabase.NewClient(cfg.Supabase.URL, cfg.Supabase.ServiceKey)

	// Initialize repositories
	eventRepo := repository.NewEventRepository(supabaseClient)
	eventTypeRepo := repository.NewEventTypeRepository(supabaseClient)
	userRepo := repository.NewUserRepository(supabaseClient)

	// Initialize services
	eventService := service.NewEventService(eventRepo, eventTypeRepo)
	eventTypeService := service.NewEventTypeService(eventTypeRepo)
	analyticsService := service.NewAnalyticsService(eventRepo)
	authService := service.NewAuthService(supabaseClient, userRepo)

	// Initialize handlers
	eventHandler := handlers.NewEventHandler(eventService)
	eventTypeHandler := handlers.NewEventTypeHandler(eventTypeService)
	analyticsHandler := handlers.NewAnalyticsHandler(analyticsService)
	authHandler := handlers.NewAuthHandler(authService)

	// Set Gin mode based on environment
	if cfg.Server.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize Gin router
	router := gin.Default()

	// Middleware
	router.Use(middleware.CORS())
	router.Use(middleware.Logger())

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "ok",
			"env":    cfg.Server.Env,
		})
	})

	// API v1 routes
	v1 := router.Group("/api/v1")
	{
		// Auth routes
		auth := v1.Group("/auth")
		{
			auth.POST("/login", authHandler.Login)
			auth.POST("/signup", authHandler.Signup)
			auth.POST("/logout", authHandler.Logout)
			auth.GET("/me", middleware.Auth(supabaseClient), authHandler.Me)
		}

		// Protected routes
		protected := v1.Group("")
		protected.Use(middleware.Auth(supabaseClient))
		{
			// Event routes
			protected.GET("/events", eventHandler.GetEvents)
			protected.POST("/events", eventHandler.CreateEvent)
			protected.GET("/events/:id", eventHandler.GetEvent)
			protected.PUT("/events/:id", eventHandler.UpdateEvent)
			protected.DELETE("/events/:id", eventHandler.DeleteEvent)

			// Event type routes
			protected.GET("/event-types", eventTypeHandler.GetEventTypes)
			protected.POST("/event-types", eventTypeHandler.CreateEventType)
			protected.GET("/event-types/:id", eventTypeHandler.GetEventType)
			protected.PUT("/event-types/:id", eventTypeHandler.UpdateEventType)
			protected.DELETE("/event-types/:id", eventTypeHandler.DeleteEventType)

			// Analytics routes
			protected.GET("/analytics/summary", analyticsHandler.GetSummary)
			protected.GET("/analytics/trends", analyticsHandler.GetTrends)
			protected.GET("/analytics/event-type/:id", analyticsHandler.GetEventTypeAnalytics)
		}
	}

	log.Printf("Server listening on port %s", cfg.Server.Port)
	if err := router.Run(":" + cfg.Server.Port); err != nil {
		return fmt.Errorf("failed to start server: %w", err)
	}

	return nil
}
