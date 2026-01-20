//
//  ContentView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//
//  NOTE: This view is now ONLY used for screenshot mode in DEBUG builds.
//  Normal app routing is handled by RootView + AppRouter.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    #if DEBUG
    /// Check if running in screenshot mode for UI tests
    private var isScreenshotMode: Bool {
        ScreenshotMockData.isScreenshotMode
    }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if isScreenshotMode {
                // Screenshot mode: skip auth, go directly to main app
                MainTabView()
                    .onAppear {
                        setupScreenshotMode()
                    }
            } else {
                // In non-screenshot debug mode, this view shouldn't be used
                // RootView handles routing via AppRouter
                Text("ContentView should not be shown - use RootView")
            }
            #else
            // In release builds, this view shouldn't be used
            // RootView handles routing via AppRouter
            Text("ContentView should not be shown - use RootView")
            #endif
        }
    }

    #if DEBUG
    /// Set up screenshot mode with mock data
    private func setupScreenshotMode() {
        // Inject mock data for screenshots
        ScreenshotMockData.injectMockData(into: modelContext)
    }
    #endif
}

#Preview {
    ContentView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
}
