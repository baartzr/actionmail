# Fixing GoogleApiManager DEVELOPER_ERROR

## Important: Google Play Services ≠ Google Play Store

**Google Play Services** is a system service on Android devices that provides APIs for Google services (Firebase, Maps, Sign-In, etc.). It's **NOT** the same as Google Play Store.

- **Google Play Services**: System service on Android (comes pre-installed)
- **Google Play Store**: App store where you publish apps

Even if you **never publish to Play Store**, Google Play Services still runs on Android devices and validates apps that use Google APIs.

## Problem
You're seeing this error in Android logs:
```
E/GoogleApiManager: Failed to get service from broker.
E/GoogleApiManager: java.lang.SecurityException: Unknown calling package name 'com.google.android.gms'.
E/GoogleApiManager: ConnectionResult{statusCode=DEVELOPER_ERROR, ...}
```

**Why this happens:**
1. Your app uses **Firebase** (`firebase_core`, `cloud_firestore`)
2. Firebase on Android uses **Google Play Services** under the hood
3. Google Play Services validates your app's package name and SHA fingerprints for security
4. If your app isn't registered in Google Cloud Console, validation fails
5. This happens even for **debug builds** and apps **not published to Play Store**

This is a **security measure** by Google, not related to Play Store deployment.

**Note:** This is different from the `assetlinks.json` file used for App Links. You need both:
- `assetlinks.json` (already configured) - for Android App Links verification
- Android OAuth client in Google Cloud Console - for Google Play Services validation

## Solution

### Step 1: Get SHA Fingerprints

Your SHA-256 fingerprint is already known from `assetlinks.json`:
- **SHA-256**: `EC:14:20:6E:E4:41:C8:BB:36:9F:F2:82:F4:C9:45:25:F8:D3:44:38:00:34:FA:F5:56:23:81:DA:E2:DA:C7:68`
- Source: [https://inboxiq--api.web.app/.well-known/assetlinks.json](https://inboxiq--api.web.app/.well-known/assetlinks.json)

**To get SHA-1 (required for Android OAuth client):**
```bash
cd android
./gradlew signingReport
```
Look for SHA1 under the "debug" variant, or use:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

**Note:** 
- **Android OAuth client** (Google Cloud Console) → Only needs **SHA-1**
- **App Links** (`assetlinks.json`) → Uses **SHA-256** (already configured)

### Step 2: Update Existing Android OAuth Client

You already have an Android OAuth client: `861261774181-f29dderckau7jehjirqdbgfkr3qdqgcl.apps.googleusercontent.com`

This client is referenced in your `google-services.json` with:
- Package name: `com.seagreen.inboxiq1`
- SHA-1 (from google-services.json): `6d6daf17c86c01f17b566b6d5afcf4161f1a72e4`

**To fix the GoogleApiManager error:**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: `inboxiq--api`
3. Navigate to **APIs & Services** → **Credentials**
4. Find your Android OAuth client: `861261774181-f29dderckau7jehjirqdbgfkr3qdqgcl.apps.googleusercontent.com`
5. Click to edit it
6. Verify/Update:
   - **Package name**: `com.seagreen.inboxiq1`
   - **SHA-1 certificate fingerprint**: Should match `6d6daf17c86c01f17b566b6d5afcf4161f1a72e4` (from google-services.json)
   
   **Note:** Android OAuth clients only require SHA-1 (not SHA-256). SHA-256 is used for App Links (`assetlinks.json`), but Google Cloud Console Android OAuth client only has a field for SHA-1.

7. Click **Save**

**If the SHA-1 matches but you still get errors:**

If your SHA-1 already matches (`6D:6D:AF:17:C8:6C:01:F1:7B:56:6B:6D:5A:FC:F4:16:1F:1A:72:E4`), verify:

1. **Package name matches exactly:**
   - Android OAuth client: `com.seagreen.inboxiq1`
   - Your app's `applicationId` in `build.gradle.kts`: `com.seagreen.inboxiq1`
   - Must match exactly (case-sensitive)

2. **Wait for propagation:**
   - Changes in Google Cloud Console can take a few minutes to propagate
   - Try restarting the app after 5-10 minutes

3. **Clear app data and reinstall:**
   - Sometimes Android caches the validation result
   - Uninstall the app completely, then reinstall

4. **Check if the error is actually blocking:**
   - The `GoogleApiManager` error might be a warning that doesn't affect functionality
   - If Firebase is working (which it is), the error might be harmless

**Important:** This Android OAuth client is separate from your Web OAuth client. You have both:
- **Web OAuth client** (`861261774181-sflh559mhcdjjens6fucg5313keg7ajd`) - for OAuth sign-in flow and Gmail API access
- **Android OAuth client** (`861261774181-f29dderckau7jehjirqdbgfkr3qdqgcl`) - ONLY for Google Play Services validation

**Key Point:** The Android OAuth client is NOT used for:
- ❌ Gmail API access
- ❌ OAuth sign-in
- ❌ Getting access/refresh tokens

It's ONLY used by Google Play Services to validate your app when using Firebase. Your Gmail API continues using the Web OAuth client (`OAuthConfig.clientId`).

### Step 3: For Release Builds

If you're building a release APK, you'll need to:
1. Get the SHA-1/SHA-256 from your **release keystore** (not debug)
2. Create a **separate** Android OAuth client in Google Cloud Console with the release fingerprints

### Step 4: Verify

After adding the fingerprints:
1. Restart the app
2. The `GoogleApiManager` errors should disappear
3. Check logs - you should no longer see `DEVELOPER_ERROR`

## Notes

- **This doesn't affect Firebase** - Firebase works fine without this
- **This is for Google Play Services validation** - Some Google APIs require this registration
- **Debug vs Release**: You need separate OAuth clients for debug and release builds (different keystores = different fingerprints)
- **The error is harmless** - Your app works fine, but fixing it removes the error logs

## Alternative: Suppress the Error (Not Recommended)

If you don't need Google Play Services APIs, you could suppress these errors, but it's better to properly register the app.

