//
//  CalendarDayView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct CalendarDayView: View {
    let date: Date
    let isSelected: Bool
    let events: [Event]
    let onTap: () -> Void
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var eventTypes: [EventType] {
        let types = events.compactMap { $0.eventType }
        return Array(Set(types))
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
            
            if !events.isEmpty {
                HStack(spacing: 2) {
                    ForEach(eventTypes.prefix(3)) { eventType in
                        Circle()
                            .fill(eventType.color)
                            .frame(width: 6, height: 6)
                    }
                    
                    if eventTypes.count > 3 {
                        Text("+\(eventTypes.count - 3)")
                            .font(.system(size: 8))
                            .foregroundColor(isSelected ? .white : .secondary)
                    }
                }
            } else {
                Spacer()
                    .frame(height: 6)
            }
        }
        .frame(width: 40, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue : (isToday ? Color.blue.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday && !isSelected ? Color.blue : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
    }
}