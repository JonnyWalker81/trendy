package config

import (
	"fmt"
	"strings"

	"github.com/spf13/viper"
)

// Config holds all configuration for the application
type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	Supabase SupabaseConfig `mapstructure:"supabase"`
	Logging  LoggingConfig  `mapstructure:"logging"`
}

// LoggingConfig holds logging-specific configuration
type LoggingConfig struct {
	// Level is the minimum log level: debug, info, warn, error
	Level string `mapstructure:"level"`
	// Format is the output format: json or text
	Format string `mapstructure:"format"`
	// LogBodies enables request/response body logging (security risk in production)
	LogBodies bool `mapstructure:"log_bodies"`
	// AddSource adds source file:line to log entries
	AddSource bool `mapstructure:"add_source"`
}

// ServerConfig holds server-specific configuration
type ServerConfig struct {
	Port string `mapstructure:"port"`
	Env  string `mapstructure:"env"`
}

// SupabaseConfig holds Supabase-specific configuration
type SupabaseConfig struct {
	URL        string `mapstructure:"url"`
	ServiceKey string `mapstructure:"service_key"`
}

// Load reads configuration from environment variables and config files
func Load() (*Config, error) {
	v := viper.New()

	// Set default values
	v.SetDefault("server.port", "8080")
	v.SetDefault("server.env", "development")
	v.SetDefault("logging.level", "info")
	v.SetDefault("logging.format", "json")
	v.SetDefault("logging.log_bodies", false)
	v.SetDefault("logging.add_source", false)

	// Read from environment variables
	v.SetEnvPrefix("TRENDY")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	// Also bind to non-prefixed environment variables for backward compatibility
	v.BindEnv("server.port", "PORT")
	v.BindEnv("supabase.url", "SUPABASE_URL")
	v.BindEnv("supabase.service_key", "SUPABASE_SERVICE_KEY")

	// Logging environment variables (TRENDY_ prefix via AutomaticEnv)
	// TRENDY_LOGGING_LEVEL, TRENDY_LOGGING_FORMAT, TRENDY_LOGGING_LOG_BODIES, TRENDY_LOGGING_ADD_SOURCE
	// Or use short names:
	v.BindEnv("logging.level", "LOG_LEVEL")
	v.BindEnv("logging.format", "LOG_FORMAT")
	v.BindEnv("logging.log_bodies", "LOG_BODIES")
	v.BindEnv("logging.add_source", "LOG_ADD_SOURCE")

	// Read from config file if it exists
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./config")

	// It's okay if config file doesn't exist
	if err := v.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("error reading config file: %w", err)
		}
	}

	var config Config
	if err := v.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("unable to decode config: %w", err)
	}

	// Validate required fields
	if err := config.Validate(); err != nil {
		return nil, err
	}

	return &config, nil
}

// Validate checks that all required configuration values are present
func (c *Config) Validate() error {
	if c.Supabase.URL == "" {
		return fmt.Errorf("SUPABASE_URL is required")
	}
	if c.Supabase.ServiceKey == "" {
		return fmt.Errorf("SUPABASE_SERVICE_KEY is required")
	}
	return nil
}

// LogLevelForEnv returns the appropriate log level based on the server environment
// if no explicit level is configured
func (c *Config) LogLevelForEnv() string {
	// If explicitly set, use that
	if c.Logging.Level != "" && c.Logging.Level != "info" {
		return c.Logging.Level
	}

	// Environment-based defaults
	switch c.Server.Env {
	case "development":
		return "debug"
	case "staging":
		return "info"
	case "production":
		return "warn"
	default:
		return "info"
	}
}

// IsProduction returns true if the server is running in production mode
func (c *Config) IsProduction() bool {
	return c.Server.Env == "production"
}
