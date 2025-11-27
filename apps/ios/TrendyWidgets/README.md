# Trendy Widgets - Setup Instructions

This document provides instructions for adding the TrendyWidgets extension to the Xcode project.

## Prerequisites

- Xcode 15.0+
- iOS 17.0+ deployment target
- Apple Developer account (for App Group capability)

## Step 1: Add Widget Extension Target in Xcode

1. Open `trendy.xcodeproj` in Xcode
2. Go to **File → New → Target...**
3. Select **Widget Extension** under iOS
4. Configure the target:
   - **Product Name**: `TrendyWidgets`
   - **Team**: Select your team
   - **Bundle Identifier**: `com.memento.trendy.TrendyWidgets`
   - **Include Live Activity**: No (uncheck)
   - **Include Configuration App Intent**: Yes (check)
5. Click **Finish**
6. When prompted to activate the scheme, click **Activate**

## Step 2: Delete Generated Files

Xcode generates template files that we'll replace:

1. In the Project Navigator, expand `TrendyWidgets`
2. Delete the generated files:
   - `TrendyWidgets.swift`
   - `TrendyWidgetsBundle.swift`
   - `AppIntent.swift`
3. Keep the `Assets.xcassets` and `Info.plist`

## Step 3: Add Existing Widget Files

1. Right-click on `TrendyWidgets` in Project Navigator
2. Select **Add Files to "TrendyWidgets"...**
3. Navigate to `apps/ios/TrendyWidgets/`
4. Select all the folders and files:
   - `TrendyWidgetsBundle.swift`
   - `Shared/`
   - `DataManager/`
   - `Intents/`
   - `Providers/`
   - `Views/`
5. Ensure **"Copy items if needed"** is UNCHECKED
6. Ensure **"TrendyWidgets"** target is checked
7. Click **Add**

## Step 4: Add Main App Files to Widget Target

The widget needs access to the Event and EventType models:

1. In Project Navigator, find these files in the `trendy` target:
   - `Models/Event.swift`
   - `Models/EventType.swift`
   - `Models/PropertyValue.swift`
   - `Models/PropertyDefinition.swift`
2. For each file, select it and open the **File Inspector** (right panel)
3. Under **Target Membership**, check **TrendyWidgets**

## Step 5: Configure App Group Capability

### For Main App Target:
1. Select the `trendy` project in Project Navigator
2. Select the `trendy` target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **App Groups**
6. Add group: `group.com.memento.trendy`

### For Widget Extension Target:
1. Select the `TrendyWidgets` target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Add the same group: `group.com.memento.trendy`

## Step 6: Update Widget Info.plist (if needed)

The widget's `Info.plist` should have:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
</dict>
```

## Step 7: Build and Test

1. Select the main app scheme (`trendy`)
2. Build and run on a device or simulator
3. Long-press on the home screen to enter jiggle mode
4. Tap the **+** button to add widgets
5. Search for "Trendy" to find your widgets

## Troubleshooting

### "App Group container not found" error
- Ensure both targets have the App Groups capability enabled
- Verify the App Group identifier matches exactly: `group.com.memento.trendy`
- Try cleaning the build folder (Cmd+Shift+K)

### Widgets not appearing in widget gallery
- Make sure the widget extension target is included in the build
- Check that the bundle identifier is correct
- Restart the device/simulator

### Data not syncing between app and widget
- Both targets must use the same App Group
- Check that `trendyApp.swift` uses the shared container URL
- Verify `WidgetCenter.shared.reloadAllTimelines()` is called after data changes

### Widget shows stale data
- Widgets have limited refresh rates (every 15-60 minutes)
- The app calls `WidgetCenter.shared.reloadAllTimelines()` after data mutations
- Force refresh by removing and re-adding the widget

## Widget Types

| Widget | Size | Description |
|--------|------|-------------|
| Quick Log | Small | Single EventType, tap to log |
| Quick Log Grid | Medium | 1-6 EventTypes, tap any to log |
| Dashboard | Large | Quick log + recent events + stats |
| Quick Log | Circular (Lock Screen) | Icon + count, tap to log |
| Streak & Stats | Rectangular (Lock Screen) | Name, streak, last logged |
| Quick Stat | Inline (Lock Screen) | Single line above time |

## File Structure

```
TrendyWidgets/
├── TrendyWidgetsBundle.swift    # Widget bundle entry
├── TrendyWidgets.entitlements   # App Group entitlement
├── Shared/
│   └── AppGroupContainer.swift  # Shared container config
├── DataManager/
│   └── WidgetDataManager.swift  # SwiftData access
├── Intents/
│   ├── QuickLogIntent.swift     # Interactive logging
│   └── ConfigurationIntent.swift # Widget configuration
├── Providers/
│   ├── QuickLogProvider.swift   # Single type provider
│   ├── MultiTypeProvider.swift  # Grid provider
│   └── DashboardProvider.swift  # Large widget provider
└── Views/
    ├── HomeScreen/
    │   ├── SmallWidget.swift
    │   ├── MediumWidget.swift
    │   └── LargeWidget.swift
    └── LockScreen/
        ├── CircularWidget.swift
        ├── RectangularWidget.swift
        └── InlineWidget.swift
```
