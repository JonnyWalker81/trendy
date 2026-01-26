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
    @State private var logLines: [LogLine] = []
    @State private var isLoading = true
    @State private var showingShareSheet = false
    @State private var filterLevel: LogLineLevel? = nil

    private var filteredLines: [LogLine] {
        guard let filter = filterLevel else { return logLines }
        return logLines.filter { $0.level.severity >= filter.severity }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if logLines.isEmpty {
                ContentUnavailableView(
                    "Empty Log",
                    systemImage: "doc.text",
                    description: Text("This log file is empty.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                            LogLineView(line: line)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        filterLevel = nil
                    } label: {
                        Label("All Levels", systemImage: filterLevel == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(LogLineLevel.allCases, id: \.self) { level in
                        Button {
                            filterLevel = level
                        } label: {
                            Label("\(level.displayName) & Above", systemImage: filterLevel == level ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
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
        if let content = FileLogger.shared.readLogFile(at: file.url) {
            logLines = content.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { LogLine(rawLine: $0) }
        }
        isLoading = false
    }
}

// MARK: - Log Line Model

struct LogLine {
    let rawLine: String
    let timestamp: String
    let level: LogLineLevel
    let category: String
    let message: String

    init(rawLine: String) {
        self.rawLine = rawLine

        // Parse format: [timestamp] [LEVEL] [category] message
        // Example: [2026-01-26 10:30:45.123] [ERROR] [api] Request failed [endpoint=/events]

        let pattern = #"^\[([^\]]+)\] \[([^\]]+)\] \[([^\]]+)\] (.*)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: rawLine, range: NSRange(rawLine.startIndex..., in: rawLine)) {

            if let timestampRange = Range(match.range(at: 1), in: rawLine) {
                timestamp = String(rawLine[timestampRange])
            } else {
                timestamp = ""
            }

            if let levelRange = Range(match.range(at: 2), in: rawLine) {
                level = LogLineLevel(rawValue: String(rawLine[levelRange])) ?? .info
            } else {
                level = .info
            }

            if let categoryRange = Range(match.range(at: 3), in: rawLine) {
                category = String(rawLine[categoryRange])
            } else {
                category = ""
            }

            if let messageRange = Range(match.range(at: 4), in: rawLine) {
                message = String(rawLine[messageRange])
            } else {
                message = rawLine
            }
        } else {
            // Fallback for unparseable lines
            timestamp = ""
            level = .info
            category = ""
            message = rawLine
        }
    }
}

enum LogLineLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case notice = "NOTICE"
    case warning = "WARN"
    case error = "ERROR"
    case fault = "FAULT"

    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .primary
        case .notice: return .blue
        case .warning: return .orange
        case .error: return .red
        case .fault: return .purple
        }
    }

    var backgroundColor: Color {
        switch self {
        case .debug: return .clear
        case .info: return .clear
        case .notice: return .blue.opacity(0.1)
        case .warning: return .orange.opacity(0.15)
        case .error: return .red.opacity(0.15)
        case .fault: return .purple.opacity(0.2)
        }
    }

    var icon: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .notice: return "bell"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .fault: return "bolt.circle"
        }
    }

    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warning: return "Warning"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }

    var severity: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .warning: return 3
        case .error: return 4
        case .fault: return 5
        }
    }
}

// MARK: - Log Line View

struct LogLineView: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Level indicator
            Image(systemName: line.level.icon)
                .font(.system(size: 10))
                .foregroundStyle(line.level.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                // Timestamp and category
                HStack(spacing: 4) {
                    if !line.timestamp.isEmpty {
                        Text(line.timestamp)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if !line.category.isEmpty {
                        Text(line.category)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(line.level.color.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(line.level.color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                // Message
                Text(line.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.level == .debug ? .secondary : .primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.level.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
