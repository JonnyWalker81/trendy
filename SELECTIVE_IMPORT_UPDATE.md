# Selective Calendar Import Feature Update

## Summary
Updated the calendar import feature to allow users to selectively choose which event types to import, rather than importing all events automatically.

## Changes Made

### 1. **Model Update** (ImportMapping.swift:37)
- Added `isSelected: Bool = true` property to `EventTypeMapping`
- Default is `true` to maintain backward compatibility

### 2. **UI Updates** (CalendarImportView.swift)

#### Event Type Row Changes:
- Changed `EventTypeMappingRow` to use `@Binding` for two-way data binding
- Added toggle switch to each event type row
- Event type details (New/Existing badge) only show when selected

#### Preview Section Enhancements:
- Added "Selected Events" count showing number of events to be imported
- Added "Select All" and "Select None" buttons for bulk operations
- Buttons intelligently disable when all items are already selected/deselected

#### Import Logic:
- Modified `performImport()` to only process selected event types (line 415)
- Updated `canProceed` logic to ensure at least one event type is selected

## User Experience

### Import Flow:
1. User selects date range
2. User selects calendars
3. **New**: Preview screen shows all event types with toggles
4. User can:
   - Toggle individual event types on/off
   - Use "Select All" or "Select None" for bulk selection
   - See real-time count of selected events
5. Only selected event types are imported

### Visual Feedback:
- Selected event types show full details (New/Existing badge)
- Deselected event types appear simplified
- Selected events count prominently displayed in blue
- Next button disabled if no events selected

## Benefits
- Users have full control over what gets imported
- Prevents unwanted event types from cluttering the app
- Reduces import time for users with many calendar events
- Clear visual feedback about what will be imported

## Testing
1. Clean build folder in Xcode (⌘+⇧+K)
2. Run the app
3. Navigate to Settings → Import from Calendar
4. Test the selection toggles and verify only selected events import