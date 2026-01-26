//
//  LogExportView.swift
//  trendy
//
//  View for browsing, viewing, and exporting app logs.
//  Accessible from Debug Storage settings.
//

import SwiftUI
import UIKit

struct LogExportView: View {
    @State private var logFiles: [LogFileInfo] = []
    @State private var selectedFile: LogFileInfo?
    @State private var isLoading = true
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteSuccess = false

    var body: some View {
        List {
            if isLoading {
                loadingSection
            } else if logFiles.isEmpty {
                emptySection
            } else {
                filesSection
                actionsSection
            }
        }
        .navigationTitle("App Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    loadLogFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            loadLogFiles()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(
            "Delete All Logs?",
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all log files. This cannot be undone.")
        }
        .alert("Logs Deleted", isPresented: $showingDeleteSuccess) {
            Button("OK") {}
        } message: {
            Text("All log files have been deleted.")
        }
    }

    // MARK: - Sections

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Loading logs...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No Log Files")
                    .font(.headline)
                Text("Logs will appear here as the app runs. They are stored for up to 7 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var filesSection: some View {
        Section {
            ForEach(logFiles) { file in
                NavigationLink {
                    LogFileDetailView(file: file)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.body)
                            Text(file.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Log Files (\(logFiles.count))")
        } footer: {
            let totalSize = logFiles.reduce(0) { $0 + $1.size }
            Text("Total size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                exportAllLogs()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export All Logs")
                }
            }

            Button(role: .destructive) {
                showingDeleteAllConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete All Logs")
                }
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Export creates a single file combining all logs for easy sharing with support.")
        }
    }

    // MARK: - Actions

    private func loadLogFiles() {
        isLoading = true
        logFiles = FileLogger.shared.getLogFiles()
        isLoading = false
    }

    private func exportAllLogs() {
        if let url = FileLogger.shared.createExportFile() {
            exportURL = url
            showingShareSheet = true
        }
    }

    private func deleteAllLogs() {
        FileLogger.shared.deleteAllLogs()
        loadLogFiles()
        showingDeleteSuccess = true
    }
}

// MARK: - Log File Detail View

struct LogFileDetailView: View {
    let file: LogFileInfo
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var showingShareSheet = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if content.isEmpty {
                ContentUnavailableView(
                    "Empty Log",
                    systemImage: "doc.text",
                    description: Text("This log file is empty.")
                )
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            loadContent()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [file.url])
        }
    }

    private func loadContent() {
        isLoading = true
        content = FileLogger.shared.readLogFile(at: file.url) ?? ""
        isLoading = false
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        LogExportView()
    }
}
