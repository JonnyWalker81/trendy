# Trendy

<div align="center">
  <img src="trendy/Assets.xcassets/AppIcon.appiconset/trendyAppIcon 1.png" width="120" height="120" alt="Trendy App Icon">
</div>

A modern iOS app for tracking personal events and visualizing patterns over time. Built with SwiftUI and SwiftData.

## Features

### 📊 Quick Event Tracking
- Tap colorful bubbles to instantly record events
- Long press to add notes
- Haptic feedback for confirmation
- Customizable event types with colors and icons

### 📅 Calendar Integration
- Import events from iOS Calendar
- Smart categorization of calendar events
- Selective import with checkboxes
- Support for all-day and multi-day events

### 📈 Analytics & Insights
- Track frequency and trends over time
- Interactive charts showing patterns
- Daily/weekly averages
- Trend analysis (increasing/decreasing/stable)

### 🔍 Multiple Views
- **Dashboard**: Quick access bubbles for tracking
- **Events List**: Chronological view with search
- **Calendar**: Month/Quarter/Year zoom levels
- **Analytics**: Charts and statistics
- **Settings**: Manage event types and import data

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

1. Clone the repository:
```bash
git clone git@github.com:JonnyWalker81/trendy.git
cd trendy
```

2. Open in Xcode:
```bash
open trendy.xcodeproj
```

3. Build and run (⌘R)

## App Icon

The app features a modern, colorful design that represents the bubble-based tracking interface. The icon adapts to both light and dark modes.

## Architecture

Trendy uses modern iOS development practices:

- **SwiftUI** for the user interface
- **SwiftData** for persistence
- **Swift Charts** for data visualization
- **EventKit** for calendar integration
- **@Observable** macro for state management
- **Async/await** for asynchronous operations

## Usage

### Getting Started
1. Launch the app
2. Create event types (Exercise, Medical, Work, etc.)
3. Tap bubbles to track events
4. View patterns in Calendar and Analytics

### Importing Calendar Events
1. Go to Settings → Import from Calendar
2. Grant calendar permissions
3. Select date range and calendars
4. Choose which events to import
5. Events are categorized automatically

### Viewing Analytics
1. Navigate to Analytics tab
2. Select an event type
3. Choose time range (Week/Month/Year)
4. View trends and statistics

## Privacy

- Calendar data is only accessed with your permission
- All data is stored locally on your device
- No data is sent to external servers

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available under the MIT license.