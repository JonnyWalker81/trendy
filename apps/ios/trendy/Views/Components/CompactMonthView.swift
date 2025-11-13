//
//  CompactMonthView.swift
//  trendy
//
//  Created by Assistant on 7/19/25.
//

import SwiftUI

struct CompactMonthView: View {
    let month: Date
    let events: [Event]
    let onDayTap: (Date) -> Void
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    
    var body: some View {
        VStack(spacing: 4) {
            // Month header
            Text(month, format: .dateTime.month(.abbreviated))
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            
            // Weekday headers
            HStack(spacing: 2) {
                ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days grid
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        CompactDayView(
                            date: date,
                            eventTypes: eventTypes(on: date),
                            isToday: calendar.isDateInToday(date)
                        ) {
                            onDayTap(date)
                        }
                    } else {
                        Color.clear
                            .frame(height: 20)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.cardBackground)
        .cornerRadius(8)
    }
    
    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        let startDate = monthInterval.start
        let endDate = monthInterval.end
        
        let numberOfDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let firstWeekday = calendar.component(.weekday, from: startDate) - 1
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        
        for dayOffset in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
    
    private func eventTypes(on date: Date) -> [EventType] {
        let dayEvents = events.filter { event in
            if event.isAllDay {
                if let endDate = event.endDate {
                    return date >= calendar.startOfDay(for: event.timestamp) && 
                           date <= calendar.startOfDay(for: endDate)
                } else {
                    return calendar.isDate(event.timestamp, inSameDayAs: date)
                }
            } else {
                return calendar.isDate(event.timestamp, inSameDayAs: date)
            }
        }
        
        let types = dayEvents.compactMap { $0.eventType }
        return Array(Set(types)).sorted { $0.name < $1.name }
    }
}

struct CompactDayView: View {
    let date: Date
    let eventTypes: [EventType]
    let isToday: Bool
    let onTap: () -> Void
    
    private var hasEvents: Bool {
        !eventTypes.isEmpty
    }
    
    var body: some View {
        ZStack {
            // Background
            if isToday {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 22, height: 22)
            }
            
            // Day number
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 10, weight: isToday ? .semibold : .regular))
                .foregroundColor(isToday ? .white : .primary)
            
            // Event indicators
            if hasEvents {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 1) {
                        ForEach(eventTypes.prefix(3)) { eventType in
                            Circle()
                                .fill(eventType.color)
                                .frame(width: 4, height: 4)
                                .overlay(
                                    Circle()
                                        .stroke(isToday ? Color.white.opacity(0.8) : Color.clear, lineWidth: 0.5)
                                )
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(width: 22, height: 22)
            }
            
            // Event count badge
            if eventTypes.count > 3 {
                Text("+\(eventTypes.count - 3)")
                    .font(.system(size: 6))
                    .foregroundColor(.white)
                    .padding(.horizontal, 2)
                    .background(Color.gray)
                    .cornerRadius(2)
                    .offset(x: 10, y: -10)
            }
        }
        .frame(width: 25, height: 25)
        .onTapGesture {
            onTap()
        }
    }
}