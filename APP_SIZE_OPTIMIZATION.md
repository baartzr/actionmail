# App Size Optimization Plan

## Current Size: 95.7MB (after minification)
Target: Reduce to 50-60MB (40-50% reduction)

**Note:** Android minification has been applied but shows minimal impact because the largest contributors are native libraries that minification doesn't affect. Focus on removing/replacing large native dependencies.

## Major Size Contributors Identified

### 1. **Syncfusion PDF Libraries** (Estimated: 25-35MB) ⚠️ HIGHEST PRIORITY
- `syncfusion_flutter_pdfviewer: ^27.2.5`
- `syncfusion_flutter_pdf: ^27.2.5`
- These commercial libraries are known to be very large

**Recommendations:**
- **Option A (Best)**: Replace with lighter alternatives
  - Use `pdfx: ^2.9.2` (already in dependencies) as primary PDF viewer
  - Use `pdf: ^3.11.3` (already in dependencies) for PDF generation/editing
  - Remove Syncfusion dependencies entirely
  - **Estimated savings: 20-30MB**

- **Option B**: Make PDF viewer optional/on-demand
  - Only load PDF viewer when user actually opens a PDF
  - Use dynamic imports if possible

### 2. **flutter_inappwebview** (Estimated: 10-15MB)
- Large native library for WebView functionality
- Used for email HTML rendering

**Recommendations:**
- **Option A**: Use platform WebView directly
  - Use `url_launcher` to open emails in external browser
  - For inline viewing, use Flutter's `HtmlWidget` or `flutter_html` (much smaller)
  - **Estimated savings: 8-12MB**

- **Option B**: Keep but optimize
  - Ensure WebView is only loaded when needed
  - Use lazy loading

### 3. **Firebase** (Estimated: 8-12MB)
- `firebase_core: ^4.2.1`
- `cloud_firestore: ^6.1.0`

**Recommendations:**
- **Option A**: Make Firebase optional
  - Only include Firebase if user enables sync feature
  - Use conditional imports
  - **Estimated savings: 6-10MB**

- **Option B**: Use lighter Firebase alternatives
  - Consider using REST API directly instead of Firestore SDK
  - Use Firebase Functions HTTP endpoints

### 4. **PDF Editor Dependencies** (Estimated: 5-8MB)
- `flutter_tesseract_ocr: ^0.4.30` - OCR library (very large)
- Multiple PDF libraries

**Recommendations:**
- **Option A**: Make OCR optional
  - Only include OCR if user explicitly enables it
  - Use cloud-based OCR API instead of local OCR
  - **Estimated savings: 3-5MB**

- **Option B**: Remove if not critical
  - If OCR is rarely used, remove it entirely
  - Use external OCR services via API

### 5. **Android Build Configuration** (Estimated: 5-10MB savings)
Currently missing optimization settings.

**Recommendations:**
Add to `android/app/build.gradle.kts`:

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
        
        // Add these optimizations:
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
```

Create `android/app/proguard-rules.pro`:
```
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**
```

**Estimated savings: 5-10MB**

### 6. **Google APIs** (Estimated: 3-5MB)
- `googleapis: ^11.4.0` - Very large, includes all Google APIs

**Recommendations:**
- Use specific API packages instead of full `googleapis`
- Only import what you need
- **Estimated savings: 2-4MB**

### 7. **Unused Dependencies**
Check for unused packages:
- `ensemble_app_badger` - Only needed if using badges
- `window_to_front` - May be redundant with `window_manager`

## Implementation Priority

### Phase 1: Quick Wins (Estimated: 15-20MB savings)
1. ✅ **COMPLETED** - Add Android code shrinking/minification
   - Added `isMinifyEnabled = true` and `isShrinkResources = true` to build.gradle.kts
   - Created proguard-rules.pro with Flutter and Firebase keep rules
   - **Result:** Minimal impact (95.7MB) - native libraries not affected by minification
2. ✅ Checked unused dependencies - all are used
3. ⚠️ Optimize asset sizes (compress images) - **NEXT STEP**

### Phase 2: Medium Effort (Estimated: 20-30MB savings)
1. ⚠️ Replace Syncfusion PDF libraries with lighter alternatives
2. ⚠️ Make Firebase optional/conditional
3. ⚠️ Optimize Google APIs usage

### Phase 3: Larger Refactoring (Estimated: 10-15MB savings)
1. ⚠️ Replace flutter_inappwebview with lighter solution
2. ⚠️ Make OCR optional or remove
3. ⚠️ Review all native dependencies

## Immediate Actions (Priority Order)

### 1. ✅ COMPLETED - Android Optimization
- Minification added but minimal impact on native libraries

### 2. 🔥 HIGH PRIORITY - Replace Syncfusion PDF Libraries (2-3 hours)
**This is the #1 priority - will save 20-30MB**

Steps:
1. Review current PDF viewer usage in `lib/features/home/presentation/widgets/pdf_viewer_window.dart`
2. Replace Syncfusion with `pdfx` (already in dependencies)
3. Test PDF viewing functionality
4. Remove Syncfusion dependencies from `../pdf_editor/packages/pdf_editor_core/pubspec.yaml`
5. Rebuild and measure size reduction

### 3. Check Asset Sizes (10 minutes)
```powershell
Get-ChildItem -Recurse -Include *.png,*.jpg,*.jpeg | Select-Object FullName, @{Name="Size(MB)";Expression={[math]::Round($_.Length/1MB,2)}}
```
Compress any large images (>100KB)

### 4. Analyze APK Breakdown (when Gradle daemon is working)
```bash
flutter build apk --release --target-platform android-arm64 --analyze-size
```
This will show detailed size breakdown by component

### 5. Consider WebView Alternative (Medium priority)
- Evaluate if `flutter_html` or `flutter_widget_from_html` can replace `flutter_inappwebview`
- Potential savings: 8-12MB

## Expected Results

| Action | Estimated Savings | Effort |
|--------|------------------|--------|
| Android minification | 5-10MB | Low |
| Remove Syncfusion | 20-30MB | Medium |
| Replace WebView | 8-12MB | Medium |
| Make Firebase optional | 6-10MB | Medium |
| Remove OCR | 3-5MB | Low |
| Optimize Google APIs | 2-4MB | Low |
| **Total Potential** | **44-71MB** | |

**Target: Reduce from 95MB to 50-60MB (40-50% reduction)**

## Notes

- Test thoroughly after each optimization
- Some optimizations may require code changes
- Consider user impact (e.g., removing features)
- Measure actual size after each change

