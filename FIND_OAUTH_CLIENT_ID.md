# Finding Your OAuth 2.0 Client ID for Desktop Sign-In

## Step 1: Navigate to OAuth 2.0 Client IDs (NOT API Keys)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: **InboxIQ Gmail (inboxiq--api)**
3. Navigate to: **APIs & Services → Credentials**
4. **Look for "OAuth 2.0 Client IDs" section** (NOT "API Keys")

## Step 2: Find the Desktop/Web Client

You should see a list of OAuth 2.0 Client IDs. Look for one with:
- **Name**: Could be "Web client" or "Desktop client" or similar
- **Application type**: Web application (for desktop)
- **Client ID**: Should match `861261774181-sflh559mhcdjjens6fucg5313keg7ajd.apps.googleusercontent.com`

## Step 3: Check Authorized Redirect URIs

Click on the OAuth Client ID to edit it. Under "Authorized redirect URIs", you **MUST** have:

```
http://localhost:8400
http://localhost:8400/oauth2redirect
```

**Important**: 
- URIs must match **EXACTLY** (including protocol, port, path)
- Case-sensitive
- No trailing slashes unless specified

## Step 4: Check OAuth Consent Screen

1. Go to **APIs & Services → OAuth consent screen**
2. Verify:
   - **App name**: Shows "InboxIQ" (matches your error message)
   - **User support email**: Must be set
   - **Scopes**: Should include Gmail scopes
   - **Publishing status**: 
     - If "Testing" → Add your email as a test user
     - If "In production" → Available to all users

## If You Can't Find OAuth Client ID

If you only see API Keys and no OAuth 2.0 Client IDs:

1. Click **+ CREATE CREDENTIALS** at the top
2. Select **OAuth client ID**
3. Choose **Application type**: **Web application**
4. **Name**: "Desktop Client" or "ActionMail Desktop"
5. **Authorized redirect URIs**: 
   - `http://localhost:8400`
   - `http://localhost:8400/oauth2redirect`
6. Click **Create**
7. Copy the Client ID and update `lib/config/oauth_config.dart`

## Current Configuration in Your App

Based on your code, the app expects:
- **Client ID**: `861261774181-sflh559mhcdjjens6fucg5313keg7ajd.apps.googleusercontent.com`
- **Redirect URI**: `http://localhost:8400` (desktop)
- **Scopes**: Gmail readonly, modify, email, profile

If the Client ID doesn't exist or has wrong redirect URIs, that's why you're getting "invalid request" error.

