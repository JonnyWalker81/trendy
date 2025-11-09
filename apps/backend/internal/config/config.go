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

	// Read from environment variables
	v.SetEnvPrefix("TRENDY")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	// Also bind to non-prefixed environment variables for backward compatibility
	v.BindEnv("server.port", "PORT")
	v.BindEnv("supabase.url", "SUPABASE_URL")
	v.BindEnv("supabase.service_key", "SUPABASE_SERVICE_KEY")

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
