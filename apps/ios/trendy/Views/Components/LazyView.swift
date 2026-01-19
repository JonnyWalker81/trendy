//
//  LazyView.swift
//  trendy
//
//  Created by Claude on 1/19/26.
//

import SwiftUI

/// A view that defers creation of its content until the tab is actually selected.
///
/// IMPORTANT: SwiftUI's TabView fires `onAppear` for ALL tabs when the TabView first appears,
/// not just the selected tab. This is because TabView needs to measure all tab content for layout.
/// A naive LazyView using `onAppear` will NOT prevent pre-rendering.
///
/// This implementation uses the selected tab binding to truly defer content creation:
/// - Content is only built when this tab IS the selected tab
/// - Once built, content is retained (not destroyed when switching away)
/// - Uses lightweight Color.clear placeholder until selected
///
/// Usage:
/// ```swift
/// @State private var selectedTab = 0
///
/// TabView(selection: $selectedTab) {
///     DashboardView()  // Default tab - render immediately
///         .tabItem { ... }
///         .tag(0)
///
///     LazyView(tag: 1, selection: $selectedTab) {
///         EventListView()  // Only built when tab 1 is first selected
///     }
///     .tabItem { ... }
///     .tag(1)
/// }
/// ```
struct LazyView<Content: View>: View {
    /// The tag of this tab (must match the .tag() modifier)
    let tag: Int

    /// Binding to the TabView's selection
    @Binding var selection: Int

    /// Closure that builds the content view
    let build: () -> Content

    /// Tracks if this tab was EVER selected - retains content after first render
    @State private var hasBeenSelected = false

    /// Creates a lazy tab view that only renders when selected.
    /// - Parameters:
    ///   - tag: The tab's tag value (must match .tag() modifier)
    ///   - selection: Binding to the TabView's selection state
    ///   - build: ViewBuilder closure that creates the content view
    init(tag: Int, selection: Binding<Int>, @ViewBuilder _ build: @escaping () -> Content) {
        self.tag = tag
        self._selection = selection
        self.build = build
    }

    /// Convenience initializer using autoclosure
    init(tag: Int, selection: Binding<Int>, _ build: @autoclosure @escaping () -> Content) {
        self.tag = tag
        self._selection = selection
        self.build = build
    }

    var body: some View {
        // Render content only if:
        // 1. This tab is currently selected, OR
        // 2. This tab was previously selected (retain for smooth tab switching)
        if hasBeenSelected || selection == tag {
            build()
                .onAppear {
                    // Mark as having been selected so content persists
                    if !hasBeenSelected {
                        hasBeenSelected = true
                    }
                }
        } else {
            // Lightweight placeholder - TabView can measure this without triggering content build
            Color.clear
        }
    }
}
