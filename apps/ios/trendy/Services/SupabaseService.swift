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
            print("✅ Session restored for user: \(session.user.email ?? "unknown")")
            #endif
        } catch {
            #if DEBUG
            print("ℹ️ No existing session found: \(error.localizedDescription)")
            #endif
            await MainActor.run {
                self.isAuthenticated = false
            }
        }
    }

    /// Get current access token for API requests
    func getAccessToken() async throws -> String {
        let tokenStart = Date()
        Log.auth.info("TIMING getAccessToken [T+0.000s] START - calling client.auth.session")
        let session = try await client.auth.session
        Log.auth.info("TIMING getAccessToken [T+\(String(format: "%.3f", Date().timeIntervalSince(tokenStart)))s] COMPLETE - session acquired")
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
            print("⚠️ Signup completed but no session returned for: \(email)")
            #endif
            throw AuthError.noSession
        }

        await MainActor.run {
            self.currentSession = session
            self.isAuthenticated = true
        }

        #if DEBUG
        print("✅ User signed up: \(email)")
        #endif
        return session
    }

    /// Sign in existing user with email and password
    func signIn(email: String, password: String) async throws -> Session {
        #if DEBUG
        print("🔐 SupabaseService.signIn: Starting sign-in for \(email)")
        #endif

        do {
            let session = try await client.auth.signIn(
                email: email,
                password: password
            )

            await MainActor.run {
                self.currentSession = session
                self.isAuthenticated = true
            }

            #if DEBUG
            print("✅ User signed in: \(email)")
            #endif
            return session
        } catch {
            #if DEBUG
            print("❌ SupabaseService.signIn failed: \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Localized description: \(error.localizedDescription)")
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

        await MainActor.run {
            self.currentSession = session
            self.isAuthenticated = true
        }

        #if DEBUG
        print("✅ User signed in with \(provider): \(session.user.email ?? "unknown")")
        #endif
        return session
    }

    /// Sign out current user
    func signOut() async throws {
        try await client.auth.signOut()

        await MainActor.run {
            self.currentSession = nil
            self.isAuthenticated = false
        }

        #if DEBUG
        print("✅ User signed out")
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
