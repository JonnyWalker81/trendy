//
//  CreateEventTypeView.swift
//  trendy
//
//  Create first event type screen for onboarding
//

import SwiftUI

struct CreateEventTypeView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(EventStore.self) private var eventStore

    @State private var showCustomForm = false
    @State private var customName = ""
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
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("What will you track?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.dsForeground)

                    Text("Choose a template or create your own")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsMutedForeground)
                }
                .padding(.top, 40)

                // Progress Bar
                OnboardingProgressBar(
                    progress: OnboardingStep.createEventType.progress,
                    stepName: "Event Type",
                    stepNumber: 3,
                    totalSteps: 6
                )
                .padding(.horizontal, 24)

                if showCustomForm {
                    // Custom Event Type Form
                    customEventTypeForm
                } else {
                    // Template Grid
                    templateGrid
                }

                // Skip option (if user has existing event types)
                if !eventStore.eventTypes.isEmpty {
                    Button {
                        Task {
                            await viewModel.skipEventTypeCreation()
                        }
                    } label: {
                        Text("Skip - use existing event types")
                            .foregroundStyle(Color.dsLink)
                    }
                    .padding(.top, 8)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color.dsBackground)
        .disabled(viewModel.isLoading)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
    }

    // MARK: - Template Grid

    private var templateGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(EventTypeTemplate.templates) { template in
                TemplateCard(template: template) {
                    if template.isCustom {
                        withAnimation {
                            showCustomForm = true
                        }
                    } else {
                        Task {
                            await viewModel.createEventType(from: template)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Custom Event Type Form

    private var customEventTypeForm: some View {
        VStack(spacing: 24) {
            // Back to templates
            Button {
                withAnimation {
                    showCustomForm = false
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back to templates")
                }
                .foregroundStyle(Color.dsLink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            VStack(spacing: 20) {
                // Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.headline)
                        .foregroundStyle(Color.dsForeground)

                    TextField("e.g., Meditation", text: $customName)
                        .padding()
                        .background(Color.dsCard)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.dsBorder, lineWidth: 1)
                        )
                }

                // Color Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.headline)
                        .foregroundStyle(Color.dsForeground)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.dsForeground, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }

                // Icon Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.headline)
                        .foregroundStyle(Color.dsForeground)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? Color.dsAccent : Color.clear)
                                )
                                .foregroundStyle(selectedIcon == icon ? Color.dsPrimary : Color.dsMutedForeground)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                }

                // Preview
                VStack(spacing: 12) {
                    Text("Preview")
                        .font(.headline)
                        .foregroundStyle(Color.dsForeground)

                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(selectedColor)
                            .clipShape(Circle())

                        Text(customName.isEmpty ? "Your Event Type" : customName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.dsForeground)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.dsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.dsDestructive)
                }

                // Create Button
                Button {
                    Task {
                        await viewModel.createCustomEventType(
                            name: customName,
                            colorHex: selectedColor.hexString,
                            iconName: selectedIcon
                        )
                    }
                } label: {
                    Text("Create Event Type")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(!customName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.dsPrimary : Color.dsSecondary)
                        .foregroundStyle(!customName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.dsPrimaryForeground : Color.dsSecondaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: EventTypeTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: template.iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(template.color)
                    .clipShape(Circle())

                Text(template.name)
                    .font(.headline)
                    .foregroundStyle(Color.dsForeground)

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(Color.dsMutedForeground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.dsCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.dsBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Progress Indicator

struct ProgressIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                if step < currentStep {
                    // Completed step
                    Circle()
                        .fill(Color.dsPrimary)
                        .frame(width: 8, height: 8)
                } else if step == currentStep {
                    // Current step
                    Capsule()
                        .fill(Color.dsPrimary)
                        .frame(width: 24, height: 8)
                } else {
                    // Future step
                    Circle()
                        .fill(Color.dsBorder)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

#Preview {
    let previewSupabaseConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewAPIConfig = APIConfiguration(baseURL: "http://127.0.0.1:8080/api/v1")
    let previewSupabase = SupabaseService(configuration: previewSupabaseConfig)
    let previewAPIClient = APIClient(configuration: previewAPIConfig, supabaseService: previewSupabase)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)
    let eventStore = EventStore(apiClient: previewAPIClient)

    CreateEventTypeView(viewModel: viewModel)
        .environment(eventStore)
        .preferredColorScheme(.dark)
}
