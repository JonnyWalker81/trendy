/**
 * Structured logging module for the web application.
 * Uses pino for structured JSON logging with environment-based configuration.
 */

// Log levels in order of severity
type LogLevel = 'debug' | 'info' | 'warn' | 'error'

interface LogContext {
  [key: string]: unknown
}

interface LogEntry {
  timestamp: string
  level: LogLevel
  message: string
  context?: LogContext
}

// Environment-based log level configuration
const LOG_LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
}

function getLogLevel(): LogLevel {
  // Check environment variable first
  const envLevel = import.meta.env.VITE_LOG_LEVEL?.toLowerCase()
  if (envLevel && envLevel in LOG_LEVEL_ORDER) {
    return envLevel as LogLevel
  }

  // Environment-based defaults
  if (import.meta.env.DEV) {
    return 'debug'
  }
  if (import.meta.env.MODE === 'staging') {
    return 'info'
  }
  // Production: only warn and error
  return 'warn'
}

const currentLogLevel = getLogLevel()

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVEL_ORDER[level] >= LOG_LEVEL_ORDER[currentLogLevel]
}

function formatLogEntry(level: LogLevel, message: string, context?: LogContext): LogEntry {
  return {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...(context && Object.keys(context).length > 0 && { context }),
  }
}

function outputLog(entry: LogEntry): void {
  // In development, use pretty formatting for console
  if (import.meta.env.DEV) {
    const levelColors: Record<LogLevel, string> = {
      debug: 'color: #6b7280',
      info: 'color: #3b82f6',
      warn: 'color: #f59e0b',
      error: 'color: #ef4444',
    }

    const contextStr = entry.context ? ` ${JSON.stringify(entry.context)}` : ''

    switch (entry.level) {
      case 'debug':
        console.debug(`%c[${entry.level.toUpperCase()}]`, levelColors[entry.level], entry.message, contextStr)
        break
      case 'info':
        console.info(`%c[${entry.level.toUpperCase()}]`, levelColors[entry.level], entry.message, contextStr)
        break
      case 'warn':
        console.warn(`%c[${entry.level.toUpperCase()}]`, levelColors[entry.level], entry.message, contextStr)
        break
      case 'error':
        console.error(`%c[${entry.level.toUpperCase()}]`, levelColors[entry.level], entry.message, contextStr)
        break
    }
  } else {
    // In production, output structured JSON for log aggregation
    const jsonStr = JSON.stringify(entry)
    switch (entry.level) {
      case 'debug':
      case 'info':
        console.log(jsonStr)
        break
      case 'warn':
        console.warn(jsonStr)
        break
      case 'error':
        console.error(jsonStr)
        break
    }
  }
}

/**
 * Logger interface for structured logging
 */
export interface Logger {
  debug(message: string, context?: LogContext): void
  info(message: string, context?: LogContext): void
  warn(message: string, context?: LogContext): void
  error(message: string, context?: LogContext): void
  child(defaultContext: LogContext): Logger
}

function createLogger(defaultContext: LogContext = {}): Logger {
  return {
    debug(message: string, context?: LogContext): void {
      if (shouldLog('debug')) {
        outputLog(formatLogEntry('debug', message, { ...defaultContext, ...context }))
      }
    },

    info(message: string, context?: LogContext): void {
      if (shouldLog('info')) {
        outputLog(formatLogEntry('info', message, { ...defaultContext, ...context }))
      }
    },

    warn(message: string, context?: LogContext): void {
      if (shouldLog('warn')) {
        outputLog(formatLogEntry('warn', message, { ...defaultContext, ...context }))
      }
    },

    error(message: string, context?: LogContext): void {
      if (shouldLog('error')) {
        outputLog(formatLogEntry('error', message, { ...defaultContext, ...context }))
      }
    },

    child(childContext: LogContext): Logger {
      return createLogger({ ...defaultContext, ...childContext })
    },
  }
}

// Default logger instance
export const logger = createLogger()

// Named loggers for different components
export const apiLogger = createLogger({ component: 'api' })
export const authLogger = createLogger({ component: 'auth' })
export const uiLogger = createLogger({ component: 'ui' })

// Error helper to safely extract error information
export function errorContext(error: unknown): LogContext {
  if (error instanceof Error) {
    return {
      error_name: error.name,
      error_message: error.message,
      error_stack: import.meta.env.DEV ? error.stack : undefined,
    }
  }
  return { error_message: String(error) }
}

// Log API configuration on startup
if (import.meta.env.DEV) {
  logger.debug('Logger initialized', {
    log_level: currentLogLevel,
    mode: import.meta.env.MODE,
  })
}
