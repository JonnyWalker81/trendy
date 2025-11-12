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
    @AppStorage("migration_completed") private var migrationCompleted = false

    var body: some View {
        Group {
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
    }
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
