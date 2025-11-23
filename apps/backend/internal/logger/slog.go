package logger

import (
	"context"
	"log/slog"
	"os"
)

// slogLogger implements Logger using Go's standard library slog
type slogLogger struct {
	logger *slog.Logger
	level  Level
}

// NewSlogLogger creates a new Logger backed by slog
func NewSlogLogger(cfg Config) Logger {
	var handler slog.Handler

	opts := &slog.HandlerOptions{
		Level:     toSlogLevel(cfg.Level),
		AddSource: cfg.AddSource,
	}

	switch cfg.Format {
	case "text":
		handler = slog.NewTextHandler(os.Stdout, opts)
	default:
		handler = slog.NewJSONHandler(os.Stdout, opts)
	}

	return &slogLogger{
		logger: slog.New(handler),
		level:  cfg.Level,
	}
}

// toSlogLevel converts our Level to slog.Level
func toSlogLevel(l Level) slog.Level {
	switch l {
	case LevelDebug:
		return slog.LevelDebug
	case LevelInfo:
		return slog.LevelInfo
	case LevelWarn:
		return slog.LevelWarn
	case LevelError:
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// fieldsToAttrs converts our Field slice to slog.Attr slice
func fieldsToAttrs(fields []Field) []any {
	attrs := make([]any, 0, len(fields)*2)
	for _, f := range fields {
		attrs = append(attrs, f.Key, f.Value)
	}
	return attrs
}

func (l *slogLogger) Debug(msg string, fields ...Field) {
	l.logger.Debug(msg, fieldsToAttrs(fields)...)
}

func (l *slogLogger) Info(msg string, fields ...Field) {
	l.logger.Info(msg, fieldsToAttrs(fields)...)
}

func (l *slogLogger) Warn(msg string, fields ...Field) {
	l.logger.Warn(msg, fieldsToAttrs(fields)...)
}

func (l *slogLogger) Error(msg string, fields ...Field) {
	l.logger.Error(msg, fieldsToAttrs(fields)...)
}

func (l *slogLogger) With(fields ...Field) Logger {
	attrs := fieldsToAttrs(fields)
	return &slogLogger{
		logger: l.logger.With(attrs...),
		level:  l.level,
	}
}

func (l *slogLogger) WithContext(ctx context.Context) Logger {
	// Extract context values and create a child logger with them
	fields := extractContextFields(ctx)
	if len(fields) == 0 {
		return l
	}
	return l.With(fields...)
}

func (l *slogLogger) Level() Level {
	return l.level
}
