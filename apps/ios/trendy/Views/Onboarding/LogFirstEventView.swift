//
//  LogFirstEventView.swift
//  trendy
//
//  Log first event screen for onboarding
//

import SwiftUI

struct LogFirstEventView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(EventStore.self) private var eventStore

    @State private var notes = ""
    @State private var showSuccess = false

    private var eventType: EventType? {
        viewModel.createdEventType ?? eventStore.eventTypes.first
    }

    var body: some View {
        VStack(spacing: 24) {
            // Progress Bar at top
            OnboardingProgressBar(
                progress: OnboardingStep.logFirstEvent.progress,
                stepName: "First Event",
                stepNumber: 4,
                totalSteps: 6
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()

            if showSuccess {
                // Success State
                successView
            } else {
                // Log Event State
                logEventView
            }

            Spacer()

            // Skip option
            if !showSuccess {
                Button {
                    Task {
                        await viewModel.skipFirstEvent()
                    }
                } label: {
                    Text("Skip for now")
                        .foregroundStyle(Color.dsMutedForeground)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.dsBackground)
        .disabled(viewModel.isLoading && !showSuccess)
    }

    // MARK: - Log Event View

    private var logEventView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Log your first event")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsForeground)

                if let eventType = eventType {
                    Text("Let's track your first \(eventType.name)")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsMutedForeground)
                }
            }

            // Event Type Display
            if let eventType = eventType {
                VStack(spacing: 16) {
                    Image(systemName: eventType.iconName)
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .frame(width: 100, height: 100)
                        .background(eventType.color)
                        .clipShape(Circle())
                        .shadow(color: eventType.color.opacity(0.5), radius: 10)

                    Text(eventType.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsForeground)

                    Text("Now")
                        .font(.headline)
                        .foregroundStyle(Color.dsPrimary)
                }
                .padding(.vertical, 20)
            }

            // Optional Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a note (optional)")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsMutedForeground)

                TextField("How are you feeling?", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .padding()
                    .background(Color.dsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.dsBorder, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 32)

            // Log Button
            Button {
                Task {
                    await logEvent()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.dsPrimaryForeground)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log Now")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .background(Color.dsPrimary)
            .foregroundStyle(Color.dsPrimaryForeground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.dsSuccess)
                .scaleEffect(showSuccess ? 1.0 : 0.5)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showSuccess)

            Text("First event logged!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.dsForeground)

            if let eventType = eventType {
                Text("You've started tracking \(eventType.name)")
                    .font(.body)
                    .foregroundStyle(Color.dsMutedForeground)
            }
        }
        .onAppear {
            // Auto-advance after showing success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task {
                    await viewModel.advanceToNextStep()
                }
            }
        }
    }

    // MARK: - Actions

    private func logEvent() async {
        await viewModel.logFirstEvent(notes: notes.isEmpty ? nil : notes)

        // Show success animation briefly
        withAnimation {
            showSuccess = true
        }
    }
}

#Preview {
    @Previewable @State var previewSupabaseConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    @Previewable @State var previewAPIConfig = APIConfiguration(baseURL: "http://127.0.0.1:8080/api/v1")

    let previewSupabase = SupabaseService(configuration: previewSupabaseConfig)
    let previewAPIClient = APIClient(configuration: previewAPIConfig, supabaseService: previewSupabase)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)
    let eventStore = EventStore(apiClient: previewAPIClient)

    LogFirstEventView(viewModel: viewModel)
        .environment(eventStore)
        .preferredColorScheme(.dark)
}
