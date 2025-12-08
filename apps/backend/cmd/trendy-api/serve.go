package main

import (
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/config"
	"github.com/JonnyWalker81/trendy/backend/internal/handlers"
	"github.com/JonnyWalker81/trendy/backend/internal/logger"
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

	// Initialize structured logger
	log := logger.NewSlogLogger(logger.Config{
		Level:     logger.ParseLevel(cfg.LogLevelForEnv()),
		Format:    cfg.Logging.Format,
		LogBodies: cfg.Logging.LogBodies,
		AddSource: cfg.Logging.AddSource,
	})
	logger.SetDefault(log)

	log.Info("starting Trendy API server",
		logger.String("env", cfg.Server.Env),
		logger.String("log_level", cfg.LogLevelForEnv()),
		logger.String("log_format", cfg.Logging.Format),
	)
	log.Debug("supabase configuration",
		logger.String("url", cfg.Supabase.URL),
	)

	// Initialize Supabase client
	supabaseClient := supabase.NewClient(cfg.Supabase.URL, cfg.Supabase.ServiceKey)

	// Initialize repositories
	eventRepo := repository.NewEventRepository(supabaseClient)
	eventTypeRepo := repository.NewEventTypeRepository(supabaseClient)
	userRepo := repository.NewUserRepository(supabaseClient)
	propertyDefRepo := repository.NewPropertyDefinitionRepository(supabaseClient)
	geofenceRepo := repository.NewGeofenceRepository(supabaseClient)
	insightRepo := repository.NewInsightRepository(supabaseClient)
	aggregateRepo := repository.NewDailyAggregateRepository(supabaseClient)
	streakRepo := repository.NewStreakRepository(supabaseClient)

	// Initialize services
	eventService := service.NewEventService(eventRepo, eventTypeRepo)
	eventTypeService := service.NewEventTypeService(eventTypeRepo)
	analyticsService := service.NewAnalyticsService(eventRepo)
	authService := service.NewAuthService(supabaseClient, userRepo)
	propertyDefService := service.NewPropertyDefinitionService(propertyDefRepo, eventTypeRepo)
	geofenceService := service.NewGeofenceService(geofenceRepo)
	intelligenceService := service.NewIntelligenceService(eventRepo, eventTypeRepo, insightRepo, aggregateRepo, streakRepo)

	// Initialize handlers
	eventHandler := handlers.NewEventHandler(eventService)
	eventTypeHandler := handlers.NewEventTypeHandler(eventTypeService)
	analyticsHandler := handlers.NewAnalyticsHandler(analyticsService)
	authHandler := handlers.NewAuthHandler(authService)
	propertyDefHandler := handlers.NewPropertyDefinitionHandler(propertyDefService)
	geofenceHandler := handlers.NewGeofenceHandler(geofenceService)
	insightsHandler := handlers.NewInsightsHandler(intelligenceService)

	// Set Gin mode based on environment
	if cfg.Server.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize Gin router
	router := gin.Default()

	// Global middleware
	router.Use(middleware.SecurityHeaders()) // Security headers on all responses
	router.Use(middleware.CORS())
	router.Use(middleware.Logger())
	router.Use(middleware.RateLimit()) // General rate limit: 100 req/min

	// Health check (no rate limit needed)
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "ok",
			"env":    cfg.Server.Env,
		})
	})

	// API v1 routes
	v1 := router.Group("/api/v1")
	{
		// Auth routes - stricter rate limiting to prevent brute force
		auth := v1.Group("/auth")
		auth.Use(middleware.RateLimitAuth()) // Auth rate limit: 10 req/min
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
			protected.GET("/events/export", eventHandler.ExportEvents)
			protected.POST("/events", eventHandler.CreateEvent)
			protected.POST("/events/batch", eventHandler.CreateEventsBatch)
			protected.GET("/events/:id", eventHandler.GetEvent)
			protected.PUT("/events/:id", eventHandler.UpdateEvent)
			protected.DELETE("/events/:id", eventHandler.DeleteEvent)

			// Event type routes
			protected.GET("/event-types", eventTypeHandler.GetEventTypes)
			protected.POST("/event-types", eventTypeHandler.CreateEventType)
			protected.GET("/event-types/:id", eventTypeHandler.GetEventType)
			protected.PUT("/event-types/:id", eventTypeHandler.UpdateEventType)
			protected.DELETE("/event-types/:id", eventTypeHandler.DeleteEventType)

			// Property definition routes
			protected.GET("/event-types/:id/properties", propertyDefHandler.GetPropertyDefinitionsByEventType)
			protected.POST("/event-types/:id/properties", propertyDefHandler.CreatePropertyDefinition)
			protected.GET("/property-definitions/:id", propertyDefHandler.GetPropertyDefinition)
			protected.PUT("/property-definitions/:id", propertyDefHandler.UpdatePropertyDefinition)
			protected.DELETE("/property-definitions/:id", propertyDefHandler.DeletePropertyDefinition)

			// Analytics routes
			protected.GET("/analytics/summary", analyticsHandler.GetSummary)
			protected.GET("/analytics/trends", analyticsHandler.GetTrends)
			protected.GET("/analytics/event-type/:id", analyticsHandler.GetEventTypeAnalytics)

			// Geofence routes
			protected.GET("/geofences", geofenceHandler.GetGeofences)
			protected.POST("/geofences", geofenceHandler.CreateGeofence)
			protected.GET("/geofences/:id", geofenceHandler.GetGeofence)
			protected.PUT("/geofences/:id", geofenceHandler.UpdateGeofence)
			protected.DELETE("/geofences/:id", geofenceHandler.DeleteGeofence)

			// Insights/Intelligence routes
			protected.GET("/insights", insightsHandler.GetInsights)
			protected.GET("/insights/correlations", insightsHandler.GetCorrelations)
			protected.GET("/insights/streaks", insightsHandler.GetStreaks)
			protected.GET("/insights/weekly-summary", insightsHandler.GetWeeklySummary)
			protected.POST("/insights/refresh", insightsHandler.RefreshInsights)
		}
	}

	log.Info("server listening",
		logger.String("port", cfg.Server.Port),
		logger.String("address", ":"+cfg.Server.Port),
	)
	if err := router.Run(":" + cfg.Server.Port); err != nil {
		return fmt.Errorf("failed to start server: %w", err)
	}

	return nil
}
