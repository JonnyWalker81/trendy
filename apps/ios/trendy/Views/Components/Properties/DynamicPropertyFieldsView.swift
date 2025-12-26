//
//  DynamicPropertyFieldsView.swift
//  trendy
//
//  SwiftUI component for managing all properties (schema + custom) for an event
//

import SwiftUI
import SwiftData

/// Protocol for property storage - allows different backing stores
protocol PropertyStorage: AnyObject {
    var properties: [String: PropertyValue] { get set }
}

/// View for managing all properties of an event (schema-based + custom)
/// NOTE: We use a plain class reference, NOT @ObservedObject, because @ObservedObject
/// was causing issues where the same object would return different values
struct DynamicPropertyFieldsView<Storage: PropertyStorage>: View {
    let eventTypeId: String?
    let storage: Storage  // Plain reference - parent handles observation
    let propertyDefinitions: [PropertyDefinition]

    @State private var showingAddCustomProperty = false
    @State private var refreshTrigger = UUID()  // Force view refresh when properties change

    // Custom properties (not in schema)
    private var customPropertyKeys: [String] {
        let schemaKeys = Set(propertyDefinitions.map { $0.key })
        return storage.properties.keys.filter { !schemaKeys.contains($0) }.sorted()
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
                                get: { storage.properties[definition.key] },
                                set: { newValue in
                                    // Directly update storage.properties
                                    if let newValue = newValue {
                                        storage.properties[definition.key] = newValue
                                    } else {
                                        storage.properties.removeValue(forKey: definition.key)
                                    }

                                    #if DEBUG
                                    print("🔄 Schema property '\(definition.key)' updated - total: \(storage.properties.count), keys: \(storage.properties.keys.joined(separator: ", "))")
                                    #endif
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
                        if let propValue = storage.properties[key] {
                            CustomPropertyRow(
                                key: key,
                                propertyValue: propValue,
                                onUpdate: { newValue in
                                    storage.properties[key] = newValue
                                    refreshTrigger = UUID()
                                },
                                onRemove: {
                                    storage.properties.removeValue(forKey: key)
                                    refreshTrigger = UUID()
                                    #if DEBUG
                                    print("➖ Removed property '\(key)' - remaining: \(storage.properties.count)")
                                    #endif
                                }
                            )
                        }
                    }
                }
            }

            // Add custom property button
            Button(action: {
                print("🟡 OPENING ADD SHEET - storage object: \(ObjectIdentifier(storage)), properties count: \(storage.properties.count), keys: \(storage.properties.keys.joined(separator: ", "))")
                showingAddCustomProperty = true
            }) {
                Label("Add Custom Property", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .sheet(isPresented: $showingAddCustomProperty) {
                // Capture storage reference directly
                let storageRef = storage
                AddCustomPropertySheet(
                    eventTypeId: eventTypeId,
                    onAdd: { key, value in
                        print("🟢 onAdd callback - storage.properties count: \(storageRef.properties.count), adding key: \(key)")
                        storageRef.properties[key] = value
                        print("🟢 After add - storage.properties count: \(storageRef.properties.count), keys: \(storageRef.properties.keys.joined(separator: ", "))")
                        // Trigger view refresh
                        refreshTrigger = UUID()
                    },
                    onCancel: {
                        showingAddCustomProperty = false
                    }
                )
            }

            // Debug: show current property count (also uses refreshTrigger to force updates)
            Text("DEBUG: \(storage.properties.count) properties [\(refreshTrigger.uuidString.prefix(4))]")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

}

// MARK: - Custom Property Row (Separate view to isolate button actions from SwiftUI confusion)

/// Separate view for each custom property row to prevent SwiftUI from mixing up button actions
struct CustomPropertyRow: View {
    let key: String
    let propertyValue: PropertyValue
    let onUpdate: (PropertyValue) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatLabel(key))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                CustomPropertyValueEditor(
                    propertyValue: propertyValue,
                    onUpdate: onUpdate
                )
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)  // Use plain style to avoid SwiftUI list button interference
        }
    }

    private func formatLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Separate view for editing custom property values
struct CustomPropertyValueEditor: View {
    let propertyValue: PropertyValue
    let onUpdate: (PropertyValue) -> Void

    var body: some View {
        let propertyType = PropertyType(rawValue: propertyValue.type.rawValue) ?? .text

        switch propertyType {
        case .text, .url, .email:
            TextField("Enter value", text: Binding(
                get: { propertyValue.stringValue ?? "" },
                set: { onUpdate(PropertyValue(type: propertyType, value: $0)) }
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
                        onUpdate(PropertyValue(type: .number, value: doubleValue))
                    }
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.decimalPad)

        case .boolean:
            Toggle("", isOn: Binding(
                get: { propertyValue.boolValue ?? false },
                set: { onUpdate(PropertyValue(type: .boolean, value: $0)) }
            ))

        case .date:
            DatePicker("", selection: Binding(
                get: { propertyValue.dateValue ?? Date() },
                set: { onUpdate(PropertyValue(type: .date, value: $0)) }
            ), displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.compact)

        case .duration:
            let durationSeconds = propertyValue.doubleValue ?? 0
            let durationMinutes = Int(durationSeconds / 60)

            HStack {
                TextField("Minutes", text: Binding(
                    get: { String(durationMinutes) },
                    set: { newValue in
                        if let minutes = Int(newValue) {
                            onUpdate(PropertyValue(type: .duration, value: Double(minutes * 60)))
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
}

// MARK: - Add Custom Property Sheet (Separate View to fix SwiftUI binding issue)

/// Separate sheet view to avoid SwiftUI's stale binding capture issue
struct AddCustomPropertySheet: View {
    let eventTypeId: String?
    let onAdd: (String, PropertyValue) -> Void
    let onCancel: () -> Void

    @State private var propertyKey = ""
    @State private var propertyLabel = ""
    @State private var propertyType: PropertyType = .text
    @State private var tempValue: PropertyValue?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Property Details")) {
                    TextField("Key (e.g., custom_field)", text: $propertyKey)
                        .autocapitalization(.none)

                    TextField("Label", text: $propertyLabel)

                    Picker("Type", selection: $propertyType) {
                        ForEach(PropertyType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section(header: Text("Initial Value")) {
                    PropertyFieldView(
                        definition: PropertyDefinition(
                            eventTypeId: eventTypeId ?? UUIDv7.generate(),
                            key: propertyKey,
                            label: propertyLabel.isEmpty ? "Value" : propertyLabel,
                            propertyType: propertyType
                        ),
                        value: $tempValue
                    )
                }
            }
            .navigationTitle("Add Custom Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProperty()
                    }
                    .disabled(propertyKey.isEmpty)
                }
            }
        }
    }

    private func addProperty() {
        guard !propertyKey.isEmpty else { return }

        let value: PropertyValue
        if let temp = tempValue {
            value = temp
        } else {
            // Create default value based on type
            let defaultValue: Any
            switch propertyType {
            case .text, .url, .email, .select: defaultValue = ""
            case .number: defaultValue = 0.0
            case .boolean: defaultValue = false
            case .date: defaultValue = Date()
            case .duration: defaultValue = 0
            }
            value = PropertyValue(type: propertyType, value: defaultValue)
        }

        print("🔵 AddCustomPropertySheet.addProperty() - key: \(propertyKey)")

        // Call the callback which runs in the parent's context with fresh binding
        onAdd(propertyKey, value)
        dismiss()
    }
}

// MARK: - Preview Storage

/// Simple storage class for previews
class PreviewPropertyStorage: PropertyStorage {
    var properties: [String: PropertyValue]

    init(properties: [String: PropertyValue] = [:]) {
        self.properties = properties
    }
}

// MARK: - Preview

private struct DynamicPropertyFieldsPreview: View {
    var body: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: EventType.self, PropertyDefinition.self, configurations: config)

        // Create sample event type
        let eventType = EventType(name: "Test Event", colorHex: "#007AFF", iconName: "star.fill")
        let _ = container.mainContext.insert(eventType)

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

        let _ = container.mainContext.insert(textProp)
        let _ = container.mainContext.insert(numberProp)

        let storage = PreviewPropertyStorage(properties: [
            "notes": PropertyValue(type: .text, value: "Test note"),
            "custom_field": PropertyValue(type: .number, value: 42)
        ])

        DynamicPropertyFieldsView(
            eventTypeId: eventType.id,
            storage: storage,
            propertyDefinitions: [textProp, numberProp]
        )
        .modelContainer(container)
        .padding()
    }
}

#Preview {
    DynamicPropertyFieldsPreview()
}
