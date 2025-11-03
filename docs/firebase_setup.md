# Firebase Setup Instructions

## Overview
Firebase sync has been integrated into the app to sync email metadata across devices with minimal traffic.

## Setup Required

### 1. Install Firebase CLI (if not already installed)
```bash
npm install -g firebase-tools
```

### 2. Generate Firebase configuration
```bash
flutter pub global activate flutterfire_cli
flutterfire configure
```
This will create `lib/firebase_options.dart` with your Firebase project configuration.

**IMPORTANT**: This file contains API keys and should NOT be committed to git. It's already in `.gitignore`.

### 3. Add google-services.json file

**Location**: Place the `google-services.json` file in:
```
android/app/google-services.json
```

**How to get it**:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create a new one)
3. Click the gear icon ⚙️ next to "Project Overview"
4. Select "Project settings"
5. Scroll down to "Your apps" section
6. If you don't have an Android app, click "Add app" → Android
7. Enter package name: `com.seagreen.inboxiq1`
8. Download the `google-services.json` file
9. Place it in `android/app/google-services.json`

### 4. Verify Gradle configuration

The following has been added to your Gradle files:
- **android/build.gradle.kts**: Google Services classpath dependency
- **android/app/build.gradle.kts**: Google Services plugin

### 5. Run pub get
```bash
flutter pub get
```

### 6. Clean and rebuild
```bash
flutter clean
flutter pub get
flutter run
```

## Firebase App ID
The app ID provided is: `1:861261774181:android:56de935bbfd21ab7f1358c`
- Make sure this matches your Firebase project configuration
- The Firebase Console should show this app ID for Android

## Features

- **Minimal Traffic**: Only syncs changed metadata, not full emails
- **Smart Sync**: Tracks initial values to avoid syncing unchanged data
- **Real-time Updates**: Listens to Firebase changes and applies to local database
- **Toggle Control**: User can enable/disable sync in Settings (default: OFF)

## Synced Data

1. **Email Personal/Business Tags**: Only syncs when changed from initial value
2. **Email Action Date & Message**: Only syncs when changed from initial value
3. **Sender Preferences**: Syncs on startup and when changed

## Firebase Database Structure

```
users/
  {userEmail}/
    data/
      emailMeta/
        {messageId}/
          current/
            localTagPersonal: "Personal" | "Business" | null
            actionDate: "2024-01-15T10:00:00Z" | null
            actionInsightText: "text" | null
          lastModified: "2024-01-15T10:00:00Z"
      senderPrefs/
        {senderEmail}: "Personal" | "Business" | null
        lastModified: "2024-01-15T10:00:00Z"
```

## Troubleshooting

If you see errors about Firebase not being initialized:
1. Make sure `google-services.json` is in `android/app/`
2. Run `flutter clean` and rebuild
3. Check that the package name in `google-services.json` matches `com.seagreen.inboxiq1`
4. Verify `firebase_options.dart` was generated (if using `flutterfire configure`)
