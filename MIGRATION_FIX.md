# SwiftData Migration Fix

## Issue
When adding new properties to the Event model (`isAllDay` and `endDate`), the app crashed with a migration error:
```
Validation error missing attribute values on mandatory destination attribute
```

## Root Cause
SwiftData couldn't migrate existing Event records because the new `isAllDay` property didn't have a default value in the model definition.

## Solution
Added default value to the `isAllDay` property in the Event model:
```swift
var isAllDay: Bool = false  // Added default value
```

This allows SwiftData to:
1. Migrate existing events with `isAllDay = false`
2. Create new events with the proper all-day status
3. Maintain backward compatibility

## Important Notes
- The `endDate` property was already optional (`Date?`) so it didn't cause issues
- Default values in SwiftData models are crucial for migration
- The initializer default parameter alone isn't sufficient for migration

## Testing
If you still encounter the error:
1. Delete the app from simulator/device
2. Clean build folder (⌘+⇧+K)
3. Rebuild and run

The app should now launch successfully with existing data intact.