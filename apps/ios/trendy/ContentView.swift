//
//  ContentView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("migration_completed") private var migrationCompleted = false

    #if DEBUG
    /// Check if running in screenshot mode for UI tests
    private var isScreenshotMode: Bool {
        ScreenshotMockData.isScreenshotMode
    }
    #endif

    var body: some View {
        @Bindable var themeManager = themeManager

        Group {
            #if DEBUG
            if isScreenshotMode {
                // Screenshot mode: skip auth and migration, go directly to main app
                MainTabView()
                    .onAppear {
                        setupScreenshotMode()
                    }
            } else {
                authenticatedContent
            }
            #else
            authenticatedContent
            #endif
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if authViewModel.isAuthenticated {
            if migrationCompleted {
                // Migration done, show main app
                MainTabView()
            } else {
                // Show migration view (will be created next)
                MigrationView()
            }
        } else {
            // Not authenticated, show login
            LoginView()
        }
    }

    #if DEBUG
    /// Set up screenshot mode with mock data
    private func setupScreenshotMode() {
        // Mark migration as completed to bypass migration view
        migrationCompleted = true

        // Inject mock data for screenshots
        ScreenshotMockData.injectMockData(into: modelContext)
    }
    #endif
}

#Preview {
    // Create preview configuration
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let previewAuthViewModel = AuthViewModel(supabaseService: previewSupabase)

    return ContentView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
        .environment(previewAuthViewModel)
}
