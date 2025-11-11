# ActionMail OAuth Sign-In (Google) - Desktop and Android

This document explains how Google OAuth sign-in works in ActionMail across Windows/Linux desktop and Android, what must be configured in Google Cloud Console, and how the app is wired to obtain refresh tokens.

## Overview

- We use the OAuth 2.0 Authorization Code flow with PKCE against Google.
- We require refresh tokens (offline access) to periodically refresh Gmail API access tokens.
- We avoid Google Sign-In on Android because it does not provide refresh tokens.
- **Desktop**: Uses local HTTP server with `http://localhost:8400` redirect.
- **Android**: Uses HTTPS App Links with Firebase Hosting redirect (`https://inboxiq--api.web.app/__/auth/handler`).

## Google Cloud Console Configuration

### Web OAuth Client (Used for Both Desktop and Android)

Create a **Web OAuth client** (not Desktop or Android client) because:
- Desktop OAuth clients don't allow configuring redirect URIs
- Android OAuth clients don't provide refresh tokens
- Web OAuth clients support both `http://localhost` (desktop) and HTTPS (Android App Links)

**OAuth Client Type:** Web application

**Client ID Example:**
- `861261774181-sflh559mhcdjjens6fucg5313keg7ajd.apps.googleusercontent.com`

**Authorized redirect URIs:**
- `http://localhost:8400` (for desktop - Windows/Linux/Mac)
- `https://inboxiq--api.web.app/__/auth/handler` (for Android App Links)

**Authorized JavaScript origins:**
- Leave empty (not needed for this flow)

**Notes:**
- Both desktop and Android use the same Web OAuth client ID
- The Web OAuth client must have both redirect URIs configured
- Ensure the OAuth consent screen is configured with your testing accounts added as Test users if the app is not in production

### Android App Links Configuration

For Android App Links to work without the app chooser:

1. **Firebase Hosting:** Deploy `assetlinks.json` to `https://inboxiq--api.web.app/.well-known/assetlinks.json`

2. **assetlinks.json content:**
```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.seagreen.inboxiq1",
    "sha256_cert_fingerprints": [
      "YOUR_SHA256_FINGERPRINT_HERE"
    ]
  }
}]
```

3. **Get SHA-256 fingerprint:**
   - Command: `cd android && ./gradlew signingReport`
   - Look for `SHA256` under `Variant: debug` or `Variant: release`
   - Or use Android Studio: Build > Generate Signed Bundle/APK > View certificates

4. **Verify App Links:**
   - After deploying `assetlinks.json`, Android will verify domain ownership
   - This can take a few minutes to propagate
   - Once verified, App Links will open the app directly without showing a chooser

## App Configuration

### Redirect URIs

Defined in `lib/constants/app_constants.dart`:

- **Desktop:** `AppConstants.oauthRedirectUri` → `http://localhost:8400`
- **Android:** `AppConstants.oauthRedirectUriForMobile` → `https://inboxiq--api.web.app/__/auth/handler`

### Client Credentials

`lib/config/oauth_config.dart` (gitignored):
- Both desktop and Android use `webClientId` (same Web OAuth client)
- Client secret is shared between platforms

## Desktop Flow (Windows/Linux/Mac)

**Code:** `GoogleAuthService.signIn()` desktop branch in `lib/services/auth/google_auth_service.dart`

**Steps:**
1. Generate PKCE verifier/challenge.
2. Start local HTTP server on port 8400 bound to loopback IPv4.
3. Construct Google auth URL with:
   - Web OAuth client ID
   - `redirect_uri=http://localhost:8400`
   - `prompt=consent`, `access_type=offline`
   - PKCE challenge
4. Launch system browser with `launchUrl`.
5. User signs in via browser.
6. Google redirects to `http://localhost:8400?code=...`
7. Local HTTP server captures the redirect and extracts `code`.
8. Exchange code for `access_token` and `refresh_token`.
9. Fetch basic profile (userinfo) to populate account.
10. Bring window to front via `WindowToFront.activate()`.

## Android Flow

**Code:** `GoogleAuthService.signIn()` Android branch in `lib/services/auth/google_auth_service.dart`

**Steps:**
1. Generate PKCE verifier/challenge.
2. Store OAuth state (verifier, redirectUri, clientId, clientSecret) in SharedPreferences.
3. Construct Google auth URL with:
   - Web OAuth client ID
   - `redirect_uri=https://inboxiq--api.web.app/__/auth/handler`
   - `prompt=consent`, `access_type=offline`
   - PKCE challenge
4. Launch external browser with `launchUrl`.
5. User signs in via browser.
6. Google redirects to `https://inboxiq--api.web.app/__/auth/handler?code=...`
7. Android verifies App Link via `assetlinks.json` and opens the app automatically (no chooser).
8. App restarts or resumes with the App Link in the intent.
9. Splash screen detects App Link via `MainActivity.getInitialAppLink()`.
10. Retrieve stored OAuth state from SharedPreferences.
11. Exchange code for `access_token` and `refresh_token`.
12. Fetch basic profile (userinfo) to populate account.
13. Navigate to home screen.

### Android Manifest

`android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop">
    <!-- Existing intent-filter for app launch -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    
    <!-- HTTPS App Links for OAuth redirect -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data 
            android:scheme="https" 
            android:host="inboxiq--api.web.app" 
            android:pathPrefix="/__/auth/handler"/>
    </intent-filter>
</activity>
```

**Important:** Do NOT add `http://localhost` intent-filters. This would cause the app chooser to appear.

### MainActivity App Link Handling

`android/app/src/main/kotlin/com/seagreen/domail/MainActivity.kt`:

- Implements `MethodChannel` with method `getInitialAppLink` to retrieve App Link from intent
- Implements `MethodChannel` with method `clearAppLink` to clear intent data after processing
- Handles both initial intent (app restarted) and new intent (app resumed)

### Splash Screen App Link Processing

`lib/features/auth/presentation/splash_screen.dart`:

- `_checkAppLinkAndCompleteSignIn()` checks for App Link on startup and resume
- Retrieves stored OAuth state from SharedPreferences
- Completes OAuth flow using `GoogleAuthService.completeOAuthFlow()`
- Navigates to home after successful sign-in

## Scopes

Defined in `AppConstants.oauthScopes`:
- `email`
- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/gmail.modify`
- `https://www.googleapis.com/auth/userinfo.profile`

We use `prompt=consent` and `access_type=offline` to obtain a refresh token.

## Refresh Tokens

- Stored with the account in local preferences after first consent.
- Access tokens are refreshed automatically via the token endpoint when near expiry.
- Refresh tokens are required for offline access and are obtained via Web OAuth client.

## Foregrounding Behavior

- **Desktop:** `WindowToFront.activate()` is used after sign-in.
- **Android:** App automatically returns to foreground via App Links. `MainActivity.bringToFront()` is available as a fallback via MethodChannel.

## Troubleshooting

### Desktop

**Error: redirect_uri_mismatch**
- Verify the Web OAuth client has `http://localhost:8400` in Authorized redirect URIs
- Ensure the redirect URI in the code matches exactly (no trailing slash, correct port)

**No refresh_token returned**
- Use `prompt=consent` and `access_type=offline`
- Google may not return a new refresh_token if you previously granted access; revoke access or use consent prompt

### Android

**Error: redirect_uri_mismatch**
- Verify the Web OAuth client has `https://inboxiq--api.web.app/__/auth/handler` in Authorized redirect URIs
- Ensure the redirect URI in the code matches exactly (including the path)

**App chooser appears after sign-in**
- App Links may not be verified yet (wait a few minutes after deploying `assetlinks.json`)
- Verify `assetlinks.json` is accessible at `https://inboxiq--api.web.app/.well-known/assetlinks.json`
- Verify SHA-256 fingerprint in `assetlinks.json` matches your app's signing certificate
- Check Android logs for App Links verification: `adb shell pm get-app-links com.seagreen.inboxiq1`

**App doesn't open after sign-in**
- Check Android logs for App Link detection: `[splash] detected OAuth App Link`
- Verify `MainActivity.getInitialAppLink()` is returning the App Link URL
- Ensure OAuth state was stored in SharedPreferences before launching browser

**OAuth state missing error**
- This happens when app restarts with an old App Link from a previous sign-in attempt
- The code automatically clears old App Links and launches a fresh sign-in
- If persistent, clear app data and try again

**Sign-in button doesn't open browser**
- Check logs for `[auth][android] launching browser`
- Verify `launchUrl` has necessary permissions in AndroidManifest

## Relevant Files

- `lib/services/auth/google_auth_service.dart` — main OAuth flow implementation
- `lib/features/auth/presentation/splash_screen.dart` — App Link detection and completion
- `lib/constants/app_constants.dart` — redirect URIs and scopes
- `android/app/src/main/AndroidManifest.xml` — App Links intent-filter
- `android/app/src/main/kotlin/com/seagreen/domail/MainActivity.kt` — App Link handling
- `lib/config/oauth_config.dart` — client id/secret (gitignored)
- `public/.well-known/assetlinks.json` — Android App Links verification (Firebase Hosting)

## Deployment Checklist

### Google Cloud Console
- [ ] Web OAuth client created
- [ ] `http://localhost:8400` added to Authorized redirect URIs
- [ ] `https://inboxiq--api.web.app/__/auth/handler` added to Authorized redirect URIs
- [ ] OAuth consent screen configured with test users

### Firebase Hosting
- [ ] `assetlinks.json` deployed to `public/.well-known/assetlinks.json`
- [ ] SHA-256 fingerprint updated in `assetlinks.json`
- [ ] File accessible at `https://inboxiq--api.web.app/.well-known/assetlinks.json`

### Android App
- [ ] `AndroidManifest.xml` has HTTPS App Links intent-filter with `android:autoVerify="true"`
- [ ] `MainActivity.kt` implements `getInitialAppLink` and `clearAppLink` methods
- [ ] App Links verified (check via `adb shell pm get-app-links`)

### Code
- [ ] `oauth_config.dart` has Web OAuth client ID configured
- [ ] Both desktop and Android use `webClientId` in `OAuthConfig.clientId`
- [ ] Redirect URIs match exactly in code and Google Cloud Console
