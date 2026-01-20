//
//  PermissionsView.swift
//  trendy
//
//  Permission pre-prompts screen for onboarding
//  Displays individual full-screen priming views for each permission
//

import SwiftUI

struct PermissionsView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.geofenceManager) private var geofenceManager
    @Environment(\.healthKitService) private var healthKitService

    @State private var currentPermissionIndex = 0
    @State private var permissionResults: [OnboardingPermissionType: Bool] = [:]

    /// Ordered list of permissions to request
    private let permissions: [OnboardingPermissionType] = [
        .notifications,
        .location,
        .healthkit
    ]

    /// Current permission being displayed (nil when all handled)
    private var currentPermission: OnboardingPermissionType? {
        guard currentPermissionIndex < permissions.count else { return nil }
        return permissions[currentPermissionIndex]
    }

    /// Calculate progress: interpolate between permissions step and finish step
    /// This gives smooth progress advancement as user moves through permissions
    private var progress: Double {
        let baseProgress = OnboardingStep.permissions.progress
        let finishProgress = OnboardingStep.finish.progress
        let permissionProgress = Double(currentPermissionIndex) / Double(permissions.count)
        return baseProgress + (finishProgress - baseProgress) * permissionProgress
    }

    var body: some View {
        Group {
            if let permission = currentPermission {
                permissionPrimingView(for: permission)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(permission)
            } else {
                // All permissions handled - advance to next step
                Color.clear.onAppear {
                    Task {
                        await viewModel.advanceToNextStep()
                    }
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentPermissionIndex)
    }

    // MARK: - Permission Priming Views

    @ViewBuilder
    private func permissionPrimingView(for permission: OnboardingPermissionType) -> some View {
        switch permission {
        case .notifications:
            NotificationPrimingScreen(
                progress: progress,
                onEnable: { await requestPermission(permission) },
                onSkip: { skipPermission(permission) }
            )
        case .location:
            LocationPrimingScreen(
                progress: progress,
                onEnable: { await requestPermission(permission) },
                onSkip: { skipPermission(permission) }
            )
        case .healthkit:
            HealthKitPrimingScreen(
                progress: progress,
                onEnable: { await requestPermission(permission) },
                onSkip: { skipPermission(permission) }
            )
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

    private func skipPermission(_ permission: OnboardingPermissionType) {
        permissionResults[permission] = false
        advanceToNextPermission()
    }

    private func advanceToNextPermission() {
        withAnimation {
            currentPermissionIndex += 1
        }
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
