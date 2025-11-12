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
    private(set) var currentSession: Session?
    private(set) var isAuthenticated = false

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
            self.currentSession = session
            self.isAuthenticated = true
            print("Session restored for user: \(session.user.email ?? "unknown")")
        } catch {
            print("No existing session found: \(error.localizedDescription)")
            self.isAuthenticated = false
        }
    }

    /// Get current access token for API requests
    func getAccessToken() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }

    /// Get current user ID
    func getUserId() async throws -> String {
        let session = try await client.auth.session
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
            throw AuthError.noSession
        }

        self.currentSession = session
        self.isAuthenticated = true

        print("User signed up successfully: \(email)")
        return session
    }

    /// Sign in existing user with email and password
    func signIn(email: String, password: String) async throws -> Session {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )

        self.currentSession = session
        self.isAuthenticated = true

        print("User signed in successfully: \(email)")
        return session
    }

    /// Sign out current user
    func signOut() async throws {
        try await client.auth.signOut()

        self.currentSession = nil
        self.isAuthenticated = false

        print("User signed out successfully")
    }

    /// Refresh the current session token
    func refreshSession() async throws -> Session {
        let session = try await client.auth.refreshSession()

        self.currentSession = session
        self.isAuthenticated = true

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
