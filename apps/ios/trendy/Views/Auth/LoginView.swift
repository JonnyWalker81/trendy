//
//  LoginView.swift
//  trendy
//
//  Login screen for user authentication
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo/Title
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.dsPrimary)

                    Text("trendy")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Track your life, find your patterns")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                .padding(.bottom, 40)

                // Login Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Error Message
                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.dsDestructive)
                            .padding(.horizontal)
                    }

                    // Login Button
                    Button {
                        Task {
                            await authViewModel.signIn(email: email, password: password)
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authViewModel.isLoading || email.isEmpty || password.isEmpty)
                }
                .padding(.horizontal, 32)

                Spacer()

                // Sign Up Link
                Button {
                    showingSignup = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundStyle(Color.dsMutedForeground)
                        Text("Sign Up")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.dsLink)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSignup) {
                SignupView()
            }
            .onAppear {
                authViewModel.clearError()
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

    return LoginView()
        .environment(previewAuthViewModel)
}
