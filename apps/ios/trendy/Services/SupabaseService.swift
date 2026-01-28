//
//  SupabaseService.swift
//  trendy
//
//  Created by Claude Code
//

import Foundation
import Supabase

/// Auth state change event types
enum AuthStateEvent {
    case initialSession(Session?)
    case signedIn(Session)
    case signedOut
    case tokenRefreshed(Session)
}

/// Service class for managing Supabase authentication
@Observable
@MainActor
class SupabaseService {
    private(set) var client: SupabaseClient
    var currentSession: Session?
    var isAuthenticated = false

    /// Track whether initial session restore has completed
    private(set) var initialSessionRestored = false

    /// Task for auth state change listener
    private var authStateTask: Task<Void, Never>?

    /// Continuation for auth state change stream
    private var authStateContinuation: AsyncStream<AuthStateEvent>.Continuation?

    /// Stream of auth state change events that AppRouter can subscribe to
    private(set) var authStateChanges: AsyncStream<AuthStateEvent>!

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
        Log.auth.debug("Cached userId for synchronous access", context: .with { ctx in
            ctx.add("user_id", userId)
        })
        #endif
    }

    /// Clear the cached user ID (called on sign-out)
    private func clearCachedUserId() {
        UserDefaults.standard.removeObject(forKey: Self.cachedUserIdKey)
        #if DEBUG
        Log.auth.debug("Cleared cached userId")
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

        // Create async stream for auth state changes
        self.authStateChanges = AsyncStream { continuation in
            self.authStateContinuation = continuation
        }

        // Start listening to Supabase auth state changes
        startAuthStateListener()
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Auth State Listener

    /// Start listening to Supabase SDK auth state changes
    /// This is the reliable way to track session state - no arbitrary timeouts
    private func startAuthStateListener() {
        authStateTask = Task { [weak self] in
            guard let self = self else { return }

            for await (event, session) in self.client.auth.authStateChanges {
                guard !Task.isCancelled else { break }

                Log.auth.debug("Auth state change", context: .with { ctx in
                    ctx.add("event", String(describing: event))
                    ctx.add("has_session", session != nil ? "true" : "false")
                })

                switch event {
                case .initialSession:
                    self.initialSessionRestored = true
                    self.currentSession = session
                    self.isAuthenticated = session != nil
                    if let session = session {
                        self.cacheUserId(session.user.id.uuidString)
                    }
                    self.authStateContinuation?.yield(.initialSession(session))

                case .signedIn:
                    if let session = session {
                        self.currentSession = session
                        self.isAuthenticated = true
                        self.cacheUserId(session.user.id.uuidString)
                        self.authStateContinuation?.yield(.signedIn(session))
                    }

                case .signedOut:
                    self.currentSession = nil
                    self.isAuthenticated = false
                    self.clearCachedUserId()
                    self.authStateContinuation?.yield(.signedOut)

                case .tokenRefreshed:
                    if let session = session {
                        self.currentSession = session
                        self.isAuthenticated = true
                        self.authStateContinuation?.yield(.tokenRefreshed(session))
                    }

                case .userUpdated, .userDeleted, .passwordRecovery, .mfaChallengeVerified:
                    // Handle other events if needed in the future
                    break
                }
            }
        }
    }

    // MARK: - Session Management

    /// Manually restore session from secure storage (fallback method)
    /// Note: Prefer using authStateChanges stream which handles this automatically
    func restoreSession() async {
        do {
            let session = try await client.auth.session
            self.currentSession = session
            self.isAuthenticated = true
            Log.auth.info("Session restored manually", context: .with { ctx in
                ctx.add("email", session.user.email)
            })
        } catch {
            Log.auth.debug("No existing session found", error: error)
            self.isAuthenticated = false
        }
    }

    /// Wait for initial session restore to complete
    /// Returns the session if authenticated, nil otherwise
    /// This is the preferred way to wait for session state on app launch
    func waitForInitialSession() async -> Session? {
        // If already restored, return current state immediately
        if initialSessionRestored {
            return currentSession
        }

        // Wait for the initialSession event from auth state listener
        for await event in authStateChanges {
            if case .initialSession(let session) = event {
                return session
            }
        }
        return nil
    }

    /// Get current access token for API requests
    nonisolated func getAccessToken() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }

    /// Get current user ID (async version)
    nonisolated func getUserId() async throws -> String {
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
            Log.auth.warning("Signup completed but no session returned", context: .with { ctx in
                ctx.add("email", email)
            })
            #endif
            throw AuthError.noSession
        }

        // Cache userId for synchronous access on future app launches
        cacheUserId(session.user.id.uuidString)

        self.currentSession = session
        self.isAuthenticated = true

        #if DEBUG
        Log.auth.info("User signed up", context: .with { ctx in
            ctx.add("email", email)
        })
        #endif
        return session
    }

    /// Sign in existing user with email and password
    func signIn(email: String, password: String) async throws -> Session {
        #if DEBUG
        Log.auth.debug("Starting sign-in", context: .with { ctx in
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

            self.currentSession = session
            self.isAuthenticated = true

            #if DEBUG
            Log.auth.info("User signed in", context: .with { ctx in
                ctx.add("email", email)
            })
            #endif
            return session
        } catch {
            #if DEBUG
            Log.auth.error("Sign-in failed", context: .with { ctx in
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

        self.currentSession = session
        self.isAuthenticated = true

        #if DEBUG
        Log.auth.info("User signed in with OAuth", context: .with { ctx in
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

        self.currentSession = nil
        self.isAuthenticated = false

        #if DEBUG
        Log.auth.info("User signed out")
        #endif
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
    nonisolated func getCurrentUser() async throws -> User {
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
