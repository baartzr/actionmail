# OAuth Sign-In Troubleshooting

## Error: "Access blocked: InboxIQ's request is invalid"

This error indicates a mismatch between your app's OAuth configuration and Google Cloud Console settings.

## Required Configuration in Google Cloud Console

### Step 1: Check OAuth Client ID Configuration

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: **InboxIQ Gmail (inboxiq--api)**
3. Navigate to **APIs & Services → Credentials**
4. Find your OAuth 2.0 Client ID: `861261774181-sflh559mhcdjjens6fucg5313keg7ajd.apps.googleusercontent.com`
5. Click to edit it

### Step 2: Verify Authorized Redirect URIs

Your OAuth client **MUST** have these exact redirect URIs:

**For Desktop:**
```
http://localhost:8400
http://localhost:8400/oauth2redirect
```

**For Android:**
```
http://127.0.0.1:8400/oauth2redirect
com.seagreen.inboxiq1:/oauth2redirect
```

**For iOS:**
```
com.seagreen.inboxiq1:/oauth2redirect
```

### Step 3: Check OAuth Consent Screen

1. Go to **APIs & Services → OAuth consent screen**
2. Verify:
   - **App name**: Should match what you see in the error (currently shows "InboxIQ")
   - **User support email**: Must be set
   - **Developer contact information**: Must be set
   - **App domain** (if required)
   - **Authorized domains**: Add `localhost`, `127.0.0.1`, and your domain if needed

### Step 4: Publishing Status

**If your app is in "Testing" mode:**
- Only test users can sign in
- Add your email as a test user in OAuth consent screen
- Or publish the app (requires verification if requesting sensitive scopes)

**If your app is "In production":**
- All users can sign in
- May require verification for sensitive scopes

## Current App Configuration

Based on your code:

**Client ID:** `861261774181-sflh559mhcdjjens6fucg5313keg7ajd.apps.googleusercontent.com`

**Redirect URIs Used:**
- Desktop: `http://localhost:8400`
- Android: `http://127.0.0.1:8400/oauth2redirect`
- iOS: `com.seagreen.inboxiq1:/oauth2redirect`

**Scopes Requested:**
- `email`
- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/gmail.modify`
- `https://www.googleapis.com/auth/userinfo.profile`

## Quick Fix Checklist

- [ ] OAuth Client ID exists and is correct
- [ ] All redirect URIs are added to the OAuth client
- [ ] OAuth consent screen is configured (app name, email, etc.)
- [ ] Your email is added as a test user (if in testing mode)
- [ ] The package name matches: `com.seagreen.inboxiq1`
- [ ] SHA-1 certificate fingerprint is added (for Android)

## Platform-Specific Checks

### Android
1. Get your SHA-1 fingerprint:
   ```bash
   # Debug keystore
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   
   # Release keystore (if using)
   keytool -list -v -keystore <path-to-keystore> -alias <alias>
   ```
2. Add SHA-1 to OAuth client → Android → SHA-1 certificate fingerprints

### iOS
- Verify bundle ID matches: `com.actionmail.actionmail` or `com.seagreen.inboxiq1`

## Common Issues

1. **Redirect URI mismatch**: Most common issue - URI must match exactly (including trailing slash, protocol, port)
2. **Testing mode**: App is in testing, but user email not added
3. **Missing SHA-1**: Android requires SHA-1 fingerprint for debug/release
4. **App not published**: Required for production use (or add test users)

