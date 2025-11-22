//
//  EventType.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import SwiftData
import SwiftUI

// Allow UUID to be used with .sheet(item:) binding
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

@Model
final class EventType {
    var id: UUID
    var name: String
    var colorHex: String
    var iconName: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Event.eventType)
    var events: [Event]?

    @Relationship(deleteRule: .cascade, inverse: \PropertyDefinition.eventType)
    var propertyDefinitions: [PropertyDefinition]?

    init(name: String, colorHex: String = "#007AFF", iconName: String = "circle.fill") {
        self.id = UUID()
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