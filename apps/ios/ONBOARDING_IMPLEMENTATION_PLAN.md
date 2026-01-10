# TrendSight Onboarding Implementation Plan

## Overview

Implement a high-conversion onboarding flow for the TrendSight iOS app with:
- Email/password + Google OAuth authentication
- Event type creation with templates
- First event logging
- Permission pre-prompts (notifications, location, HealthKit)
- Resume logic and analytics tracking

**Primary conversion metric**: % who complete onboarding and create at least one Event Type
**Secondary metric**: % who log first event

---

## Architecture Summary

```
OnboardingContainerView
├── WelcomeView           → Value prop + CTAs
├── OnboardingAuthView    → Email/Password + Google Sign-In
├── CreateEventTypeView   → Template selection + custom creation
├── LogFirstEventView     → Simplified event logging
├── PermissionsView       → Pre-prompts for all permissions
└── OnboardingFinishView  → Success confirmation
```

**State Machine**: `OnboardingStep` enum drives navigation with persistence to both UserDefaults (local) and Supabase profiles table (remote).

**Routing Logic**:
- No Supabase session → show onboarding + auth
- Session exists AND `onboarding_complete = true` → go to main app
- Session exists BUT `onboarding_complete = false` → resume onboarding

---

## Phase 1: Database & Infrastructure

### 1.1 Supabase Migration

**File**: `supabase/migrations/20260109_add_profiles_table.sql`

```sql
-- Profiles table for onboarding state and user preferences
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    onboarding_complete BOOLEAN NOT NULL DEFAULT FALSE,
    onboarding_step TEXT,  -- Current step for resume logic
    notifications_enabled BOOLEAN DEFAULT NULL,  -- NULL = not prompted
    location_enabled BOOLEAN DEFAULT NULL,
    healthkit_enabled BOOLEAN DEFAULT NULL,
    onboarding_started_at TIMESTAMP WITH TIME ZONE,
    onboarding_completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id)
    VALUES (NEW.id)
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for auto-creation
DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_profiles_onboarding_complete
    ON public.profiles(onboarding_complete);
```

### 1.2 New Files to Create

```
apps/ios/trendy/
├── Models/Onboarding/
│   ├── OnboardingStep.swift          # State machine enum
│   ├── EventTypeTemplate.swift       # Predefined templates
│   └── OnboardingAnalytics.swift     # PostHog event names
├── Services/
│   ├── ProfileService.swift          # Supabase profiles CRUD
│   └── GoogleSignInService.swift     # Google OAuth wrapper
├── ViewModels/
│   └── OnboardingViewModel.swift     # State machine + persistence
└── Views/Onboarding/
    ├── OnboardingContainerView.swift # Navigation coordinator
    ├── WelcomeView.swift
    ├── OnboardingAuthView.swift
    ├── CreateEventTypeView.swift
    ├── LogFirstEventView.swift
    ├── PermissionsView.swift
    └── OnboardingFinishView.swift
```

---

## Phase 2: Models

### 2.1 OnboardingStep.swift

```swift
import Foundation

/// State machine for onboarding flow
enum OnboardingStep: String, Codable, CaseIterable {
    case welcome
    case auth
    case createEventType
    case logFirstEvent
    case permissions
    case finish

    /// Next step in the flow
    var next: OnboardingStep? {
        switch self {
        case .welcome: return .auth
        case .auth: return .createEventType
        case .createEventType: return .logFirstEvent
        case .logFirstEvent: return .permissions
        case .permissions: return .finish
        case .finish: return nil
        }
    }

    /// Previous step (for back navigation)
    var previous: OnboardingStep? {
        switch self {
        case .welcome: return nil
        case .auth: return .welcome
        case .createEventType: return nil  // Can't go back after auth
        case .logFirstEvent: return .createEventType
        case .permissions: return .logFirstEvent
        case .finish: return nil
        }
    }

    /// Whether this step can be skipped
    var isSkippable: Bool {
        switch self {
        case .permissions: return true
        default: return false
        }
    }

    /// Step number for progress indicator (1-indexed)
    var stepNumber: Int {
        switch self {
        case .welcome: return 1
        case .auth: return 1
        case .createEventType: return 2
        case .logFirstEvent: return 3
        case .permissions: return 4
        case .finish: return 4
        }
    }

    /// Total steps for progress indicator
    static var totalSteps: Int { 4 }
}
```

### 2.2 EventTypeTemplate.swift

```swift
import Foundation

/// Predefined event type templates for onboarding
struct EventTypeTemplate: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let colorHex: String
    let description: String

    static let templates: [EventTypeTemplate] = [
        EventTypeTemplate(
            id: "mood",
            name: "Mood",
            iconName: "face.smiling.fill",
            colorHex: "#FBBF24",
            description: "Track your daily mood and emotions"
        ),
        EventTypeTemplate(
            id: "workout",
            name: "Workout",
            iconName: "figure.run",
            colorHex: "#34D399",
            description: "Log your exercise sessions"
        ),
        EventTypeTemplate(
            id: "medication",
            name: "Medication",
            iconName: "pills.fill",
            colorHex: "#60A5FA",
            description: "Never miss a dose"
        ),
        EventTypeTemplate(
            id: "coffee",
            name: "Coffee",
            iconName: "cup.and.saucer.fill",
            colorHex: "#A78BFA",
            description: "Track your caffeine intake"
        ),
        EventTypeTemplate(
            id: "journal",
            name: "Journal",
            iconName: "book.fill",
            colorHex: "#F472B6",
            description: "Daily reflections and notes"
        ),
        EventTypeTemplate(
            id: "custom",
            name: "Custom",
            iconName: "plus.circle.fill",
            colorHex: "#94A3B8",
            description: "Create your own event type"
        )
    ]
}
```

### 2.3 OnboardingAnalytics.swift

```swift
import Foundation

/// Analytics event names for PostHog tracking
enum OnboardingAnalyticsEvent: String {
    case onboardingStarted = "onboarding_started"
    case onboardingAuthViewed = "onboarding_auth_viewed"
    case onboardingAuthSucceeded = "onboarding_auth_succeeded"
    case onboardingAuthFailed = "onboarding_auth_failed"
    case onboardingAuthMethodUsed = "onboarding_auth_method_used"
    case onboardingEventTypeCreated = "onboarding_event_type_created"
    case onboardingEventTypeSkipped = "onboarding_event_type_skipped"
    case onboardingFirstEventLogged = "onboarding_first_event_logged"
    case onboardingFirstEventSkipped = "onboarding_first_event_skipped"
    case onboardingPermissionPrompted = "onboarding_permission_prompted"
    case onboardingPermissionResult = "onboarding_permission_result"
    case onboardingCompleted = "onboarding_completed"
    case onboardingAbandoned = "onboarding_abandoned"
}

/// Permission types for analytics
enum OnboardingPermissionType: String {
    case notifications
    case location
    case healthkit
}
```

---

## Phase 3: Services

### 3.1 ProfileService.swift

```swift
import Foundation
import Supabase

/// Service for managing user profiles in Supabase
@Observable
class ProfileService {
    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    // MARK: - Profile Model

    struct Profile: Codable {
        let id: String
        var onboardingComplete: Bool
        var onboardingStep: String?
        var notificationsEnabled: Bool?
        var locationEnabled: Bool?
        var healthkitEnabled: Bool?
        var onboardingStartedAt: Date?
        var onboardingCompletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case onboardingComplete = "onboarding_complete"
            case onboardingStep = "onboarding_step"
            case notificationsEnabled = "notifications_enabled"
            case locationEnabled = "location_enabled"
            case healthkitEnabled = "healthkit_enabled"
            case onboardingStartedAt = "onboarding_started_at"
            case onboardingCompletedAt = "onboarding_completed_at"
        }
    }

    // MARK: - CRUD Operations

    /// Fetch profile for current user
    func fetchProfile() async throws -> Profile? {
        let userId = try await supabaseService.getUserId()

        let response: [Profile] = try await supabaseService.client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .execute()
            .value

        return response.first
    }

    /// Create or update profile
    func upsertProfile(_ profile: Profile) async throws {
        try await supabaseService.client
            .from("profiles")
            .upsert(profile)
            .execute()
    }

    /// Update onboarding step
    func updateOnboardingStep(_ step: OnboardingStep) async throws {
        let userId = try await supabaseService.getUserId()

        try await supabaseService.client
            .from("profiles")
            .update(["onboarding_step": step.rawValue])
            .eq("id", value: userId)
            .execute()
    }

    /// Mark onboarding as complete
    func completeOnboarding() async throws {
        let userId = try await supabaseService.getUserId()

        try await supabaseService.client
            .from("profiles")
            .update([
                "onboarding_complete": true,
                "onboarding_completed_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: userId)
            .execute()
    }

    /// Update permission preferences
    func updatePermissions(
        notifications: Bool? = nil,
        location: Bool? = nil,
        healthkit: Bool? = nil
    ) async throws {
        let userId = try await supabaseService.getUserId()

        var updates: [String: Any] = [:]
        if let notifications = notifications {
            updates["notifications_enabled"] = notifications
        }
        if let location = location {
            updates["location_enabled"] = location
        }
        if let healthkit = healthkit {
            updates["healthkit_enabled"] = healthkit
        }

        guard !updates.isEmpty else { return }

        try await supabaseService.client
            .from("profiles")
            .update(updates)
            .eq("id", value: userId)
            .execute()
    }
}
```

### 3.2 GoogleSignInService.swift

```swift
import GoogleSignIn
import Supabase

/// Service for handling Google Sign-In with Supabase
@Observable
class GoogleSignInService {
    private let supabaseService: SupabaseService

    /// Google iOS Client ID from Google Cloud Console
    private var googleClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
    }

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    /// Sign in with Google
    @MainActor
    func signIn(presentingViewController: UIViewController) async throws -> Session {
        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: googleClientID)
        GIDSignIn.sharedInstance.configuration = config

        // Perform Google Sign-In
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController
        )

        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleSignInError.noIdToken
        }

        // Exchange Google ID token for Supabase session
        // Note: Supabase Dashboard must have "Skip nonce check" enabled for iOS
        let session = try await supabaseService.client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken
            )
        )

        // Update SupabaseService state
        await MainActor.run {
            supabaseService.currentSession = session
            supabaseService.isAuthenticated = true
        }

        Log.auth.info("Google Sign-In successful", context: .with { ctx in
            ctx.add("user_id", session.user.id.uuidString)
        })

        return session
    }

    /// Sign out from Google
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
}

enum GoogleSignInError: LocalizedError {
    case noIdToken
    case cancelled
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .noIdToken:
            return "Could not obtain Google ID token"
        case .cancelled:
            return "Sign-in was cancelled"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
```

---

## Phase 4: ViewModel

### 4.1 OnboardingViewModel.swift

**Key Responsibilities**:
- State machine management via `currentStep: OnboardingStep`
- Dual persistence: UserDefaults (local) + ProfileService (remote)
- Auth coordination: email/password via existing SupabaseService + Google via GoogleSignInService
- Event type/event creation via EventStore
- Permission requests via existing NotificationManager, GeofenceManager, HealthKitService
- PostHog analytics for all events

**Key Methods**:

```swift
// State Management
func determineInitialState() async  // Route based on auth + profile status
func advanceToNextStep() async
func goBack()
func skipCurrentStep() async

// Authentication
func signUp(email: String, password: String) async
func signIn(email: String, password: String) async
func signInWithGoogle(from viewController: UIViewController) async

// Event Type Creation
func createEventType(from template: EventTypeTemplate) async
func createCustomEventType(name: String, colorHex: String, iconName: String) async
func skipEventTypeCreation() async

// First Event
func logFirstEvent(notes: String?) async
func skipFirstEvent() async

// Permissions
func requestNotificationPermission() async -> Bool
func requestLocationPermission(geofenceManager: GeofenceManager) async -> Bool
func requestHealthKitPermission(healthKitService: HealthKitService?) async -> Bool

// Cleanup
func handleSignOut()
```

**Local Persistence Keys**:
- `onboarding_current_step` - Current step for resume
- `onboarding_start_time` - For duration tracking

---

## Phase 5: Views

### 5.1 OnboardingContainerView.swift

Navigation coordinator that:
- Initializes OnboardingViewModel and EventStore
- Calls `determineInitialState()` on appear
- Switches view based on `viewModel.currentStep`
- Animates transitions between steps

### 5.2 WelcomeView.swift

- App logo (chart.line.uptrend.xyaxis icon)
- Title: "Track anything. See patterns."
- 3 feature highlights:
  - Quick Logging: "Tap to track any event instantly"
  - Smart Insights: "Discover correlations in your data"
  - Reminders: "Never miss what matters to you"
- "Get Started" primary CTA
- "I have an account" secondary link

### 5.3 OnboardingAuthView.swift

- Toggle between Sign Up / Sign In modes
- Google Sign-In button (styled to match design system)
- Divider with "or"
- Email/Password form:
  - Email TextField
  - Password SecureField
  - Confirm Password (sign up only)
- Password requirements helper text
- Error message display
- Submit button with loading state

### 5.4 CreateEventTypeView.swift

- Header: "What will you track first?"
- 6 template cards in 2x3 grid:
  - Each shows icon, name, description
  - Tapping non-custom → immediate creation + advance
  - Tapping "Custom" → reveals:
    - Name TextField
    - Color picker grid (12 colors, reuse from AddEventTypeView.swift)
    - Icon picker grid (24 icons, reuse from AddEventTypeView.swift)
    - Preview bubble
    - "Create" button
- Progress indicator: "Step 2 of 4"

### 5.5 LogFirstEventView.swift

- Header: "Log your first [EventType Name]"
- Large event type bubble display
- "Log Now" button (uses current timestamp)
- Optional notes TextField
- Success animation on log:
  - Checkmark scale animation
  - "First event logged!" message
  - Auto-advance after 1.5s
- "Skip for now" link
- Progress indicator: "Step 3 of 4"

### 5.6 PermissionsView.swift

Three sequential pre-prompt cards:

1. **Notifications**
   - Icon: bell.fill
   - Title: "Stay on Track"
   - Description: "Get reminders to log events and maintain streaks"
   - "Enable Notifications" / "Not Now"

2. **Location**
   - Icon: location.fill
   - Title: "Auto-Log Places"
   - Description: "Automatically log events when you arrive or leave locations"
   - "Enable Location" / "Not Now"

3. **HealthKit**
   - Icon: heart.fill
   - Title: "Import Health Data"
   - Description: "Automatically track workouts, steps, and sleep from Apple Health"
   - "Connect HealthKit" / "Not Now"

- Progress indicator: "Step 4 of 4"
- "Continue" button after all prompts shown

### 5.7 OnboardingFinishView.swift

- Success illustration (checkmark.circle.fill, large, animated)
- "You're all set!"
- Summary cards:
  - "Event type created: [Name]"
  - "First event logged" (if applicable)
  - Permission status indicators
- "Go to Dashboard" CTA
- Posts `Notification.Name.onboardingCompleted` on tap

---

## Phase 6: Integration

### 6.1 Modify ContentView.swift

Replace current routing logic:

```swift
@ViewBuilder
private var authenticatedContent: some View {
    if authViewModel.isAuthenticated {
        if onboardingComplete {
            MainTabView()
        } else {
            OnboardingContainerView()
                .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
                    withAnimation {
                        onboardingComplete = true
                    }
                }
        }
    } else {
        OnboardingContainerView()  // Changed from LoginView()
    }
}
```

Add state and notification name:
```swift
@State private var onboardingComplete = false

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}
```

### 6.2 Modify SupabaseService.swift

Add method for ID token sign-in:

```swift
/// Sign in with ID token from external provider (Google)
func signInWithIdToken(provider: Provider, idToken: String) async throws -> Session {
    let session = try await client.auth.signInWithIdToken(
        credentials: .init(
            provider: provider,
            idToken: idToken
        )
    )

    await MainActor.run {
        self.currentSession = session
        self.isAuthenticated = true
    }

    return session
}
```

### 6.3 Google Sign-In Setup

**Package Installation**:
- Xcode > File > Add Packages
- URL: `https://github.com/google/GoogleSignIn-iOS`
- Version: 7.0.0+

**Google Cloud Console**:
1. Create iOS OAuth Client ID (needs bundle ID)
2. Create Web OAuth Client ID (for Supabase server validation)
3. Download credentials

**Supabase Dashboard**:
1. Authentication > Providers > Google
2. Enable Google provider
3. Add Web Client ID and Secret
4. **Enable "Skip nonce check"** for iOS native sign-in

**xcconfig files** (add to all environments):
```
GOOGLE_CLIENT_ID = your-ios-client-id.apps.googleusercontent.com
```

**Info.plist additions**:
```xml
<key>GOOGLE_CLIENT_ID</key>
<string>$(GOOGLE_CLIENT_ID)</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR-CLIENT-ID</string>
        </array>
    </dict>
</array>
```

**URL Handling** (in AppDelegate or SceneDelegate):
```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return GIDSignIn.sharedInstance.handle(url)
}
```

### 6.4 Assets

Add `google_logo` image to Assets.xcassets (Google's official logo for sign-in buttons).

---

## Phase 7: Testing

### Unit Tests: OnboardingViewModelTests.swift

```swift
func testInitialStateIsWelcome() async
func testAuthenticatedUserWithIncompleteOnboarding() async
func testAuthenticatedUserWithCompleteOnboarding() async
func testStepAdvancement() async
func testPermissionsAreSkippable() async
func testResumeFromPersistedStep() async
func testSignOutClearsState() async
func testEventTypeCreationFromTemplate() async
func testFirstEventLogging() async
```

### UI Tests: OnboardingUITests.swift

```swift
func testCompleteOnboardingFlow() throws
func testResumeAfterAppTermination() throws
func testSignInExistingUser() throws
func testSkipPermissions() throws
func testErrorHandlingInvalidCredentials() throws
```

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `apps/ios/trendy/ContentView.swift` | Add onboarding routing logic, onboardingComplete state |
| `apps/ios/trendy/Services/SupabaseService.swift` | Add `signInWithIdToken` method |
| `apps/ios/trendy/trendyApp.swift` | Add URL handling for Google Sign-In callback |
| `apps/ios/Config/Debug.xcconfig` | Add `GOOGLE_CLIENT_ID` |
| `apps/ios/Config/Staging.xcconfig` | Add `GOOGLE_CLIENT_ID` |
| `apps/ios/Config/Release.xcconfig` | Add `GOOGLE_CLIENT_ID` |
| `apps/ios/Config/TestFlight.xcconfig` | Add `GOOGLE_CLIENT_ID` |
| `apps/ios/trendy/trendy-Info.plist` | Add Google URL scheme |

---

## Verification Plan

1. **Fresh install**: App shows Welcome screen, full onboarding completes in <2 min
2. **Email signup**: Creates account, advances to event type creation
3. **Google Sign-In**: Opens Google consent, returns to app, advances flow
4. **Create event type**: Template selection creates event type in Supabase
5. **Custom event type**: Name/color/icon selection works, creates in Supabase
6. **Log first event**: Event saved to Supabase with correct timestamp
7. **Permissions**: Pre-prompts shown, system dialogs triggered, all skippable
8. **Completion**: `profiles.onboarding_complete = true` in Supabase
9. **Resume**: Kill app mid-flow → reopen → resumes at correct step
10. **Returning user**: Sign in existing account → goes to main app if onboarding complete
11. **Sign out**: Returns to welcome, clears local state

---

## Edge Cases Handled

| Scenario | Handling |
|----------|----------|
| No network during onboarding | Local UserDefaults persistence, sync on reconnect |
| App killed mid-flow | Resume from persisted step (local + remote) |
| User already has event types | Skip creation step, use first existing type |
| Permission denied | Friendly message, continue flow normally |
| Google Sign-In cancelled | No error shown, user can retry or use email |
| Profile missing after auth | Auto-upsert via trigger or manual fallback |
| Token refresh needed | Handled by Supabase SDK automatically |

---

## Analytics Events (PostHog)

| Event | Properties |
|-------|------------|
| `onboarding_started` | `current_step` |
| `onboarding_auth_viewed` | `current_step` |
| `onboarding_auth_succeeded` | `method` (email_signup, email_signin, google) |
| `onboarding_auth_failed` | `method`, `error` |
| `onboarding_event_type_created` | `template_id`, `template_name` or `custom_name` |
| `onboarding_event_type_skipped` | - |
| `onboarding_first_event_logged` | `event_type_name`, `has_notes` |
| `onboarding_first_event_skipped` | - |
| `onboarding_permission_prompted` | `type` (notifications, location, healthkit) |
| `onboarding_permission_result` | `type`, `granted` |
| `onboarding_completed` | `duration_seconds` |

---

## Design System Colors Used

Reference `apps/ios/trendy/DesignSystem/Colors.swift`:

- `Color.dsBackground` - Main backgrounds
- `Color.dsForeground` - Primary text
- `Color.dsCard` - Card backgrounds, input fields
- `Color.dsPrimary` - Primary buttons, icons
- `Color.dsMutedForeground` - Secondary text
- `Color.dsLink` - Clickable links
- `Color.dsDestructive` - Error messages
- `Color.dsSuccess` - Success states
- `Color.dsBorder` - Dividers, borders

---

## Implementation Order

1. **Database**: Apply Supabase migration for profiles table
2. **Models**: Create OnboardingStep, EventTypeTemplate, OnboardingAnalytics
3. **ProfileService**: Implement profiles CRUD
4. **GoogleSignInService**: Set up Google OAuth (requires Google Cloud Console setup)
5. **OnboardingViewModel**: Implement state machine and persistence
6. **Views**: Build all 6 onboarding screens
7. **Integration**: Modify ContentView, SupabaseService, add Google Sign-In config
8. **Testing**: Unit tests for ViewModel, UI tests for flow
9. **Polish**: Animations, error handling, analytics verification
