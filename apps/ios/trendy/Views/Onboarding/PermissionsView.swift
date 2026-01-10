//
//  PermissionsView.swift
//  trendy
//
//  Permission pre-prompts screen for onboarding
//

import SwiftUI

struct PermissionsView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.geofenceManager) private var geofenceManager
    @Environment(\.healthKitService) private var healthKitService

    @State private var currentPermissionIndex = 0
    @State private var permissionResults: [OnboardingPermissionType: Bool] = [:]

    private let permissions: [OnboardingPermissionType] = [
        .notifications,
        .location,
        .healthkit
    ]

    private var currentPermission: OnboardingPermissionType? {
        guard currentPermissionIndex < permissions.count else { return nil }
        return permissions[currentPermissionIndex]
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Text("Enhance Your Experience")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsForeground)

                Text("These permissions are optional but helpful")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsMutedForeground)
            }

            // Progress Indicator
            ProgressIndicatorView(currentStep: 4, totalSteps: 4)

            Spacer()

            // Current Permission Card
            if let permission = currentPermission {
                PermissionCard(
                    permission: permission,
                    onEnable: {
                        await requestPermission(permission)
                    },
                    onSkip: {
                        skipCurrentPermission()
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(permission)
            } else {
                // All permissions handled
                allPermissionsHandledView
            }

            Spacer()

            // Skip all remaining
            if currentPermission != nil {
                Button {
                    Task {
                        await viewModel.skipCurrentStep()
                    }
                } label: {
                    Text("Skip all and continue")
                        .foregroundStyle(Color.dsMutedForeground)
                }
            }

            Spacer(minLength: 40)
        }
        .background(Color.dsBackground)
        .animation(.easeInOut(duration: 0.3), value: currentPermissionIndex)
    }

    // MARK: - All Permissions Handled View

    private var allPermissionsHandledView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.dsSuccess)

            Text("Permissions Set")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.dsForeground)

            // Summary of results
            VStack(spacing: 12) {
                ForEach(permissions, id: \.self) { permission in
                    HStack {
                        Image(systemName: permission.iconName)
                            .foregroundStyle(Color.dsPrimary)
                            .frame(width: 24)

                        Text(permission.displayName)
                            .foregroundStyle(Color.dsForeground)

                        Spacer()

                        if let enabled = permissionResults[permission] {
                            Image(systemName: enabled ? "checkmark.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(enabled ? Color.dsSuccess : Color.dsMutedForeground)
                        } else {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color.dsMutedForeground)
                        }
                    }
                }
            }
            .padding()
            .background(Color.dsCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            Text("You can change these anytime in Settings")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)

            Button {
                Task {
                    await viewModel.advanceToNextStep()
                }
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dsPrimary)
                    .foregroundStyle(Color.dsPrimaryForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func requestPermission(_ permission: OnboardingPermissionType) async {
        let granted: Bool

        switch permission {
        case .notifications:
            granted = await viewModel.requestNotificationPermission()
        case .location:
            if let geofenceManager = geofenceManager {
                granted = await viewModel.requestLocationPermission(geofenceManager: geofenceManager)
            } else {
                granted = false
            }
        case .healthkit:
            granted = await viewModel.requestHealthKitPermission(healthKitService: healthKitService)
        }

        permissionResults[permission] = granted
        advanceToNextPermission()
    }

    private func skipCurrentPermission() {
        if let permission = currentPermission {
            permissionResults[permission] = false
        }
        advanceToNextPermission()
    }

    private func advanceToNextPermission() {
        withAnimation {
            currentPermissionIndex += 1
        }
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {
    let permission: OnboardingPermissionType
    let onEnable: () async -> Void
    let onSkip: () -> Void

    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: permission.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(Color.dsPrimary)
                .clipShape(Circle())

            // Title and Description
            VStack(spacing: 8) {
                Text(permission.promptTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsForeground)

                Text(permission.promptDescription)
                    .font(.body)
                    .foregroundStyle(Color.dsMutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Buttons
            VStack(spacing: 12) {
                Button {
                    isLoading = true
                    Task {
                        await onEnable()
                        isLoading = false
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.dsPrimaryForeground)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(permission.enableButtonText)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(Color.dsPrimary)
                .foregroundStyle(Color.dsPrimaryForeground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isLoading)

                Button(action: onSkip) {
                    Text("Not Now")
                        .foregroundStyle(Color.dsLink)
                }
                .disabled(isLoading)
            }
        }
        .padding(32)
        .background(Color.dsCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.dsBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Environment Keys for Services

private struct GeofenceManagerKey: EnvironmentKey {
    static let defaultValue: GeofenceManager? = nil
}

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: HealthKitService? = nil
}

extension EnvironmentValues {
    var geofenceManager: GeofenceManager? {
        get { self[GeofenceManagerKey.self] }
        set { self[GeofenceManagerKey.self] = newValue }
    }

    var healthKitService: HealthKitService? {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }
}

#Preview {
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)

    return PermissionsView(viewModel: viewModel)
        .preferredColorScheme(.dark)
}
