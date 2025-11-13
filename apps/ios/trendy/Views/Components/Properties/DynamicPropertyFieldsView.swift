//
//  DynamicPropertyFieldsView.swift
//  trendy
//
//  SwiftUI component for managing all properties (schema + custom) for an event
//

import SwiftUI
import SwiftData

/// View for managing all properties of an event (schema-based + custom)
struct DynamicPropertyFieldsView: View {
    let eventTypeId: UUID?
    @Binding var properties: [String: PropertyValue]

    @Query private var allPropertyDefinitions: [PropertyDefinition]

    @State private var showingAddCustomProperty = false
    @State private var newPropertyKey = ""
    @State private var newPropertyLabel = ""
    @State private var newPropertyType: PropertyType = .text
    @State private var tempPropertyValue: PropertyValue?

    // Computed property definitions for this event type
    private var propertyDefinitions: [PropertyDefinition] {
        guard let eventTypeId = eventTypeId else { return [] }
        return allPropertyDefinitions
            .filter { $0.eventTypeId == eventTypeId }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    // Custom properties (not in schema)
    private var customPropertyKeys: [String] {
        let schemaKeys = Set(propertyDefinitions.map { $0.key })
        return properties.keys.filter { !schemaKeys.contains($0) }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Schema-based properties
            if !propertyDefinitions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Event Properties")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(propertyDefinitions) { definition in
                        PropertyFieldView(
                            definition: definition,
                            value: Binding(
                                get: { properties[definition.key] },
                                set: { newValue in
                                    if let newValue = newValue {
                                        properties[definition.key] = newValue
                                    } else {
                                        properties.removeValue(forKey: definition.key)
                                    }
                                }
                            )
                        )
                    }
                }
            }

            // Custom properties
            if !customPropertyKeys.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Properties")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(customPropertyKeys, id: \.self) { key in
                        if let propValue = properties[key] {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatCustomPropertyLabel(key))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    customPropertyValueField(key: key, propertyValue: propValue)
                                }

                                Button(action: {
                                    removeCustomProperty(key: key)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }

            // Add custom property button
            Button(action: {
                showingAddCustomProperty = true
            }) {
                Label("Add Custom Property", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .sheet(isPresented: $showingAddCustomProperty) {
                addCustomPropertySheet
            }
        }
    }

    // MARK: - Custom Property Value Field

    @ViewBuilder
    private func customPropertyValueField(key: String, propertyValue: PropertyValue) -> some View {
        let propertyType = PropertyType(rawValue: propertyValue.type.rawValue) ?? .text

        switch propertyType {
        case .text, .url, .email:
            TextField("Enter value", text: Binding(
                get: { propertyValue.stringValue ?? "" },
                set: { properties[key] = PropertyValue(type: propertyType, value: $0) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())

        case .number:
            TextField("Enter number", text: Binding(
                get: {
                    if let double = propertyValue.doubleValue {
                        return String(double)
                    } else if let int = propertyValue.intValue {
                        return String(int)
                    }
                    return ""
                },
                set: { newValue in
                    if let doubleValue = Double(newValue) {
                        properties[key] = PropertyValue(type: .number, value: doubleValue)
                    }
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.decimalPad)

        case .boolean:
            Toggle("", isOn: Binding(
                get: { propertyValue.boolValue ?? false },
                set: { properties[key] = PropertyValue(type: .boolean, value: $0) }
            ))

        case .date:
            DatePicker("", selection: Binding(
                get: { propertyValue.dateValue ?? Date() },
                set: { properties[key] = PropertyValue(type: .date, value: $0) }
            ), displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.compact)

        case .duration:
            HStack {
                TextField("Minutes", text: Binding(
                    get: { String(propertyValue.intValue ?? 0) },
                    set: { newValue in
                        if let minutes = Int(newValue) {
                            properties[key] = PropertyValue(type: .duration, value: minutes)
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)

                Text("minutes")
                    .foregroundColor(.secondary)
            }

        case .select:
            Text(propertyValue.stringValue ?? "")
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardBackground)
                .cornerRadius(6)
        }
    }

    // MARK: - Add Custom Property Sheet

    private var addCustomPropertySheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Property Details")) {
                    TextField("Key (e.g., custom_field)", text: $newPropertyKey)
                        .autocapitalization(.none)

                    TextField("Label", text: $newPropertyLabel)

                    Picker("Type", selection: $newPropertyType) {
                        ForEach(PropertyType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section(header: Text("Initial Value")) {
                    PropertyFieldView(
                        definition: PropertyDefinition(
                            eventTypeId: eventTypeId ?? UUID(),
                            key: newPropertyKey,
                            label: newPropertyLabel.isEmpty ? "Value" : newPropertyLabel,
                            propertyType: newPropertyType
                        ),
                        value: $tempPropertyValue
                    )
                }
            }
            .navigationTitle("Add Custom Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetCustomPropertyForm()
                        showingAddCustomProperty = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addCustomProperty()
                    }
                    .disabled(newPropertyKey.isEmpty)
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Format custom property key as readable label
    private func formatCustomPropertyLabel(_ key: String) -> String {
        return key.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Add a custom property
    private func addCustomProperty() {
        guard !newPropertyKey.isEmpty else { return }

        // Use temp value if set, otherwise create default value
        if let value = tempPropertyValue {
            properties[newPropertyKey] = value
        } else {
            // Create default value based on type
            let defaultValue: Any
            switch newPropertyType {
            case .text, .url, .email, .select: defaultValue = ""
            case .number: defaultValue = 0.0
            case .boolean: defaultValue = false
            case .date: defaultValue = Date()
            case .duration: defaultValue = 0
            }
            properties[newPropertyKey] = PropertyValue(type: newPropertyType, value: defaultValue)
        }

        resetCustomPropertyForm()
        showingAddCustomProperty = false
    }

    /// Remove a custom property
    private func removeCustomProperty(key: String) {
        properties.removeValue(forKey: key)
    }

    /// Reset the custom property form
    private func resetCustomPropertyForm() {
        newPropertyKey = ""
        newPropertyLabel = ""
        newPropertyType = .text
        tempPropertyValue = nil
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: EventType.self, PropertyDefinition.self, configurations: config)

    // Create sample event type
    let eventType = EventType(name: "Test Event", colorHex: "#007AFF", iconName: "star.fill")
    container.mainContext.insert(eventType)

    // Create sample property definitions
    let textProp = PropertyDefinition(
        eventTypeId: eventType.id,
        key: "notes",
        label: "Notes",
        propertyType: .text,
        displayOrder: 0
    )
    let numberProp = PropertyDefinition(
        eventTypeId: eventType.id,
        key: "amount",
        label: "Amount",
        propertyType: .number,
        displayOrder: 1
    )

    container.mainContext.insert(textProp)
    container.mainContext.insert(numberProp)

    return DynamicPropertyFieldsView(
        eventTypeId: eventType.id,
        properties: .constant([
            "notes": PropertyValue(type: .text, value: "Test note"),
            "custom_field": PropertyValue(type: .number, value: 42)
        ])
    )
    .modelContainer(container)
    .padding()
}
