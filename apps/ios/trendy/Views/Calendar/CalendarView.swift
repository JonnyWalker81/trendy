//
//  CalendarView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

enum CalendarViewMode: String, CaseIterable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
}

struct CalendarView: View {
    @Environment(EventStore.self) private var eventStore
    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    @State private var viewMode: CalendarViewMode = .month
    @State private var currentYear = Date()
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let yearColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let quarterColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    viewModeSelector
                    
                    switch viewMode {
                    case .month:
                        VStack(spacing: 20) {
                            monthHeader
                            weekdayHeader
                            calendarGrid
                            selectedDateEvents
                        }
                    case .quarter:
                        quarterView
                    case .year:
                        yearView
                    }
                }
                .padding()
            }
            .navigationTitle("Calendar")
            .task {
                await eventStore.fetchData()
            }
        }
    }
    
    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Text(currentMonth, format: .dateTime.month(.wide).year())
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var weekdayHeader: some View {
        LazyVGrid(columns: columns) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(daysInMonth(), id: \.self) { date in
                if let date = date {
                    CalendarDayView(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        events: eventStore.events(on: date)
                    ) {
                        selectedDate = date
                    }
                } else {
                    Color.clear
                        .frame(height: 50)
                }
            }
        }
    }
    
    private var selectedDateEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Events on \(selectedDate, format: .dateTime.weekday().month().day())")
                .font(.headline)
            
            let events = eventStore.events(on: selectedDate)
            
            if events.isEmpty {
                Text("No events on this day")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { event in
                    EventRowView(event: event)
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
    
    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
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
    
    private var viewModeSelector: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
    }
    
    private var quarterView: some View {
        VStack(spacing: 20) {
            // Quarter navigation
            HStack {
                Button {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: -3, to: currentMonth) ?? currentMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                
                Spacer()
                
                Text(quarterTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: 3, to: currentMonth) ?? currentMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
            }
            
            // Three months grid
            LazyVGrid(columns: quarterColumns, spacing: 12) {
                ForEach(0..<3) { offset in
                    if let monthDate = calendar.date(byAdding: .month, value: offset, to: startOfQuarter) {
                        CompactMonthView(
                            month: monthDate,
                            events: eventStore.events,
                            onDayTap: { date in
                                selectedDate = date
                                viewMode = .month
                                currentMonth = date
                            }
                        )
                    }
                }
            }
            
            if viewMode == .quarter {
                selectedDateEvents
            }
        }
    }
    
    private var yearView: some View {
        VStack(spacing: 20) {
            // Year navigation
            HStack {
                Button {
                    withAnimation {
                        currentYear = calendar.date(byAdding: .year, value: -1, to: currentYear) ?? currentYear
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                
                Spacer()
                
                Text(currentYear, format: .dateTime.year())
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
                    withAnimation {
                        currentYear = calendar.date(byAdding: .year, value: 1, to: currentYear) ?? currentYear
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
            }
            
            // 12 months grid
            LazyVGrid(columns: yearColumns, spacing: 12) {
                ForEach(0..<12) { month in
                    if let monthDate = calendar.date(byAdding: .month, value: month, to: startOfYear) {
                        CompactMonthView(
                            month: monthDate,
                            events: eventStore.events,
                            onDayTap: { date in
                                selectedDate = date
                                viewMode = .month
                                currentMonth = date
                            }
                        )
                    }
                }
            }
        }
    }
    
    private var startOfQuarter: Date {
        let month = calendar.component(.month, from: currentMonth)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        let year = calendar.component(.year, from: currentMonth)
        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth)) ?? currentMonth
    }
    
    private var quarterTitle: String {
        let month = calendar.component(.month, from: currentMonth)
        let quarter = ((month - 1) / 3) + 1
        let year = calendar.component(.year, from: currentMonth)
        return "Q\(quarter) \(year)"
    }
    
    private var startOfYear: Date {
        let year = calendar.component(.year, from: currentYear)
        return calendar.date(from: DateComponents(year: year, month: 1)) ?? currentYear
    }
}