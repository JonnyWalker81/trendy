//
//  SupabaseService.swift
//  trendy
//
//  Created by Claude Code
//

import Foundation
import Supabase

/// Service class for managing Supabase authentication
@Observable
class SupabaseService {
    private(set) var client: SupabaseClient
    var currentSession: Session?
    var isAuthenticated = false

    // MARK: - Cached User ID
    // Stores userId in UserDefaults for synchronous access on app launch.
    // This is necessary because Supabase's session restore is async (Keychain access),
    // but we need the userId synchronously for instant routing decisions.

    private static let cachedUserIdKey = "supabase_cached_user_id"

    /// Get cached user ID synchronously from UserDefaults
    /// Returns nil if no cached user ID exists (user never signed in or signed out)
    var cachedUserId: String? {
        UserDefaults.standard.string(forKey: Self.cachedUserIdKey)
    }

    /// Cache the user ID for synchronous access
    private func cacheUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: Self.cachedUserIdKey)
        #if DEBUG
        Log.auth.debug("🔑 Cached userId for synchronous access", context: .with { ctx in
            ctx.add("user_id", userId)
        })
        #endif
    }

    /// Clear the cached user ID (called on sign-out)
    private func clearCachedUserId() {
        UserDefaults.standard.removeObject(forKey: Self.cachedUserIdKey)
        #if DEBUG
        Log.auth.debug("🔑 Cleared cached userId")
        #endif
    }

    /// Initialize SupabaseService with configuration
    /// - Parameter configuration: Supabase configuration containing URL and anon key
    init(configuration: SupabaseConfiguration) {
        guard let url = URL(string: configuration.url) else {
            fatalError("Invalid Supabase URL: \(configuration.url)")
        }

        // Initialize Supabase client
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: configuration.anonKey
        )

        // Try to restore existing session
        Task {
            await restoreSession()
        }
    }

    // MARK: - Session Management

    /// Restore existing session from secure storage
    func restoreSession() async {
        do {
            let session = try await client.auth.session
            await MainActor.run {
                self.currentSession = session
                self.isAuthenticated = true
            }
            #if DEBUG
            Log.auth.info("✅ Session restored", context: .with { ctx in
                ctx.add("email", session.user.email)
            })
            #endif
        } catch {
            #if DEBUG
            Log.auth.debug("ℹ️ No existing session found", error: error)
            #endif
            await MainActor.run {
                self.isAuthenticated = false
            }
        }
    }

    /// Get current access token for API requests
    func getAccessToken() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }

    /// Get current user ID (async version)
    func getUserId() async throws -> String {
        let session = try await client.auth.session
        return session.user.id.uuidString
    }

    /// Get current user ID synchronously from cached session
    /// - Throws: AuthError.noSession if no session is available
    func getUserId() throws -> String {
        guard let session = currentSession else {
            throw AuthError.noSession
        }
        return session.user.id.uuidString
    }

    // MARK: - Authentication Methods

    /// Sign up a new user with email and password
    func signUp(email: String, password: String) async throws -> Session {
        let response = try await client.auth.signUp(
            email: email,
            password: password
        )

        guard let session = response.session else {
            #if DEBUG
            Log.auth.warning("⚠️ Signup completed but no session returned", context: .with { ctx in
                ctx.add("email", email)
            })
            #endif
            throw AuthError.noSession
        }

        // Cache userId for synchronous access on future app launches
        cacheUserId(session.user.id.uuidString)

        await MainActor.run {
            self.currentSession = session
            self.isAuthenticated = true
        }

        #if DEBUG
        Log.auth.info("✅ User signed up", context: .with { ctx in
            ctx.add("email", email)
        })
        #endif
        return session
    }

    /// Sign in existing user with email and password
    func signIn(email: String, password: String) async throws -> Session {
        #if DEBUG
        Log.auth.debug("🔐 Starting sign-in", context: .with { ctx in
            ctx.add("email", email)
        })
        #endif

        do {
            let session = try await client.auth.signIn(
                email: email,
                password: password
            )

            // Cache userId for synchronous access on future app launches
            cacheUserId(session.user.id.uuidString)

            await MainActor.run {
                self.currentSession = session
                self.isAuthenticated = true
            }

            #if DEBUG
            Log.auth.info("✅ User signed in", context: .with { ctx in
                ctx.add("email", email)
            })
            #endif
            return session
        } catch {
            #if DEBUG
            Log.auth.error("❌ Sign-in failed", context: .with { ctx in
                ctx.add("email", email)
                ctx.add("error_type", String(describing: type(of: error)))
                ctx.add(error: error)
            })
            #endif
            throw error
        }
    }

    /// Sign in with ID token from external OAuth provider (Google, Apple)
    /// - Parameters:
    ///   - provider: The OAuth provider (e.g., .google, .apple)
    ///   - idToken: The ID token obtained from the OAuth provider
    ///   - accessToken: Optional access token (required for some providers like Google)
    /// - Returns: The authenticated session
    /// - Note: For iOS Google Sign-In, ensure "Skip nonce check" is enabled in Supabase Dashboard
    func signInWithIdToken(
        provider: OpenIDConnectCredentials.Provider,
        idToken: String,
        accessToken: String? = nil
    ) async throws -> Session {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: provider,
                idToken: idToken,
                accessToken: accessToken
            )
        )

        // Cache userId for synchronous access on future app launches
        cacheUserId(session.user.id.uuidString)

        await MainActor.run {
            self.currentSession = session
            self.isAuthenticated = true
        }

        #if DEBUG
        Log.auth.info("✅ User signed in with OAuth", context: .with { ctx in
            ctx.add("provider", String(describing: provider))
            ctx.add("email", session.user.email)
        })
        #endif
        return session
    }

    /// Sign out current user
    func signOut() async throws {
        try await client.auth.signOut()

        // Clear cached userId so next app launch won't try to auto-route
        clearCachedUserId()

        await MainActor.run {
            self.currentSession = nil
            self.isAuthenticated = false
        }

        #if DEBUG
        Log.auth.info("✅ User signed out")
        #endif
    }

    /// Refresh the current session token
    func refreshSession() async throws -> Session {
        let session = try await client.auth.refreshSession()

        await MainActor.run {
            self.currentSession = session
            self.isAuthenticated = true
        }

        return session
    }

    // MARK: - User Information

    /// Get current user information
    func getCurrentUser() async throws -> User {
        let session = try await client.auth.session
        return session.user
    }
}

// MARK: - Error Types

enum AuthError: LocalizedError {
    case noSession
    case invalidCredentials
    case networkError
    case unknownError(Error)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No active session. Please sign in."
        case .invalidCredentials:
            return "Invalid email or password."
        case .networkError:
            return "Network error. Please check your connection."
        case .unknownError(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }
}
