//
//  OnboardingAuthView.swift
//  trendy
//
//  Authentication screen for onboarding - email/password + Google Sign-In
//  Redesigned with hero layout pattern per CONTEXT.md
//

import SwiftUI

struct OnboardingAuthView: View {
    @Bindable var viewModel: OnboardingViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError: String?

    /// Whether we're in sign-in mode vs sign-up mode
    private var isSignIn: Bool {
        viewModel.isSignInMode
    }

    /// Computed progress for the progress bar (step 2 of flow)
    /// Welcome = 0.0, Auth = 0.167 (1/6 of flow)
    private var currentProgress: Double {
        // Auth is step 2 of 6 total steps in the current flow
        // (welcome, auth, createEventType, logFirstEvent, permissions, finish)
        return 1.0 / Double(OnboardingStep.allCases.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            OnboardingProgressBar(progress: currentProgress)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            // Hero area (shorter than welcome to leave room for form)
            OnboardingHeroView(
                symbolName: isSignIn ? "person.crop.circle.fill" : "person.crop.circle.fill.badge.plus",
                gradientColors: [Color.dsPrimary.opacity(0.8), Color.dsAccent]
            )
            .frame(height: 200)

            // Scrollable form content
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(isSignIn ? "Welcome Back" : "Create Account")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.dsForeground)

                        Text(isSignIn ? "Sign in to continue" : "Start tracking your life")
                            .font(.subheadline)
                            .foregroundStyle(Color.dsMutedForeground)
                    }
                    .padding(.top, 24)

                    // Google Sign-In Button
                    if viewModel.isGoogleSignInAvailable {
                        GoogleSignInButton {
                            await signInWithGoogle()
                        }
                        .padding(.horizontal, 32)

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.dsBorder)
                                .frame(height: 1)
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(Color.dsMutedForeground)
                            Rectangle()
                                .fill(Color.dsBorder)
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 32)
                    }

                    // Email/Password Form
                    VStack(spacing: 16) {
                        // Email Field
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.dsCard)
                            .foregroundStyle(Color.dsForeground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.dsBorder, lineWidth: 1)
                            )

                        // Password Field
                        SecureField("Password", text: $password)
                            .textContentType(isSignIn ? .password : .newPassword)
                            .padding()
                            .background(Color.dsCard)
                            .foregroundStyle(Color.dsForeground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.dsBorder, lineWidth: 1)
                            )

                        // Confirm Password (sign up only)
                        if !isSignIn {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .padding()
                                .background(Color.dsCard)
                                .foregroundStyle(Color.dsForeground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.dsBorder, lineWidth: 1)
                                )

                            Text("Password must be at least 6 characters")
                                .font(.caption)
                                .foregroundStyle(Color.dsMutedForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Error Message
                        if let error = localError ?? viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .font(.caption)
                            .foregroundStyle(Color.dsDestructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Submit Button - primary action
                        Button {
                            Task {
                                await submitForm()
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color.dsPrimaryForeground)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text(isSignIn ? "Sign In" : "Create Account")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                        .background(isFormValid ? Color.dsPrimary : Color.dsSecondary)
                        .foregroundStyle(isFormValid ? Color.dsPrimaryForeground : Color.dsSecondaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(viewModel.isLoading || !isFormValid)
                    }
                    .padding(.horizontal, 32)

                    // Toggle Sign Up / Sign In
                    Button {
                        withAnimation {
                            viewModel.isSignInMode.toggle()
                            localError = nil
                            viewModel.errorMessage = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSignIn ? "Don't have an account?" : "Already have an account?")
                                .foregroundStyle(Color.dsMutedForeground)
                            Text(isSignIn ? "Sign Up" : "Sign In")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.dsLink)
                        }
                    }
                    .padding(.top, 8)

                    // Back Button
                    if !isSignIn {
                        Button {
                            viewModel.goBack()
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundStyle(Color.dsMutedForeground)
                        }
                    }

                    // Bottom padding to avoid keyboard overlap
                    Spacer(minLength: 40)
                }
            }
        }
        .background(Color.dsBackground)
        .onAppear {
            // Clear any previous errors
            localError = nil
            viewModel.errorMessage = nil
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        if isSignIn {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !email.isEmpty && password.count >= 6 && password == confirmPassword
        }
    }

    // MARK: - Actions

    private func submitForm() async {
        localError = nil

        if isSignIn {
            await viewModel.signIn(email: email, password: password)
        } else {
            // Validate confirm password
            guard password == confirmPassword else {
                localError = "Passwords do not match"
                return
            }
            guard password.count >= 6 else {
                localError = "Password must be at least 6 characters"
                return
            }
            await viewModel.signUp(email: email, password: password)
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        await viewModel.signInWithGoogle(from: rootViewController)
    }
}

// MARK: - Google Sign-In Button

private struct GoogleSignInButton: View {
    let action: () async -> Void

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 12) {
                // Google logo (using SF Symbol as placeholder)
                Image(systemName: "g.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red, .white)

                Text("Continue with Google")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.dsCard)
            .foregroundStyle(Color.dsForeground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dsBorder, lineWidth: 1)
            )
        }
    }
}

#Preview("Sign Up") {
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)
    viewModel.isSignInMode = false

    return OnboardingAuthView(viewModel: viewModel)
        .preferredColorScheme(.dark)
}

#Preview("Sign In") {
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)
    viewModel.isSignInMode = true

    return OnboardingAuthView(viewModel: viewModel)
        .preferredColorScheme(.dark)
}
