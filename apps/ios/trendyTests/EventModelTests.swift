//
//  EventModelTests.swift
//  trendyTests
//
//  Production-grade tests for Event SwiftData model
//
//  SUT: Event (core event model with properties support)
//
//  Assumptions:
//  - Event is a SwiftData @Model class
//  - properties is a computed property backed by propertiesData (Data)
//  - Default values: isAllDay = false, sourceType = .manual
//  - Supports optional eventType relationship
//  - Calendar sync via calendarEventId is iOS-only (not synced to backend)
//
//  Covered Behaviors:
//  ✅ Event initialization with default values
//  ✅ Properties encoding/decoding (Data ↔ [String: PropertyValue])
//  ✅ All-day event logic (isAllDay, endDate)
//  ✅ Source type handling (.manual, .imported)
//  ✅ Optional fields (notes, externalId, originalTitle, calendarEventId)
//  ✅ EventType relationship
//
//  Intentionally Omitted:
//  - SwiftData persistence (tested in integration tests with ModelContext)
//  - EventStore business logic (tested in EventStoreTests)
//  - Calendar sync (tested in CalendarManager tests)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Suite

@Suite("Event Initialization")
struct EventInitializationTests {

    @Test("Event initializes with default values")
    func test_event_initWithDefaults_hasCorrectDefaults() {
        let now = Date()
        let event = Event(timestamp: now)

        #expect(event.timestamp == now, "timestamp should be set")
        #expect(event.notes == nil, "notes should default to nil")
        #expect(event.eventType == nil, "eventType should default to nil")
        #expect(event.sourceType == .manual, "sourceType should default to .manual")
        #expect(event.externalId == nil, "externalId should default to nil")
        #expect(event.originalTitle == nil, "originalTitle should default to nil")
        #expect(event.isAllDay == false, "isAllDay should default to false")
        #expect(event.endDate == nil, "endDate should default to nil")
        #expect(event.calendarEventId == nil, "calendarEventId should default to nil")
        #expect(event.properties.isEmpty, "properties should default to empty dictionary")
    }

    @Test("Event initializes with all parameters")
    func test_event_initWithAllParams_setsAllValues() {
        let timestamp = Date()
        let endDate = Date(timeIntervalSinceNow: 3600)
        let eventType = EventTypeFixture.makeEventType()
        let properties = ["key": PropertyValueFixture.makeTextProperty(value: "value")]

        let event = Event(
            timestamp: timestamp,
            eventType: eventType,
            notes: "Test notes",
            sourceType: .imported,
            externalId: "ext-123",
            originalTitle: "Original",
            isAllDay: true,
            endDate: endDate,
            calendarEventId: "cal-456",
            properties: properties
        )

        #expect(event.timestamp == timestamp, "timestamp should be set")
        #expect(event.eventType?.id == eventType.id, "eventType should be set")
        #expect(event.notes == "Test notes", "notes should be set")
        #expect(event.sourceType == .imported, "sourceType should be .imported")
        #expect(event.externalId == "ext-123", "externalId should be set")
        #expect(event.originalTitle == "Original", "originalTitle should be set")
        #expect(event.isAllDay == true, "isAllDay should be true")
        #expect(event.endDate == endDate, "endDate should be set")
        #expect(event.calendarEventId == "cal-456", "calendarEventId should be set")
        #expect(event.properties.count == 1, "properties should have 1 entry")
    }

    @Test("Event generates unique UUID on initialization")
    func test_event_initGeneratesUniqueUUID() {
        let event1 = Event(timestamp: Date())
        let event2 = Event(timestamp: Date())

        #expect(event1.id != event2.id, "Each event should have a unique UUID")
    }
}

@Suite("Event Properties (Custom Attributes)")
struct EventPropertiesTests {

    @Test("Event properties getter returns empty dict when propertiesData is nil")
    func test_event_properties_emptyWhenDataIsNil() {
        let event = Event(timestamp: Date())

        #expect(event.properties.isEmpty, "properties should be empty when propertiesData is nil")
    }

    @Test("Event properties getter decodes from propertiesData")
    func test_event_properties_decodesFromData() {
        let props = [
            "distance": PropertyValueFixture.makeNumberProperty(value: 5),
            "notes": PropertyValueFixture.makeTextProperty(value: "Great run")
        ]

        let event = Event(timestamp: Date(), properties: props)

        #expect(event.properties.count == 2, "properties should have 2 entries")
        #expect(event.properties["distance"] != nil, "properties should have 'distance' key")
        #expect(event.properties["notes"] != nil, "properties should have 'notes' key")
    }

    @Test("Event properties setter encodes to propertiesData")
    func test_event_properties_encodesToData() {
        var event = Event(timestamp: Date())

        event.properties = [
            "key": PropertyValueFixture.makeTextProperty(value: "value")
        ]

        #expect(event.propertiesData != nil, "propertiesData should be set after properties setter")
        #expect(event.properties.count == 1, "properties should have 1 entry")
    }

    @Test("Event properties roundtrip encoding/decoding")
    func test_event_properties_roundtrip() {
        let originalProps = [
            "text": PropertyValueFixture.makeTextProperty(value: "Hello"),
            "number": PropertyValueFixture.makeNumberProperty(value: 42),
            "boolean": PropertyValueFixture.makeBooleanProperty(value: true)
        ]

        var event = Event(timestamp: Date())
        event.properties = originalProps

        let retrievedProps = event.properties

        #expect(retrievedProps.count == 3, "Retrieved properties should have 3 entries")
        #expect(retrievedProps["text"]?.stringValue == "Hello", "text property should roundtrip")
        #expect(retrievedProps["number"]?.intValue == 42, "number property should roundtrip")
        #expect(retrievedProps["boolean"]?.boolValue == true, "boolean property should roundtrip")
    }

    @Test("Event properties with complex types")
    func test_event_properties_complexTypes() {
        let date = DeterministicDate.jan1_2024
        let props = [
            "date": PropertyValueFixture.makeDateProperty(value: date),
            "select": PropertyValueFixture.makeSelectProperty(value: "Option A")
        ]

        let event = Event(timestamp: Date(), properties: props)

        #expect(event.properties["date"] != nil, "date property should be set")
        #expect(event.properties["select"]?.stringValue == "Option A", "select property should be set")
    }

    @Test("Event properties empty dict encodes/decodes correctly")
    func test_event_properties_emptyDict_roundtrips() {
        var event = Event(timestamp: Date())
        event.properties = [:]

        // Empty dict should encode to Data and decode back to empty dict
        let retrieved = event.properties
        #expect(retrieved.isEmpty, "Empty properties dict should roundtrip")
    }
}

@Suite("Event All-Day Logic")
struct EventAllDayTests {

    @Test("Event with isAllDay false is a timed event")
    func test_event_isAllDayFalse_isTimedEvent() {
        let event = Event(timestamp: Date(), isAllDay: false)

        #expect(event.isAllDay == false, "isAllDay should be false")
        #expect(event.endDate == nil, "Timed event without duration has no endDate")
    }

    @Test("Event with isAllDay true is an all-day event")
    func test_event_isAllDayTrue_isAllDayEvent() {
        let event = Event(timestamp: Date(), isAllDay: true)

        #expect(event.isAllDay == true, "isAllDay should be true")
    }

    @Test("Event all-day with endDate is multi-day event")
    func test_event_allDay_withEndDate_isMultiDay() {
        let startDate = DeterministicDate.jan1_2024
        let endDate = DeterministicDate.make(year: 2024, month: 1, day: 3)  // 3 days

        let event = Event(
            timestamp: startDate,
            isAllDay: true,
            endDate: endDate
        )

        #expect(event.isAllDay == true, "isAllDay should be true")
        #expect(event.endDate == endDate, "endDate should be set")
    }

    @Test("Event timed with endDate has duration")
    func test_event_timed_withEndDate_hasDuration() {
        let startDate = Date()
        let endDate = Date(timeIntervalSinceNow: 3600)  // 1 hour later

        let event = Event(
            timestamp: startDate,
            isAllDay: false,
            endDate: endDate
        )

        #expect(event.isAllDay == false, "isAllDay should be false")
        #expect(event.endDate == endDate, "endDate should be set")
    }
}

@Suite("Event Source Type")
struct EventSourceTypeTests {

    @Test("Event with manual sourceType is user-created")
    func test_event_manualSourceType_isUserCreated() {
        let event = Event(timestamp: Date(), sourceType: .manual)

        #expect(event.sourceType == .manual, "sourceType should be .manual")
        #expect(event.externalId == nil, "Manual events have no externalId")
        #expect(event.originalTitle == nil, "Manual events have no originalTitle")
    }

    @Test("Event with imported sourceType has external metadata")
    func test_event_importedSourceType_hasExternalMetadata() {
        let event = Event(
            timestamp: Date(),
            sourceType: .imported,
            externalId: "cal-123",
            originalTitle: "Meeting with Team"
        )

        #expect(event.sourceType == .imported, "sourceType should be .imported")
        #expect(event.externalId == "cal-123", "Imported event should have externalId")
        #expect(event.originalTitle == "Meeting with Team", "Imported event should have originalTitle")
    }

    @Test("Event sourceType defaults to manual")
    func test_event_defaultSourceType_isManual() {
        let event = Event(timestamp: Date())

        #expect(event.sourceType == .manual, "Default sourceType should be .manual")
    }
}

@Suite("Event EventType Relationship")
struct EventEventTypeRelationshipTests {

    @Test("Event with eventType has relationship")
    func test_event_withEventType_hasRelationship() {
        let eventType = EventTypeFixture.makeEventType(name: "Workout")
        let event = Event(timestamp: Date(), eventType: eventType)

        #expect(event.eventType != nil, "eventType should be set")
        #expect(event.eventType?.name == "Workout", "eventType name should match")
    }

    @Test("Event without eventType has nil relationship")
    func test_event_withoutEventType_hasNilRelationship() {
        let event = Event(timestamp: Date())

        #expect(event.eventType == nil, "eventType should be nil")
    }

    @Test("Event eventType can be changed")
    func test_event_eventType_canBeChanged() {
        let eventType1 = EventTypeFixture.makeEventType(name: "Run")
        let eventType2 = EventTypeFixture.makeEventType(name: "Bike")

        var event = Event(timestamp: Date(), eventType: eventType1)
        #expect(event.eventType?.name == "Run", "Initial eventType should be 'Run'")

        event.eventType = eventType2
        #expect(event.eventType?.name == "Bike", "Updated eventType should be 'Bike'")
    }
}

@Suite("Event Optional Fields")
struct EventOptionalFieldsTests {

    @Test("Event notes can be nil")
    func test_event_notes_canBeNil() {
        let event = Event(timestamp: Date(), notes: nil)

        #expect(event.notes == nil, "notes should be nil")
    }

    @Test("Event notes can be set")
    func test_event_notes_canBeSet() {
        let event = Event(timestamp: Date(), notes: "Important event")

        #expect(event.notes == "Important event", "notes should be set")
    }

    @Test("Event externalId can be nil")
    func test_event_externalId_canBeNil() {
        let event = Event(timestamp: Date(), externalId: nil)

        #expect(event.externalId == nil, "externalId should be nil")
    }

    @Test("Event originalTitle can be nil")
    func test_event_originalTitle_canBeNil() {
        let event = Event(timestamp: Date(), originalTitle: nil)

        #expect(event.originalTitle == nil, "originalTitle should be nil")
    }

    @Test("Event calendarEventId can be nil")
    func test_event_calendarEventId_canBeNil() {
        let event = Event(timestamp: Date(), calendarEventId: nil)

        #expect(event.calendarEventId == nil, "calendarEventId should be nil")
    }

    @Test("Event calendarEventId is iOS-only")
    func test_event_calendarEventId_isIOSOnly() {
        // calendarEventId should NOT be synced to backend
        // It's local to the iOS device for calendar sync

        let event = Event(
            timestamp: Date(),
            calendarEventId: "ios-cal-123"
        )

        #expect(event.calendarEventId == "ios-cal-123", "calendarEventId should be set locally")
        // Note: Backend sync should exclude calendarEventId (tested in migration/sync tests)
    }
}

@Suite("Event Edge Cases")
struct EventEdgeCaseTests {

    @Test("Event with empty notes string")
    func test_event_emptyNotesString() {
        let event = Event(timestamp: Date(), notes: "")

        #expect(event.notes == "", "Empty notes string should be preserved")
    }

    @Test("Event with very long notes")
    func test_event_veryLongNotes() {
        let longNotes = String(repeating: "a", count: 10000)
        let event = Event(timestamp: Date(), notes: longNotes)

        #expect(event.notes?.count == 10000, "Long notes should be preserved")
    }

    @Test("Event with timestamp in distant past")
    func test_event_timestampInDistantPast() {
        let distantPast = Date(timeIntervalSince1970: 0)  // 1970-01-01
        let event = Event(timestamp: distantPast)

        #expect(event.timestamp == distantPast, "Distant past timestamp should be valid")
    }

    @Test("Event with timestamp in distant future")
    func test_event_timestampInDistantFuture() {
        let distantFuture = Date(timeIntervalSince1970: 4102444800)  // 2100-01-01
        let event = Event(timestamp: distantFuture)

        #expect(event.timestamp == distantFuture, "Distant future timestamp should be valid")
    }

    @Test("Event with endDate before timestamp")
    func test_event_endDateBeforeTimestamp_isInvalid() {
        let startDate = Date()
        let endDate = Date(timeIntervalSinceNow: -3600)  // 1 hour ago

        let event = Event(
            timestamp: startDate,
            endDate: endDate
        )

        // Model doesn't validate this, but it's semantically invalid
        // Business logic should handle this validation
        #expect(event.endDate != nil, "endDate is set even if invalid")
        #expect(event.endDate! < event.timestamp, "endDate is before timestamp (invalid)")
    }

    @Test("Event with many properties")
    func test_event_manyProperties() {
        var properties: [String: PropertyValue] = [:]
        for i in 0..<100 {
            properties["key_\(i)"] = PropertyValueFixture.makeTextProperty(value: "value_\(i)")
        }

        let event = Event(timestamp: Date(), properties: properties)

        #expect(event.properties.count == 100, "Event should support 100 properties")
    }
}

@Suite("Event Use Cases")
struct EventUseCaseTests {

    @Test("Use case: Simple manual event")
    func test_useCase_simpleManualEvent() {
        let eventType = EventTypeFixture.makeEventType(name: "Coffee")
        let event = Event(
            timestamp: Date(),
            eventType: eventType,
            notes: "Morning coffee"
        )

        #expect(event.eventType?.name == "Coffee", "Event type should be 'Coffee'")
        #expect(event.notes == "Morning coffee", "Notes should be set")
        #expect(event.sourceType == .manual, "Should be manual event")
        #expect(event.isAllDay == false, "Should be timed event")
    }

    @Test("Use case: All-day vacation event")
    func test_useCase_allDayVacationEvent() {
        let eventType = EventTypeFixture.makeEventType(name: "Vacation")
        let startDate = DeterministicDate.jan1_2024
        let endDate = DeterministicDate.make(year: 2024, month: 1, day: 7)  // 7 days

        let event = Event(
            timestamp: startDate,
            eventType: eventType,
            notes: "Hawaii trip",
            isAllDay: true,
            endDate: endDate
        )

        #expect(event.eventType?.name == "Vacation", "Event type should be 'Vacation'")
        #expect(event.isAllDay == true, "Should be all-day event")
        #expect(event.endDate != nil, "Multi-day event should have endDate")
    }

    @Test("Use case: Imported calendar meeting")
    func test_useCase_importedCalendarMeeting() {
        let eventType = EventTypeFixture.makeEventType(name: "Meeting")
        let event = Event(
            timestamp: Date(),
            eventType: eventType,
            notes: nil,
            sourceType: .imported,
            externalId: "cal-meeting-123",
            originalTitle: "Team Standup"
        )

        #expect(event.sourceType == .imported, "Should be imported event")
        #expect(event.externalId != nil, "Imported event should have externalId")
        #expect(event.originalTitle == "Team Standup", "Should preserve original title")
    }

    @Test("Use case: Workout with custom properties")
    func test_useCase_workoutWithProperties() {
        let eventType = EventTypeFixture.makeEventType(name: "Workout")
        let properties = [
            "distance": PropertyValueFixture.makeNumberProperty(value: 5),
            "duration": PropertyValueFixture.makeNumberProperty(value: 30),
            "location": PropertyValueFixture.makeTextProperty(value: "Gym")
        ]

        let event = Event(
            timestamp: Date(),
            eventType: eventType,
            notes: "Morning run",
            properties: properties
        )

        #expect(event.properties.count == 3, "Event should have 3 custom properties")
        #expect(event.properties["distance"]?.intValue == 5, "Distance should be 5")
        #expect(event.properties["duration"]?.intValue == 30, "Duration should be 30")
        #expect(event.properties["location"]?.stringValue == "Gym", "Location should be 'Gym'")
    }
}
