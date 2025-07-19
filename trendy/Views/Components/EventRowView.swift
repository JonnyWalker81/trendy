//
//  EventRowView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct EventRowView: View {
    let event: Event
    
    var body: some View {
        HStack(spacing: 12) {
            if let eventType = event.eventType {
                Circle()
                    .fill(eventType.color)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: eventType.iconName)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.eventType?.name ?? "Unknown")
                        .font(.headline)
                    
                    Spacer()
                    
                    if event.isAllDay {
                        Text("All day")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(event.timestamp, format: .dateTime.hour().minute())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}