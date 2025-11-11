# Quick Start: Making ActionMail Release-Ready

## ⚠️ Critical Issues to Fix First

### 1. Update Application ID (CRITICAL)

Your `android/app/build.gradle.kts` has the wrong application ID from a previous project.

**Current:** `com.seagreen.inboxiq1`  
**Should be:** `com.seagreen.domail` (matches your namespace)

**Fix:**
```kotlin
// In android/app/build.gradle.kts, line 25:
applicationId = "com.seagreen.domail"  // Change from inboxiq1

// Also update line 33:
manifestPlaceholders["appAuthRedirectScheme"] = "com.seagreen.domail"
```

**Also update AndroidManifest.xml:**
- Check if any hardcoded references to `inboxiq1` exist
- Update OAuth redirect URLs in Google Cloud Console if needed

### 2. Configure App Signing (REQUIRED)

You're currently using debug signing for release builds. This **must** be fixed.

**Steps:**

1. **Generate keystore:**
```bash
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
- Enter a secure password (save it!)
- Fill in your details
- **IMPORTANT:** Save the keystore file and password securely - you'll need it for every update!

2. **Create `android/key.properties`:**
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
```

3. **Update `android/app/build.gradle.kts`:**

Add at the top (after plugins block):
```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Update the `android` block:
```kotlin
android {
    // ... existing config ...
    
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

4. **Add to `.gitignore`:**
```
android/key.properties
android/*.jks
android/upload-keystore.jks
```

### 3. Create ProGuard Rules

Create `android/app/proguard-rules.pro`:
```
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
```

### 4. Privacy Policy (REQUIRED by Google Play)

You **must** have a privacy policy before publishing. Create one and host it online.

**Minimum requirements:**
- What data you collect (Gmail emails, account info)
- How you use it (email sync, action detection)
- Third-party services (Google APIs, Firebase)
- Data storage (local SQLite)
- How users can delete their data

**Free hosting options:**
- GitHub Pages
- Firebase Hosting
- Google Sites
- Your own website

**Quick template:**
```
Privacy Policy for ActionMail

Last updated: [Date]

1. Data Collection
We collect and store:
- Email content from your Gmail account (with your permission)
- Account information (email address, name)
- Action items and metadata you create

2. How We Use Your Data
- To sync emails across your devices
- To detect and manage action items from emails
- To provide the core functionality of the app

3. Third-Party Services
- Google Gmail API: We use Google's API to access your emails
- Firebase: For cross-device synchronization
- All data transmission is encrypted

4. Data Storage
- Email data is stored locally on your device in an encrypted SQLite database
- Metadata is synced to Firebase (encrypted in transit)

5. Your Rights
- You can delete your data at any time
- You can revoke Gmail access in your Google Account settings
- Contact us at [your-email] for data deletion requests

6. Contact
For privacy concerns, contact: [your-email]
```

### 5. Update OAuth Redirect URLs

If you changed the application ID, update:
1. **Google Cloud Console** → Your project → OAuth 2.0 Client IDs
2. Update authorized redirect URIs to match new package name
3. Update AndroidManifest.xml intent-filter if needed

---

## 🚀 Build and Test Release

### Build Release Bundle
```bash
cd android
flutter build appbundle --release
```

### Test Release APK Locally
```bash
flutter build apk --release
flutter install --release
```

### Verify Signing
```bash
jarsigner -verify -verbose -certs build/app/outputs/flutter-apk/app-release.apk
```

---

## 📋 Pre-Publish Checklist

- [ ] Application ID updated to `com.seagreen.domail`
- [ ] Release signing configured
- [ ] Keystore password saved securely
- [ ] Privacy policy created and hosted
- [ ] OAuth redirect URLs updated
- [ ] App tested on real device with release build
- [ ] No debug prints in code
- [ ] Version number updated in `pubspec.yaml`
- [ ] Google Play Developer account created ($25)

---

## 🎯 Next Steps

1. **Fix the 5 critical issues above** (this file)
2. **Follow the detailed guide** in `RELEASE_CHECKLIST.md`
3. **Set up Google Play Console** account
4. **Upload to Internal Testing** track first
5. **Beta test for 1-2 weeks**
6. **Publish to Production**

---

## ⚡ Quick Commands Reference

```bash
# Clean and rebuild
flutter clean
flutter pub get

# Analyze code
flutter analyze

# Build release
flutter build appbundle --release

# Check for debug prints
grep -r "debugPrint\|print(" lib/ --include="*.dart"
```

---

**Priority Order:**
1. Fix application ID (5 minutes)
2. Set up signing (15 minutes)
3. Create privacy policy (1-2 hours)
4. Update OAuth settings (15 minutes)
5. Test release build (30 minutes)
6. Follow full checklist (1-2 days)

Good luck! 🚀

