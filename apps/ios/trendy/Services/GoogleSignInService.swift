//
//  GoogleSignInService.swift
//  trendy
//
//  Service for handling Google Sign-In with Supabase
//
//  SETUP REQUIRED:
//  1. Add GoogleSignIn-iOS package: https://github.com/google/GoogleSignIn-iOS (v7.0+)
//  2. Create iOS OAuth Client ID in Google Cloud Console
//  3. Create Web OAuth Client ID in Google Cloud Console (for Supabase)
//  4. Add both Client IDs to Supabase Dashboard under Providers > Google
//  5. Enable "Skip nonce check" in Supabase Dashboard for iOS
//  6. Add GOOGLE_CLIENT_ID to xcconfig files
//  7. Add URL scheme to Info.plist: com.googleusercontent.apps.{CLIENT_ID}
//

import Foundation
import UIKit
import Supabase

// Conditional import for GoogleSignIn - uncomment when package is added
// import GoogleSignIn

/// Service for handling Google Sign-In with Supabase
/// Requires GoogleSignIn-iOS package to be added to the project
@Observable
@MainActor
class GoogleSignInService {
    private let supabaseService: SupabaseService

    /// Whether Google Sign-In is available (package installed and configured)
    var isAvailable: Bool {
        !googleClientID.isEmpty
    }

    /// Google iOS Client ID from Info.plist (configured via xcconfig)
    private var googleClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
    }

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    // MARK: - Sign In

    /// Sign in with Google
    ///
    /// This method:
    /// 1. Presents Google Sign-In UI
    /// 2. Gets ID token from Google
    /// 3. Exchanges ID token for Supabase session
    ///
    /// - Parameter presentingViewController: The view controller to present the sign-in flow from
    /// - Returns: The Supabase session after successful sign-in
    /// - Throws: GoogleSignInError if sign-in fails
    func signIn(presentingViewController: UIViewController) async throws -> Session {
        guard isAvailable else {
            throw GoogleSignInError.notConfigured
        }

        Log.auth.info("Starting Google Sign-In")

        // TODO: Uncomment when GoogleSignIn package is added
        /*
        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: googleClientID)
        GIDSignIn.sharedInstance.configuration = config

        // Perform Google Sign-In
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController
        )

        guard let idToken = result.user.idToken?.tokenString else {
            Log.auth.error("Google Sign-In failed: No ID token")
            throw GoogleSignInError.noIdToken
        }

        Log.auth.debug("Got Google ID token, exchanging for Supabase session")

        // Exchange Google ID token for Supabase session
        // Note: Supabase Dashboard must have "Skip nonce check" enabled for iOS
        let session = try await supabaseService.client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken
            )
        )

        // Update SupabaseService state
        supabaseService.currentSession = session
        supabaseService.isAuthenticated = true

        Log.auth.info("Google Sign-In successful", context: .with { ctx in
            ctx.add("user_id", session.user.id.uuidString)
            ctx.add("email", session.user.email ?? "unknown")
        })

        return session
        */

        // Placeholder until GoogleSignIn package is added
        throw GoogleSignInError.notConfigured
    }

    // MARK: - Sign Out

    /// Sign out from Google (in addition to Supabase sign out)
    func signOut() {
        Log.auth.info("Signing out from Google")

        // TODO: Uncomment when GoogleSignIn package is added
        // GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - URL Handling

    /// Handle URL callback from Google Sign-In
    /// Call this from your AppDelegate or SceneDelegate
    ///
    /// - Parameter url: The URL to handle
    /// - Returns: Whether the URL was handled
    func handle(_ url: URL) -> Bool {
        // TODO: Uncomment when GoogleSignIn package is added
        // return GIDSignIn.sharedInstance.handle(url)
        return false
    }
}

// MARK: - Errors

enum GoogleSignInError: LocalizedError {
    case notConfigured
    case noIdToken
    case cancelled
    case networkError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Sign-In is not configured. Please add the GoogleSignIn-iOS package and configure your Client ID."
        case .noIdToken:
            return "Could not obtain Google ID token"
        case .cancelled:
            return "Sign-in was cancelled"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    var isUserCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
