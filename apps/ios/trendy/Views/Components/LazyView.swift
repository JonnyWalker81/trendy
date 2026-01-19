//
//  LazyView.swift
//  trendy
//
//  Created by Claude on 1/19/26.
//

import SwiftUI

/// A view that defers creation of its content until it appears on screen.
/// Use this to wrap expensive views in TabView to prevent eager pre-rendering.
///
/// SwiftUI's TabView eagerly pre-renders ALL tabs when the view first appears,
/// which can cause startup hangs when tabs contain expensive views (like lists
/// with many items). LazyView solves this by wrapping the content in a closure
/// that is only called when SwiftUI actually needs to render the view.
///
/// Usage:
/// ```swift
/// TabView {
///     DashboardView()  // Default tab - render immediately
///         .tabItem { ... }
///
///     LazyView(EventListView())  // Defer until selected
///         .tabItem { ... }
/// }
/// ```
struct LazyView<Content: View>: View {
    let build: () -> Content

    /// Creates a lazy view from an autoclosure.
    /// - Parameter build: An autoclosure that creates the content view.
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    /// Creates a lazy view from a ViewBuilder closure.
    /// - Parameter build: A closure that creates the content view.
    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        build()
    }
}
