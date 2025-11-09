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
    ContentView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
        .environment(AuthViewModel())
}
