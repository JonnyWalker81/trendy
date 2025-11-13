//
//  AddEventTypeView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct AddEventTypeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EventStore.self) private var eventStore
    
    @State private var name = ""
    @State private var selectedColor = Color.blue
    @State private var selectedIcon = "circle.fill"
    
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown
    ]
    
    private let icons: [String] = [
        "circle.fill", "star.fill", "heart.fill", "bolt.fill",
        "flame.fill", "drop.fill", "leaf.fill", "pawprint.fill",
        "pills.fill", "bandage.fill", "cross.fill", "bed.double.fill",
        "figure.walk", "figure.run", "dumbbell.fill", "sportscourt.fill",
        "brain.fill", "book.fill", "pencil", "briefcase.fill",
        "cart.fill", "cup.and.saucer.fill", "fork.knife", "car.fill"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Event Type Name") {
                    TextField("Name", text: $name)
                }
                
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? Color.chipBackground : Color.clear)
                                )
                                .foregroundColor(selectedIcon == icon ? .primary : .secondary)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    VStack(spacing: 12) {
                        Text("Preview")
                            .font(.headline)
                        
                        EventBubbleView(
                            eventType: EventType(
                                name: name.isEmpty ? "Preview" : name,
                                colorHex: selectedColor.hexString,
                                iconName: selectedIcon
                            ),
                            onTap: { },
                            onLongPress: { }
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Event Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            await eventStore.createEventType(
                                name: name,
                                colorHex: selectedColor.hexString,
                                iconName: selectedIcon
                            )
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}