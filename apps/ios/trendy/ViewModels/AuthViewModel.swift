//
//  AuthViewModel.swift
//  trendy
//
//  ViewModel for managing authentication state
//

import Foundation
import SwiftUI
import PostHog

@Observable
class AuthViewModel {
    // Auth state
    private(set) var isAuthenticated = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var currentUserEmail: String?

    private let supabaseService: SupabaseService

    /// Initialize AuthViewModel with SupabaseService
    /// - Parameter supabaseService: Supabase service for authentication
    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService

        // Check initial auth state
        Task {
            await checkAuthState()
        }
    }

    // MARK: - Auth State Management

    /// Check current authentication state
    func checkAuthState() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await supabaseService.getCurrentUser()
            await MainActor.run {
                self.isAuthenticated = true
                self.currentUserEmail = user.email
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
                self.currentUserEmail = nil
            }
        }
    }

    // MARK: - Auth Actions

    /// Sign up new user
    func signUp(email: String, password: String) async {
        guard validateEmail(email) else {
            await MainActor.run {
                self.errorMessage = "Please enter a valid email address"
            }
            return
        }

        guard validatePassword(password) else {
            await MainActor.run {
                self.errorMessage = "Password must be at least 6 characters"
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        do {
            let session = try await supabaseService.signUp(email: email, password: password)

            // Identify user in PostHog (email is required)
            if let email = session.user.email {
                PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                    "email": email
                ])
            }

            await MainActor.run {
                self.isAuthenticated = true
                self.currentUserEmail = session.user.email
                self.errorMessage = nil
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Sign in existing user
    func signIn(email: String, password: String) async {
        guard validateEmail(email) else {
            await MainActor.run {
                self.errorMessage = "Please enter a valid email address"
            }
            return
        }

        guard !password.isEmpty else {
            await MainActor.run {
                self.errorMessage = "Please enter your password"
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        do {
            let session = try await supabaseService.signIn(email: email, password: password)

            // Identify user in PostHog (email is required)
            if let email = session.user.email {
                PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                    "email": email
                ])
            }

            await MainActor.run {
                self.isAuthenticated = true
                self.currentUserEmail = session.user.email
                self.errorMessage = nil
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
                self.errorMessage = "Invalid email or password"
                self.isLoading = false
            }
        }
    }

    /// Sign out current user
    func signOut() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        // Reset PostHog identification before signing out
        PostHogSDK.shared.reset()

        do {
            try await supabaseService.signOut()

            await MainActor.run {
                self.isAuthenticated = false
                self.currentUserEmail = nil
                self.errorMessage = nil
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Clear error message
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Validation

    private func validateEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func validatePassword(_ password: String) -> Bool {
        return password.count >= 6
    }
}
