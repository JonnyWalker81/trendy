# Calendar Permissions Issue - Investigation and Solution

## Problem Summary
The Trendy app is unable to show the calendar permission dialog when users try to import events from their iOS Calendar. Debug logs show:
```
DEBUG: Current authorization status: 0 (not determined)
DEBUG: Calendar access granted: false
```

## Root Cause Analysis

### Investigation Findings
1. **Info.plist Configuration**: The project has a custom `trendy-Info.plist` file with the correct permission keys:
   - `NSCalendarsUsageDescription`
   - `NSCalendarsFullAccessUsageDescription`

2. **Code Implementation**: The `CalendarImportManager` correctly requests permissions using:
   - iOS 17+ API: `requestFullAccessToEvents()`
   - Legacy API: `requestAccess(to: .event)`

3. **Build Configuration Issue**: The project is configured with `GENERATE_INFOPLIST_FILE = YES`, which means:
   - Xcode automatically generates an Info.plist during build
   - The custom `trendy-Info.plist` file is ignored
   - Calendar permissions are not included in the built app

## Solution

### Option 1: Quick Fix (Recommended)
Run the provided Python script to automatically add calendar permissions to the project:

```bash
python3 fix_calendar_permissions.py
```

This script will:
1. Create a backup of your project file
2. Add the calendar permission keys to all build configurations
3. Provide instructions for rebuilding the app

### Option 2: Manual Fix in Xcode
1. Open `trendy.xcodeproj` in Xcode
2. Select the "trendy" target
3. Go to the "Build Settings" tab
4. Search for "Info.plist"
5. Add these keys under "Info.plist Values":
   - Key: `NSCalendarsUsageDescription`
   - Value: `This app needs access to your calendar to import events for tracking and visualization.`
   - Key: `NSCalendarsFullAccessUsageDescription`  
   - Value: `This app needs full access to your calendar to import events for tracking and visualization.`

### Option 3: Use Custom Info.plist
1. In Xcode, select the "trendy" target
2. Go to "Build Settings"
3. Search for "Generate Info.plist File"
4. Change `GENERATE_INFOPLIST_FILE` from `YES` to `NO`
5. Search for "Info.plist File"
6. Set `INFOPLIST_FILE` to `trendy/trendy-Info.plist`

## Technical Details

### Modern Xcode Behavior
Starting with recent Xcode versions, the recommended approach for Info.plist values is:
- Keep `GENERATE_INFOPLIST_FILE = YES` (default)
- Add Info.plist entries as build settings with `INFOPLIST_KEY_` prefix
- This allows Xcode to manage the Info.plist generation while including custom values

### Permission Key Format
In the project.pbxproj file, calendar permissions are added as:
```
INFOPLIST_KEY_NSCalendarsUsageDescription = "Your description here";
INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription = "Your description here";
```

## Verification Steps

After applying the fix:
1. Clean build folder (Cmd+Shift+K in Xcode)
2. Delete the app from simulator/device
3. Build and run the app
4. Navigate to Settings → Import from Calendar
5. The permission dialog should appear when accessing calendar

## Troubleshooting

If the permission dialog still doesn't appear:
1. Check the built app's Info.plist:
   ```bash
   cat build/Release-iphoneos/trendy.app/Info.plist | grep -A 1 "NSCalendar"
   ```
2. Reset simulator permissions:
   - Device → Erase All Content and Settings
3. Check for any privacy-related warnings in Xcode console
4. Ensure you're testing on iOS 17+ for full calendar access support

## Related Files
- `/trendy/trendy-Info.plist` - Custom Info.plist (currently unused)
- `/trendy/Utilities/CalendarImportManager.swift` - Permission request code
- `/trendy/Views/Settings/CalendarImportView.swift` - UI for calendar import
- `trendy.xcodeproj/project.pbxproj` - Project configuration

## Additional Notes
- The app correctly handles permission denial with "Open Settings" button
- Test data button is available in DEBUG builds for testing without permissions
- All permission handling code follows iOS best practices