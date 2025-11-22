//
//  PropertyFieldView.swift
//  trendy
//
//  SwiftUI component for rendering a single property input field
//

import SwiftUI

/// View for rendering a single property input field based on its type
struct PropertyFieldView: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue?

    @State private var textValue: String = ""
    @State private var numberValue: String = ""
    @State private var boolValue: Bool = false
    @State private var dateValue: Date = Date()
    @State private var selectValue: String = ""
    @State private var durationMinutes: Int = 0
    @State private var urlValue: String = ""
    @State private var emailValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(definition.label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            switch definition.propertyType {
            case .text:
                TextField("Enter text", text: $textValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: textValue) { _, newValue in
                        updateValue(type: .text, value: newValue)
                    }

            case .number:
                TextField("Enter number", text: $numberValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
                    .onChange(of: numberValue) { _, newValue in
                        if let doubleValue = Double(newValue) {
                            updateValue(type: .number, value: doubleValue)
                        }
                    }

            case .boolean:
                Toggle(isOn: $boolValue) {
                    Text("")
                }
                .onChange(of: boolValue) { _, newValue in
                    updateValue(type: .boolean, value: newValue)
                }

            case .date:
                DatePicker(
                    "",
                    selection: $dateValue,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .onChange(of: dateValue) { _, newValue in
                    updateValue(type: .date, value: newValue)
                }

            case .select:
                Picker("", selection: $selectValue) {
                    Text("Select...").tag("")
                    ForEach(definition.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectValue) { _, newValue in
                    if !newValue.isEmpty {
                        updateValue(type: .select, value: newValue)
                    }
                }

            case .duration:
                HStack {
                    TextField("Minutes", value: $durationMinutes, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .onChange(of: durationMinutes) { _, newValue in
                            // Store as seconds
                            updateValue(type: .duration, value: Double(newValue * 60))
                        }
                    Text("minutes")
                        .foregroundColor(.secondary)
                }

            case .url:
                TextField("https://example.com", text: $urlValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .onChange(of: urlValue) { _, newValue in
                        updateValue(type: .url, value: newValue)
                    }

            case .email:
                TextField("email@example.com", text: $emailValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .onChange(of: emailValue) { _, newValue in
                        updateValue(type: .email, value: newValue)
                    }
            }
        }
        .onAppear {
            loadInitialValue()
        }
    }

    // MARK: - Helper Methods

    /// Load the initial value from the binding
    private func loadInitialValue() {
        guard let currentValue = value else {
            // Set default value if defined
            if let defaultValue = definition.defaultValue {
                loadDefaultValue(defaultValue)
            }
            return
        }

        switch definition.propertyType {
        case .text:
            textValue = currentValue.stringValue ?? ""
        case .number:
            if let num = currentValue.doubleValue {
                numberValue = String(num)
            } else if let num = currentValue.intValue {
                numberValue = String(num)
            }
        case .boolean:
            boolValue = currentValue.boolValue ?? false
        case .date:
            dateValue = currentValue.dateValue ?? Date()
        case .select:
            selectValue = currentValue.stringValue ?? ""
        case .duration:
            // Duration is stored in seconds, convert to minutes for display
            if let seconds = currentValue.doubleValue {
                durationMinutes = Int(seconds / 60)
            } else {
                durationMinutes = 0
            }
        case .url:
            urlValue = currentValue.stringValue ?? ""
        case .email:
            emailValue = currentValue.stringValue ?? ""
        }
    }

    /// Load default value from property definition
    private func loadDefaultValue(_ defaultValue: AnyCodable) {
        switch definition.propertyType {
        case .text, .url, .email, .select:
            if let str = defaultValue.value as? String {
                switch definition.propertyType {
                case .text: textValue = str
                case .url: urlValue = str
                case .email: emailValue = str
                case .select: selectValue = str
                default: break
                }
                updateValue(type: definition.propertyType, value: str)
            }
        case .number:
            if let num = defaultValue.value as? Double {
                numberValue = String(num)
                updateValue(type: .number, value: num)
            } else if let num = defaultValue.value as? Int {
                numberValue = String(num)
                updateValue(type: .number, value: num)
            }
        case .boolean:
            if let bool = defaultValue.value as? Bool {
                boolValue = bool
                updateValue(type: .boolean, value: bool)
            }
        case .date:
            if let dateString = defaultValue.value as? String,
               let date = ISO8601DateFormatter().date(from: dateString) {
                dateValue = date
                updateValue(type: .date, value: date)
            }
        case .duration:
            // Default value may be in minutes (user input) or seconds (stored value)
            if let seconds = defaultValue.value as? Double {
                durationMinutes = Int(seconds / 60)
                updateValue(type: .duration, value: seconds)
            } else if let minutes = defaultValue.value as? Int {
                durationMinutes = minutes
                updateValue(type: .duration, value: Double(minutes * 60))
            }
        }
    }

    /// Update the binding value
    private func updateValue(type: PropertyType, value: Any) {
        self.value = PropertyValue(type: type, value: value)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PropertyFieldView(
            definition: PropertyDefinition(
                eventTypeId: UUID(),
                key: "test_text",
                label: "Text Field",
                propertyType: .text
            ),
            value: .constant(nil)
        )

        PropertyFieldView(
            definition: PropertyDefinition(
                eventTypeId: UUID(),
                key: "test_number",
                label: "Number Field",
                propertyType: .number
            ),
            value: .constant(nil)
        )

        PropertyFieldView(
            definition: PropertyDefinition(
                eventTypeId: UUID(),
                key: "test_bool",
                label: "Boolean Field",
                propertyType: .boolean
            ),
            value: .constant(nil)
        )

        PropertyFieldView(
            definition: PropertyDefinition(
                eventTypeId: UUID(),
                key: "test_select",
                label: "Select Field",
                propertyType: .select,
                options: ["Option 1", "Option 2", "Option 3"]
            ),
            value: .constant(nil)
        )
    }
    .padding()
}
