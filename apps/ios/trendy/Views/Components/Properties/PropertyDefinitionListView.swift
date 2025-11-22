//
//  PropertyDefinitionListView.swift
//  trendy
//
//  SwiftUI component for managing property definitions (schemas) for event types
//

import SwiftUI
import SwiftData

/// View for managing property definitions on an event type
struct PropertyDefinitionListView: View {
    let eventType: EventType

    @Environment(\.modelContext) private var modelContext
    @Query private var allPropertyDefinitions: [PropertyDefinition]

    @State private var showingAddProperty = false
    @State private var editingPropertyID: UUID?

    // Property definitions for this event type
    private var propertyDefinitions: [PropertyDefinition] {
        allPropertyDefinitions
            .filter { $0.eventTypeId == eventType.id }
            .sorted { $0.displayOrder < $1.displayOrder }
    }
    
    private var editingProperty: PropertyDefinition? {
        guard let id = editingPropertyID else { return nil }
        return propertyDefinitions.first { $0.id == id }
    }

    var body: some View {
        List {
            Section(header: Text("Property Definitions")) {
                if propertyDefinitions.isEmpty {
                    Text("No properties defined")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(propertyDefinitions) { definition in
                        PropertyDefinitionRow(definition: definition)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingPropertyID = definition.id
                            }
                    }
                    .onDelete(perform: deleteProperties)
                    .onMove(perform: moveProperties)
                }
            }

            Section {
                Button(action: {
                    showingAddProperty = true
                }) {
                    Label("Add Property Definition", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Properties")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showingAddProperty) {
            PropertyDefinitionFormView(eventType: eventType, propertyDefinition: nil)
        }
        .sheet(item: $editingPropertyID) { propertyID in
            if let definition = propertyDefinitions.first(where: { $0.id == propertyID }) {
                PropertyDefinitionFormView(eventType: eventType, propertyDefinition: definition)
            }
        }
    }

    // MARK: - Helper Methods

    /// Delete property definitions
    private func deleteProperties(at offsets: IndexSet) {
        for index in offsets {
            let definition = propertyDefinitions[index]
            modelContext.delete(definition)
        }
    }

    /// Move property definitions (reorder)
    private func moveProperties(from source: IndexSet, to destination: Int) {
        var definitions = propertyDefinitions
        definitions.move(fromOffsets: source, toOffset: destination)

        // Update display order
        for (index, definition) in definitions.enumerated() {
            definition.displayOrder = index
            definition.updatedAt = Date()
        }
    }
}

// MARK: - Property Definition Row

struct PropertyDefinitionRow: View {
    let definition: PropertyDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(definition.label)
                .font(.body)

            HStack {
                Text(definition.key)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(definition.propertyType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Property Definition Form

struct PropertyDefinitionFormView: View {
    let eventType: EventType
    let propertyDefinition: PropertyDefinition?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var key: String
    @State private var label: String
    @State private var propertyType: PropertyType
    @State private var options: [String]
    @State private var optionInput: String = ""
    @State private var hasDefaultValue: Bool = false
    @State private var defaultValueText: String = ""
    @State private var defaultValueNumber: Double = 0
    @State private var defaultValueBool: Bool = false

    init(eventType: EventType, propertyDefinition: PropertyDefinition?) {
        self.eventType = eventType
        self.propertyDefinition = propertyDefinition

        // Initialize state from existing definition or defaults
        _key = State(initialValue: propertyDefinition?.key ?? "")
        _label = State(initialValue: propertyDefinition?.label ?? "")
        _propertyType = State(initialValue: propertyDefinition?.propertyType ?? .text)
        _options = State(initialValue: propertyDefinition?.options ?? [])

        // Initialize default value if exists
        if let defaultValue = propertyDefinition?.defaultValue {
            _hasDefaultValue = State(initialValue: true)
            if let str = defaultValue.value as? String {
                _defaultValueText = State(initialValue: str)
            } else if let num = defaultValue.value as? Double {
                _defaultValueNumber = State(initialValue: num)
            } else if let num = defaultValue.value as? Int {
                _defaultValueNumber = State(initialValue: Double(num))
            } else if let bool = defaultValue.value as? Bool {
                _defaultValueBool = State(initialValue: bool)
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Key (e.g., duration, distance)", text: $key)
                        .autocapitalization(.none)
                        .disabled(propertyDefinition != nil) // Can't change key after creation

                    TextField("Label (e.g., Duration, Distance)", text: $label)

                    Picker("Type", selection: $propertyType) {
                        ForEach(PropertyType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .disabled(propertyDefinition != nil) // Can't change type after creation
                }

                // Options for select type
                if propertyType == .select {
                    Section(header: Text("Options")) {
                        ForEach(options, id: \.self) { option in
                            HStack {
                                Text(option)
                                Spacer()
                                Button(action: {
                                    options.removeAll { $0 == option }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }

                        HStack {
                            TextField("Add option", text: $optionInput)
                            Button(action: addOption) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                            .disabled(optionInput.isEmpty)
                        }
                    }
                }

                // Default value
                Section(header: Text("Default Value")) {
                    Toggle("Set default value", isOn: $hasDefaultValue)

                    if hasDefaultValue {
                        defaultValueField
                    }
                }
            }
            .navigationTitle(propertyDefinition == nil ? "Add Property" : "Edit Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePropertyDefinition()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Default Value Field

    @ViewBuilder
    private var defaultValueField: some View {
        switch propertyType {
        case .text, .url, .email:
            TextField("Default value", text: $defaultValueText)

        case .number, .duration:
            TextField("Default value", value: $defaultValueNumber, format: .number)
                .keyboardType(.decimalPad)

        case .boolean:
            Toggle("Default value", isOn: $defaultValueBool)

        case .date:
            Text("Date defaults are not supported")
                .font(.caption)
                .foregroundColor(.secondary)

        case .select:
            Picker("Default value", selection: $defaultValueText) {
                Text("None").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private var canSave: Bool {
        !key.isEmpty && !label.isEmpty && (propertyType != .select || !options.isEmpty)
    }

    private func addOption() {
        guard !optionInput.isEmpty else { return }
        options.append(optionInput)
        optionInput = ""
    }

    private func savePropertyDefinition() {
        // Build default value
        var defaultValue: AnyCodable?
        if hasDefaultValue {
            switch propertyType {
            case .text, .url, .email, .select:
                defaultValue = AnyCodable(defaultValueText)
            case .number:
                defaultValue = AnyCodable(defaultValueNumber)
            case .duration:
                defaultValue = AnyCodable(Int(defaultValueNumber))
            case .boolean:
                defaultValue = AnyCodable(defaultValueBool)
            case .date:
                defaultValue = nil // Not supported
            }
        }

        if let existing = propertyDefinition {
            // Update existing
            existing.label = label
            existing.options = propertyType == .select ? options : []
            existing.defaultValue = defaultValue
            existing.updatedAt = Date()
        } else {
            // Create new
            let maxOrder = eventType.propertyDefinitions?.map { $0.displayOrder }.max() ?? -1
            let newDefinition = PropertyDefinition(
                eventTypeId: eventType.id,
                key: key,
                label: label,
                propertyType: propertyType,
                options: propertyType == .select ? options : [],
                defaultValue: defaultValue,
                displayOrder: maxOrder + 1
            )
            modelContext.insert(newDefinition)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: EventType.self, PropertyDefinition.self, configurations: config)

    let eventType = EventType(name: "Workout", colorHex: "#FF5733", iconName: "figure.run")
    container.mainContext.insert(eventType)

    let prop1 = PropertyDefinition(
        eventTypeId: eventType.id,
        key: "duration",
        label: "Duration",
        propertyType: .duration,
        displayOrder: 0
    )
    let prop2 = PropertyDefinition(
        eventTypeId: eventType.id,
        key: "intensity",
        label: "Intensity",
        propertyType: .select,
        options: ["Low", "Medium", "High"],
        displayOrder: 1
    )

    container.mainContext.insert(prop1)
    container.mainContext.insert(prop2)

    return NavigationView {
        PropertyDefinitionListView(eventType: eventType)
    }
    .modelContainer(container)
}
