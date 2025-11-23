// Package logger provides a structured logging abstraction that allows
// swapping underlying implementations (slog, zerolog, zap, etc.)
package logger

import (
	"context"
	"time"
)

// Level represents log severity levels
type Level int

const (
	LevelDebug Level = iota
	LevelInfo
	LevelWarn
	LevelError
)

// String returns the string representation of the log level
func (l Level) String() string {
	switch l {
	case LevelDebug:
		return "debug"
	case LevelInfo:
		return "info"
	case LevelWarn:
		return "warn"
	case LevelError:
		return "error"
	default:
		return "info"
	}
}

// ParseLevel converts a string to a Level
func ParseLevel(s string) Level {
	switch s {
	case "debug", "DEBUG":
		return LevelDebug
	case "info", "INFO":
		return LevelInfo
	case "warn", "WARN", "warning", "WARNING":
		return LevelWarn
	case "error", "ERROR":
		return LevelError
	default:
		return LevelInfo
	}
}

// Field represents a key-value pair for structured logging
type Field struct {
	Key   string
	Value any
}

// Helper functions to create fields with common types
func String(key, value string) Field {
	return Field{Key: key, Value: value}
}

func Int(key string, value int) Field {
	return Field{Key: key, Value: value}
}

func Int64(key string, value int64) Field {
	return Field{Key: key, Value: value}
}

func Float64(key string, value float64) Field {
	return Field{Key: key, Value: value}
}

func Bool(key string, value bool) Field {
	return Field{Key: key, Value: value}
}

func Duration(key string, value time.Duration) Field {
	return Field{Key: key, Value: value}
}

func Time(key string, value time.Time) Field {
	return Field{Key: key, Value: value}
}

func Err(err error) Field {
	if err == nil {
		return Field{Key: "error", Value: nil}
	}
	return Field{Key: "error", Value: err.Error()}
}

func Any(key string, value any) Field {
	return Field{Key: key, Value: value}
}

// Logger is the main logging interface that can be implemented by different
// logging backends (slog, zerolog, zap, etc.)
type Logger interface {
	// Debug logs a message at debug level
	Debug(msg string, fields ...Field)
	// Info logs a message at info level
	Info(msg string, fields ...Field)
	// Warn logs a message at warn level
	Warn(msg string, fields ...Field)
	// Error logs a message at error level
	Error(msg string, fields ...Field)

	// With returns a new Logger with the given fields added to all log entries
	With(fields ...Field) Logger
	// WithContext returns a new Logger that extracts context values (request_id, user_id)
	WithContext(ctx context.Context) Logger

	// Level returns the current log level
	Level() Level
}

// Config holds logging configuration
type Config struct {
	// Level is the minimum log level to output
	Level Level
	// Format is the output format: "json" or "text"
	Format string
	// LogBodies enables request/response body logging (use with caution)
	LogBodies bool
	// AddSource adds source file:line to log entries
	AddSource bool
}

// DefaultConfig returns a sensible default configuration
func DefaultConfig() Config {
	return Config{
		Level:     LevelInfo,
		Format:    "json",
		LogBodies: false,
		AddSource: false,
	}
}

// global default logger instance
var defaultLogger Logger

// SetDefault sets the default global logger
func SetDefault(l Logger) {
	defaultLogger = l
}

// Default returns the default global logger
func Default() Logger {
	if defaultLogger == nil {
		// Return a no-op logger if not initialized
		defaultLogger = NewSlogLogger(DefaultConfig())
	}
	return defaultLogger
}

// Convenience functions that use the default logger
func Debug(msg string, fields ...Field) { Default().Debug(msg, fields...) }
func Info(msg string, fields ...Field)  { Default().Info(msg, fields...) }
func Warn(msg string, fields ...Field)  { Default().Warn(msg, fields...) }
func Error(msg string, fields ...Field) { Default().Error(msg, fields...) }
func With(fields ...Field) Logger       { return Default().With(fields...) }
func WithContext(ctx context.Context) Logger {
	return Default().WithContext(ctx)
}
