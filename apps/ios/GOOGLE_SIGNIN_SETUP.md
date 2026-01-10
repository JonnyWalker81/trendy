# Google Sign-In Setup Guide

This guide explains how to set up Google Sign-In for the TrendSight iOS app.

## Prerequisites

- A Google Cloud Platform account
- Access to the Supabase Dashboard
- Xcode with the GoogleSignIn-iOS package installed

## Step 1: Add GoogleSignIn-iOS Package

1. Open the Xcode project
2. Go to **File > Add Package Dependencies**
3. Enter the URL: `https://github.com/google/GoogleSignIn-iOS`
4. Select version **7.0.0** or later
5. Add the package to the `trendy` target

## Step 2: Create Google Cloud OAuth Credentials

### iOS Client ID

1. Go to [Google Cloud Console > Credentials](https://console.cloud.google.com/apis/credentials)
2. Click **Create Credentials > OAuth client ID**
3. Select **iOS** as the application type
4. Enter your app's **Bundle ID** (e.g., `com.shadowlabs.trendsight`)
5. Click **Create**
6. Copy the **Client ID** (format: `xxx.apps.googleusercontent.com`)

### Web Client ID (Required for Supabase)

1. In the same Google Cloud Console, create another OAuth client ID
2. Select **Web application** as the type
3. Add your Supabase callback URL to **Authorized redirect URIs**:
   - `https://your-project.supabase.co/auth/v1/callback`
4. Click **Create**
5. Copy both the **Client ID** and **Client Secret**

## Step 3: Configure Supabase

1. Go to your [Supabase Dashboard](https://supabase.com/dashboard)
2. Navigate to **Authentication > Providers > Google**
3. Enable the Google provider
4. Enter the **Web Client ID** and **Client Secret** from Step 2
5. **Important**: Enable **"Skip nonce check"** - required for iOS native sign-in
6. Save the configuration

## Step 4: Configure iOS App

### Add Client ID to Secrets

Add your iOS Client ID to the appropriate secrets file:

```
// In Secrets-Debug.xcconfig, Secrets-Staging.xcconfig, etc.
GOOGLE_CLIENT_ID = your-ios-client-id.apps.googleusercontent.com
```

The Client ID is automatically:
- Read from `Info.plist` at runtime
- Used as a URL scheme for the OAuth callback

## Step 5: Enable Google Sign-In in Code

The GoogleSignInService is currently stubbed with TODOs. To enable it:

1. Open `Services/GoogleSignInService.swift`
2. Uncomment `import GoogleSignIn` at the top
3. Uncomment the implementation in the `signIn(presentingViewController:)` method
4. Uncomment `GIDSignIn.sharedInstance.signOut()` in the `signOut()` method
5. Uncomment the URL handling in `handle(_ url:)` method

## Step 6: Handle URL Callback

Add URL handling to your app. In `trendyApp.swift` or your app delegate:

```swift
// In your App struct or SceneDelegate
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return GIDSignIn.sharedInstance.handle(url)
}
```

Or for SwiftUI, add to your WindowGroup:

```swift
WindowGroup {
    ContentView()
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
}
```

## Verification

1. Build and run the app
2. Navigate to the onboarding auth screen
3. Tap "Continue with Google"
4. Complete the Google sign-in flow
5. Verify you're redirected back to the app and authenticated

## Troubleshooting

### "Google Sign-In is not configured"
- Ensure `GOOGLE_CLIENT_ID` is set in your xcconfig file
- Rebuild the app after changing xcconfig values

### Sign-in fails with "Invalid client"
- Verify the iOS Client ID matches your bundle ID
- Check that the Web Client ID is added to Supabase

### Sign-in fails with nonce error
- Enable "Skip nonce check" in Supabase Dashboard under Google provider settings

### URL callback not working
- Verify CFBundleURLTypes in Info.plist includes the Google Client ID
- Ensure URL handling is implemented in your app

## Security Considerations

- Never commit actual Client IDs to version control
- Use environment-specific secrets files (gitignored)
- The Client ID is considered public, but the Client Secret should remain on the server (Supabase)
