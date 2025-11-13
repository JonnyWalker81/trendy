//
//  SignupView.swift
//  trendy
//
//  Signup screen for new user registration
//

import SwiftUI

struct SignupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Create Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Start tracking your events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                // Signup Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .padding()
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .padding()
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Password Requirements
                    Text("Password must be at least 6 characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Error Message
                    if let errorMessage = localError ?? authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Signup Button
                    Button {
                        validateAndSignUp()
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authViewModel.isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                authViewModel.clearError()
                localError = nil
            }
        }
    }

    private func validateAndSignUp() {
        localError = nil

        // Validate passwords match
        guard password == confirmPassword else {
            localError = "Passwords do not match"
            return
        }

        // Validate password length
        guard password.count >= 6 else {
            localError = "Password must be at least 6 characters"
            return
        }

        // Perform signup
        Task {
            await authViewModel.signUp(email: email, password: password)

            // Dismiss on success
            if authViewModel.isAuthenticated {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let previewAuthViewModel = AuthViewModel(supabaseService: previewSupabase)

    return SignupView()
        .environment(previewAuthViewModel)
}
