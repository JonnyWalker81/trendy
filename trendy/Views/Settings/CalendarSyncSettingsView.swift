//
//  CalendarSyncSettingsView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import EventKit

struct CalendarSyncSettingsView: View {
    @EnvironmentObject private var calendarManager: CalendarManager
    @Environment(EventStore.self) private var eventStore
    @State private var showingPermissionAlert = false
    
    var body: some View {
        @Bindable var eventStore = eventStore
        
        Form {
            Section {
                Toggle("Sync with Calendar", isOn: $eventStore.syncWithCalendar)
                    .disabled(!calendarManager.isAuthorized)
                
                if !calendarManager.isAuthorized {
                    Label {
                        Text(authorizationStatusText)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: authorizationStatusIcon)
                            .foregroundColor(authorizationStatusColor)
                    }
                    
                    if calendarManager.authorizationStatus == .notDetermined {
                        Button("Grant Calendar Access") {
                            Task {
                                let granted = await calendarManager.requestAccess()
                                if !granted {
                                    showingPermissionAlert = true
                                }
                            }
                        }
                    } else if calendarManager.authorizationStatus == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Calendar Integration")
            } footer: {
                Text("When enabled, events created in Trendy will automatically be added to your system calendar.")
            }
            
            if calendarManager.isAuthorized {
                Section("Available Calendars") {
                    ForEach(calendarManager.getAvailableCalendars(), id: \.calendarIdentifier) { calendar in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            Spacer()
                            if calendar.isSubscribed {
                                Text("Subscribed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendar Sync")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Calendar access was denied. Please enable it in Settings to sync your events.")
        }
    }
    
    private var authorizationStatusText: String {
        switch calendarManager.authorizationStatus {
        case .notDetermined:
            return "Calendar access not requested"
        case .denied:
            return "Calendar access denied"
        case .restricted:
            return "Calendar access restricted"
        case .fullAccess:
            return "Full calendar access granted"
        case .writeOnly:
            return "Write-only calendar access"
        @unknown default:
            return "Unknown status"
        }
    }
    
    private var authorizationStatusIcon: String {
        switch calendarManager.authorizationStatus {
        case .notDetermined:
            return "questionmark.circle"
        case .denied, .restricted:
            return "xmark.circle"
        case .fullAccess, .writeOnly:
            return "checkmark.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    private var authorizationStatusColor: Color {
        switch calendarManager.authorizationStatus {
        case .notDetermined:
            return .orange
        case .denied, .restricted:
            return .red
        case .fullAccess, .writeOnly:
            return .green
        @unknown default:
            return .gray
        }
    }
}