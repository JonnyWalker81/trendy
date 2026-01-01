//
//  AppConfiguration.swift
//  trendy
//
//  Multi-environment configuration management
//  Reads configuration from Info.plist (which pulls from xcconfig files)
//

import Foundation

// MARK: - Environment Detection

/// Represents the current build environment
enum AppEnvironment: String {
    case debug = "DEBUG"
    case staging = "STAGING"
    case testflight = "TESTFLIGHT"
    case release = "RELEASE"

    /// The current environment based on compiler flags
    static var current: AppEnvironment {
        #if DEBUG
        return .debug
        #elseif STAGING
        return .staging
        #elseif TESTFLIGHT
        return .testflight
        #elseif RELEASE
        return .release
        #else
        return .release
        #endif
    }

    var displayName: String {
        switch self {
        case .debug: return "Local Development"
        case .staging: return "Staging"
        case .testflight: return "TestFlight Beta"
        case .release: return "Production"
        }
    }
}

// MARK: - Configuration Structs

/// Configuration for the API client
struct APIConfiguration {
    let baseURL: String

    var isValid: Bool {
        !baseURL.isEmpty && (baseURL.hasPrefix("http://") || baseURL.hasPrefix("https://"))
    }
}

/// Configuration for Supabase services
struct SupabaseConfiguration {
    let url: String
    let anonKey: String

    var isValid: Bool {
        !url.isEmpty && !anonKey.isEmpty &&
        (url.hasPrefix("http://") || url.hasPrefix("https://"))
    }
}

/// Configuration for PostHog analytics
struct PostHogConfiguration {
    let apiKey: String
    let host: String

    var isValid: Bool {
        !apiKey.isEmpty && !host.isEmpty &&
        (host.hasPrefix("http://") || host.hasPrefix("https://"))
    }
}

// MARK: - App Configuration

/// Central configuration manager
/// Reads configuration values from Info.plist at initialization
/// Creates service-specific configuration objects for dependency injection
struct AppConfiguration {

    // MARK: - Properties

    let environment: AppEnvironment
    let apiConfiguration: APIConfiguration
    let supabaseConfiguration: SupabaseConfiguration
    /// PostHog configuration - only loaded in Release builds
    let posthogConfiguration: PostHogConfiguration?

    // MARK: - Initialization

    /// Initialize configuration from Info.plist
    /// - Throws: ConfigurationError if required keys are missing or invalid
    init() throws {
        self.environment = AppEnvironment.current

        // Read API configuration
        guard let apiBaseURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else {
            throw ConfigurationError.missingKey("API_BASE_URL")
        }

        self.apiConfiguration = APIConfiguration(baseURL: apiBaseURL)

        guard apiConfiguration.isValid else {
            throw ConfigurationError.invalidValue("API_BASE_URL", apiBaseURL)
        }

        // Read Supabase configuration
        guard let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String else {
            throw ConfigurationError.missingKey("SUPABASE_URL")
        }

        guard let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            throw ConfigurationError.missingKey("SUPABASE_ANON_KEY")
        }

        self.supabaseConfiguration = SupabaseConfiguration(
            url: supabaseURL,
            anonKey: supabaseKey
        )

        guard supabaseConfiguration.isValid else {
            throw ConfigurationError.invalidValue("SUPABASE_URL or SUPABASE_ANON_KEY", "\(supabaseURL), \(supabaseKey)")
        }

        // Read PostHog configuration (only required in TestFlight builds for now)
        #if TESTFLIGHT
        guard let posthogAPIKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String else {
            throw ConfigurationError.missingKey("POSTHOG_API_KEY")
        }

        guard let posthogHost = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String else {
            throw ConfigurationError.missingKey("POSTHOG_HOST")
        }

        let posthog = PostHogConfiguration(
            apiKey: posthogAPIKey,
            host: posthogHost
        )

        guard posthog.isValid else {
            throw ConfigurationError.invalidValue("POSTHOG_API_KEY or POSTHOG_HOST", "\(posthogAPIKey), \(posthogHost)")
        }

        self.posthogConfiguration = posthog
        #else
        self.posthogConfiguration = nil
        #endif
    }

    // MARK: - Debug Info

    /// Returns a sanitized summary of the current configuration for debugging
    /// (Hides sensitive keys)
    var debugDescription: String {
        var desc = """
        Environment: \(environment.displayName)
        API Base URL: \(apiConfiguration.baseURL)
        Supabase URL: \(supabaseConfiguration.url)
        Supabase Key: \(supabaseConfiguration.anonKey.prefix(20))...
        """
        if let posthog = posthogConfiguration {
            desc += """

            PostHog Host: \(posthog.host)
            PostHog Key: \(posthog.apiKey.prefix(10))...
            """
        } else {
            desc += "\nPostHog: Disabled (non-TestFlight build)"
        }
        return desc
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: LocalizedError {
    case missingKey(String)
    case invalidValue(String, String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let key):
            return "Missing required configuration key: \(key) in Info.plist"
        case .invalidValue(let key, let value):
            return "Invalid configuration value for \(key): \(value)"
        }
    }
}
