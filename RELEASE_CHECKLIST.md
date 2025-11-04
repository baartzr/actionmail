# ActionMail - Release Readiness Checklist & Google Play Guide

## 📋 Pre-Release Checklist

### 1. Code Quality & Cleanup

#### Remove Debug Code
- [ ] Search for and remove/replace all `debugPrint` statements
- [ ] Remove or comment out all `print` statements (use `debugPrint` only in debug mode)
- [ ] Remove test data or mock data
- [ ] Check for any hardcoded credentials or API keys

**Command to find debug prints:**
```bash
grep -r "debugPrint\|print(" lib/ --include="*.dart"
```

#### Code Review
- [ ] Run `flutter analyze` and fix all warnings/errors
- [ ] Review all `TODO` comments and either implement or remove
- [ ] Ensure no sensitive data in code (API keys, passwords, etc.)
- [ ] Remove unused imports and dependencies

**Commands:**
```bash
flutter analyze
flutter pub outdated
```

### 2. Version & Build Configuration

#### Update Version
- [x] Current version: `1.0.0+1` (in `pubspec.yaml`)
- [ ] Update version number for release (e.g., `1.0.0+1` → `1.0.0+2`)
- [ ] Update build number incrementally for each release

**Format:** `version: MAJOR.MINOR.PATCH+BUILD_NUMBER`
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes
- BUILD: Increment for each release

### 3. Android Configuration

#### App Signing
- [ ] Generate a release keystore (if not already done)

**Generate keystore:**
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Create `android/key.properties`:**
```
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<path-to-keystore>
```

**Update `android/app/build.gradle.kts`:**
```kotlin
// Add at top of file
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

// In android block, replace signingConfigs:
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

#### Application ID
- [ ] Verify unique application ID in `android/app/build.gradle.kts`:
  ```kotlin
  applicationId "com.actionmail.actionmail"  // Should be unique
  ```

#### Permissions Review
- [x] `INTERNET` permission (required for Gmail API)
- [ ] Review all permissions in `AndroidManifest.xml`
- [ ] Remove any unused permissions

#### ProGuard Rules (if minification enabled)
- [ ] Create `android/app/proguard-rules.pro` if using minifyEnabled
- [ ] Add rules for Flutter and Firebase:
```
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**
-keep class com.google.firebase.** { *; }
```

### 4. Privacy & Security

#### Privacy Policy
- [ ] **REQUIRED:** Create a privacy policy webpage
  - Must explain what data you collect (emails, user info)
  - How you use Gmail API
  - Firebase data usage
  - Data storage and security
  - User rights (data deletion, etc.)
- [ ] Host privacy policy online (required for Google Play)

**Privacy Policy Template Sections:**
- Data Collection (Gmail emails, user account info)
- Data Usage (Email sync, action detection)
- Third-party Services (Google APIs, Firebase)
- Data Storage (Local SQLite database)
- User Rights (Access, deletion)
- Contact Information

#### OAuth Consent Screen
- [ ] Verify OAuth consent screen in Google Cloud Console
  - App name, logo, support email
  - Scopes: `gmail.readonly`, `gmail.modify`
  - Privacy policy URL
  - Terms of service URL (if applicable)

#### Security Audit
- [ ] No hardcoded API keys or secrets
- [ ] OAuth tokens stored securely (using `flutter_secure_storage` if needed)
- [ ] Database encryption considered for sensitive data
- [ ] HTTPS for all network requests (already using Gmail API)

### 5. App Store Assets

#### App Icon
- [x] Launcher icons exist in `android/app/src/main/res/mipmap-*`
- [ ] Verify all sizes are present and properly formatted
- [ ] Create feature graphic (1024x500) for Google Play

#### Screenshots
- [ ] Phone screenshots (at least 2, max 8)
  - Minimum: 320px width
  - Maximum: 3840px width
  - Aspect ratio: 16:9 or 9:16
- [ ] Tablet screenshots (optional but recommended)
- [ ] Show key features: email list, action management, filters

#### App Description
- [ ] Short description (80 characters max)
- [ ] Full description (4000 characters max)
  - Highlight key features
  - Action management
  - Gmail integration
  - Cross-device sync (Firebase)
- [ ] What's new (for updates)

### 6. Testing

#### Device Testing
- [ ] Test on multiple Android versions (API 21+)
- [ ] Test on different screen sizes
- [ ] Test on tablets (if supported)
- [ ] Test offline functionality
- [ ] Test OAuth flow end-to-end
- [ ] Test email sync
- [ ] Test action management features

#### Performance Testing
- [ ] Check app startup time
- [ ] Test with large email lists (100+ emails)
- [ ] Memory leak testing
- [ ] Battery usage testing
- [ ] Network usage testing

#### Beta Testing
- [ ] Set up Google Play Internal Testing track
- [ ] Invite 10-20 beta testers
- [ ] Collect feedback and fix critical issues
- [ ] Test for 1-2 weeks minimum

### 7. Build Release APK/AAB

#### Build App Bundle (Recommended for Google Play)
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

#### Build APK (For direct distribution)
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

#### Split APKs by ABI (Optional - smaller downloads)
```bash
flutter build apk --release --split-per-abi
```

#### Verify Build
- [ ] Test the release build on a real device
- [ ] Verify signing is correct: `jarsigner -verify -verbose -certs app-release.apk`
- [ ] Check app size (should be reasonable, <50MB ideal)

---

## 📱 Google Play Console Setup

### Step 1: Create Google Play Developer Account

1. Go to https://play.google.com/console
2. Pay one-time $25 registration fee
3. Complete account setup (name, address, etc.)
4. Wait for approval (usually instant)

### Step 2: Create New App

1. Click "Create app"
2. Fill in:
   - **App name:** ActionMail
   - **Default language:** English (United States)
   - **App or game:** App
   - **Free or paid:** Free
   - **Declarations:** Check all applicable boxes
3. Click "Create app"

### Step 3: App Content

#### Store Listing
1. **App details:**
   - Short description (80 chars)
   - Full description (4000 chars)
   - App icon (512x512 PNG, 32-bit)
   - Feature graphic (1024x500)
   - Screenshots (2-8 required)
   - Phone screenshots required
   - Tablet screenshots (optional)

2. **Categorization:**
   - App category: Productivity
   - Tags: Email, Productivity, Gmail
   - Content rating questionnaire

3. **Privacy Policy:**
   - **REQUIRED:** Privacy policy URL
   - Must be publicly accessible
   - Must cover data collection and usage

#### Content Rating
- Complete the questionnaire
- Get rating (usually Everyone or Teen)
- Required before publishing

#### Data Safety
- Declare data collection practices:
  - Email content (collected)
  - User account info (collected)
  - Data shared with Google (Gmail API)
  - Data stored locally (SQLite)
  - Encryption in transit: Yes
  - Data deletion: User can request

### Step 4: App Access

#### OAuth Consent Screen Verification
- Must be verified in Google Cloud Console
- Scopes must match app usage
- Privacy policy must be linked

#### Sensitive Permissions
- Review all permissions
- Explain why each is needed
- Some may require justification

### Step 5: Production Track Setup

1. Go to "Production" → "Create new release"
2. Upload AAB file (`app-release.aab`)
3. Add release notes (What's new)
4. Review release

### Step 6: Review & Publish

1. **Pre-launch report:** Review automatically generated report
2. **Review checklist:**
   - [ ] All required fields completed
   - [ ] Privacy policy accessible
   - [ ] Content rating complete
   - [ ] Data safety form complete
   - [ ] OAuth consent verified
   - [ ] App tested thoroughly
   - [ ] No critical bugs

3. **Rollout:**
   - Start with staged rollout (20% → 50% → 100%)
   - Monitor crash reports
   - Monitor user feedback

4. **Click "Review"** → **"Start rollout to Production"**

---

## 🔍 Post-Launch Monitoring

### Google Play Console
- Monitor crash reports
- Review user ratings and reviews
- Track app performance metrics
- Monitor ANR (Application Not Responding) reports

### Firebase Console
- Monitor Firebase Analytics
- Check Firestore usage
- Monitor error logs

### Key Metrics to Track
- Crash-free rate (target: >99%)
- ANR rate (target: <0.1%)
- User ratings (target: >4.0)
- App size and download completion rate

---

## 🚨 Common Issues & Solutions

### Issue: App rejected for missing privacy policy
**Solution:** Create and host a privacy policy, link in Play Console

### Issue: OAuth consent screen not verified
**Solution:** Complete verification in Google Cloud Console, wait for approval

### Issue: App crashes on launch
**Solution:** Test release build thoroughly, check ProGuard rules, review logs

### Issue: App size too large
**Solution:** Enable ProGuard, remove unused resources, use split APKs

### Issue: Data safety form incomplete
**Solution:** Complete all sections honestly, explain data collection

---

## 📝 Quick Reference Commands

```bash
# Analyze code
flutter analyze

# Build release app bundle
flutter build appbundle --release

# Build release APK
flutter build apk --release

# Clean build
flutter clean
flutter pub get

# Check app size
flutter build apk --release --analyze-size

# Test release build locally
flutter install --release
```

---

## ✅ Final Checklist Before Publishing

- [ ] All tests pass
- [ ] Release build tested on real devices
- [ ] Privacy policy published and accessible
- [ ] OAuth consent screen verified
- [ ] App icon and screenshots ready
- [ ] Store listing complete
- [ ] Content rating complete
- [ ] Data safety form complete
- [ ] No critical bugs
- [ ] Version number updated
- [ ] Release notes written
- [ ] Beta testing completed
- [ ] Support email configured

---

## 📞 Support

- **Google Play Console Help:** https://support.google.com/googleplay/android-developer
- **Flutter Release Guide:** https://docs.flutter.dev/deployment/android
- **Android App Signing:** https://developer.android.com/studio/publish/app-signing

---

**Good luck with your release! 🚀**

