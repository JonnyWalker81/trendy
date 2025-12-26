//
//  EventType.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import SwiftData
import SwiftUI

// Allow String to be used with .sheet(item:) binding for UUIDv7 IDs
extension String: @retroactive Identifiable {
    public var id: String { self }
}

@Model
final class EventType {
    /// UUIDv7 identifier - client-generated, globally unique, time-ordered
    /// This is THE canonical ID used both locally and on the server
    @Attribute(.unique) var id: String
    /// Sync status with the backend
    var syncStatusRaw: String = SyncStatus.pending.rawValue
    var name: String
    var colorHex: String
    var iconName: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Event.eventType)
    var events: [Event]?

    @Relationship(deleteRule: .cascade, inverse: \PropertyDefinition.eventType)
    var propertyDefinitions: [PropertyDefinition]?

    // MARK: - Computed Properties

    /// Sync status computed property for convenient access
    @Transient var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: String = UUIDv7.generate(),
        name: String,
        colorHex: String = "#007AFF",
        iconName: String = "circle.fill",
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.syncStatusRaw = syncStatus.rawValue
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = Date()
        self.events = []
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let rgb: Int = (Int)(red * 255) << 16 | (Int)(green * 255) << 8 | (Int)(blue * 255)

        return String(format: "#%06x", rgb)
    }
}
