//
//  AppGroupContainer.swift
//  TrendyWidgets
//
//  App Group configuration for sharing data between main app and widget extension.
//
//  NOTE: This file previously created a shared SwiftData ModelContainer.
//  That approach caused 0xdead10cc crashes because iOS terminates apps holding
//  SQLite file locks in shared containers during background suspension.
//
//  Widgets now use a JSON bridge (see WidgetDataManager.swift) instead of
//  direct SwiftData access. This file is kept for the App Group identifier
//  constant and backward compatibility.
//

import Foundation

/// App Group identifier for sharing data between main app and widget extension
let appGroupIdentifier = "group.com.memento.trendy"

/// NOTE: The following was removed to fix 0xdead10cc crashes:
///
/// Previously, AppGroupContainer.createSharedModelContainer() created a
/// ModelContainer using the shared App Group storage. This allowed both
/// the main app and widget to open the same SQLite database.
///
/// This was replaced by a JSON bridge architecture:
/// - Main app writes widget_snapshot.json to the App Group
/// - Widget reads this JSON file (no SQLite involved)
/// - Widget writes widget_pending_events.json for quick-log actions
/// - Main app processes pending events on foreground
///
/// See: WidgetDataBridge.swift (main app) and WidgetDataManager.swift (widget)
