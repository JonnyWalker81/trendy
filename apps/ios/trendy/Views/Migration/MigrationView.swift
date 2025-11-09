//
//  MigrationView.swift
//  trendy
//
//  View for displaying migration progress
//

import SwiftUI
import SwiftData

struct MigrationView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("migration_completed") private var migrationCompleted = false

    @State private var migrationManager: MigrationManager?
    @State private var hasMigrationStarted = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: migrationManager?.isComplete == true ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 80))
                .foregroundStyle(migrationManager?.isComplete == true ? .green : .blue)
                .symbolEffect(.bounce, value: migrationManager?.isComplete)

            // Title
            Text(migrationManager?.isComplete == true ? "Sync Complete!" : "Syncing Your Data")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status message
            if let manager = migrationManager {
                if let errorMessage = manager.errorMessage {
                    // Error state
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button {
                            Task {
                                try? await manager.retryMigration()
                            }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 32)
                    }
                } else if manager.isComplete {
                    // Success state
                    VStack(spacing: 8) {
                        Text("All your data has been synced to the cloud")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if manager.totalEventTypes > 0 || manager.totalEvents > 0 {
                            Text("\(manager.migratedEventTypes) event types • \(manager.migratedEvents) events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        completeMigration()
                    } label: {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                } else {
                    // Migration in progress
                    VStack(spacing: 16) {
                        Text(manager.progressText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        // Progress bar
                        ProgressView(value: manager.progress) {
                            HStack {
                                Text("Event Types:")
                                Spacer()
                                Text("\(manager.migratedEventTypes)/\(manager.totalEventTypes)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Text("Events:")
                                Spacer()
                                Text("\(manager.migratedEvents)/\(manager.totalEvents)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 32)
                    }
                }
            } else {
                // Loading state
                ProgressView()
                    .progressViewStyle(.circular)

                Text("Checking for local data...")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            if !hasMigrationStarted {
                startMigration()
            }
        }
    }

    private func startMigration() {
        hasMigrationStarted = true

        // Create migration manager
        let manager = MigrationManager(modelContext: modelContext)
        self.migrationManager = manager

        // Start migration
        Task {
            do {
                try await manager.performMigration()

                // If migration completes successfully and there was no data, auto-continue
                if manager.isComplete && manager.totalEventTypes == 0 && manager.totalEvents == 0 {
                    // No data to migrate, complete immediately
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay for UX
                    await MainActor.run {
                        completeMigration()
                    }
                }
            } catch {
                print("Migration error: \(error.localizedDescription)")
            }
        }
    }

    private func completeMigration() {
        migrationCompleted = true
    }
}

#Preview {
    MigrationView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
}
