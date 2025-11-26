# Making PDF Editor Optional - Feasibility Analysis

## Current Architecture

### How It Works Now
1. **Dependency**: `pdf_editor_core` is a **local path dependency** in `pubspec.yaml`
   ```yaml
   pdf_editor_core:
     path: ../pdf_editor/packages/pdf_editor_core
   ```

2. **Integration Points** (3 places):
   - `lib/features/home/presentation/widgets/email_viewer_dialog.dart` (line 1541-1544)
   - `lib/features/home/presentation/widgets/compose_email_dialog.dart` (line 516-519)
   - `lib/features/home/presentation/windows/attachments_window.dart` (line 322-329)

3. **Fallback Already Exists**: 
   - `PdfViewerPreferenceService` controls viewer choice
   - If `useInternalViewer()` returns `false`, it uses `OpenFile.open()` (system file selector)
   - **Default is already `false`** (system file opener)

## The Challenge

### Problem: Compile-Time Dependency
The PDF editor is imported at **compile time**:
```dart
import 'package:pdf_editor_core/pdf_editor_core.dart';
```

This means:
- ❌ App won't compile if `pdf_editor_core` is missing
- ❌ All Syncfusion dependencies are bundled even if unused
- ❌ Can't make it truly optional at runtime

## Solution Options

### Option 1: Conditional Imports (Recommended) ⭐
Use Dart's conditional imports to make it optional at compile time.

**How it works:**
1. Create a stub/interface file that's always available
2. Use conditional imports to load real implementation if available
3. Check availability at runtime

**Implementation:**
```dart
// pdf_viewer_stub.dart (always available)
class PdfViewerWindow {
  static Future<void> open(BuildContext context, {required String filePath}) async {
    // Fallback to system opener
    await OpenFile.open(filePath);
  }
}

// pdf_viewer_impl.dart (only if pdf_editor_core available)
import 'package:pdf_editor_core/pdf_editor_core.dart';
// ... real implementation

// pdf_viewer_window.dart
import 'pdf_viewer_stub.dart'
    if (dart.library.io) 'pdf_viewer_impl.dart';
```

**Pros:**
- ✅ App compiles without PDF editor
- ✅ No Syncfusion dependencies if not included
- ✅ Runtime check for availability
- ✅ Clean separation

**Cons:**
- ⚠️ Requires refactoring import structure
- ⚠️ Need to handle stub vs real implementation

### Option 2: Separate Plugin Package
Package PDF editor as a separate Flutter plugin that can be installed separately.

**How it works:**
1. Create `pdf_editor_plugin` as separate pub.dev package (or local installable)
2. Main app checks if plugin is installed
3. If not installed, use system file opener

**Implementation:**
```dart
// Check if plugin available
bool isPdfEditorAvailable = await PdfEditorPlugin.isAvailable();
if (isPdfEditorAvailable) {
  await PdfEditorPlugin.open(filePath);
} else {
  await OpenFile.open(filePath);
}
```

**Pros:**
- ✅ True optional dependency
- ✅ Users can install separately
- ✅ Can be distributed separately

**Cons:**
- ⚠️ Complex - requires plugin architecture
- ⚠️ Need separate distribution mechanism
- ⚠️ More maintenance overhead

### Option 3: Runtime Try-Catch with Dynamic Loading
Use `dart:mirrors` or similar to dynamically load if available.

**Pros:**
- ✅ Runtime detection

**Cons:**
- ❌ `dart:mirrors` not available on Flutter web/mobile
- ❌ Complex and fragile
- ❌ Not recommended for Flutter

### Option 4: Build Variants/Flavors
Create separate app builds: "lite" (no PDF editor) and "full" (with PDF editor).

**How it works:**
1. Use Flutter flavors/build variants
2. `pubspec.yaml` conditionally includes dependency
3. Different builds for different feature sets

**Pros:**
- ✅ Clean separation
- ✅ Can have different app sizes

**Cons:**
- ⚠️ Users can't download editor after install
- ⚠️ Need to maintain multiple builds
- ⚠️ Not truly "optional download"

## Recommended Approach: Option 1 (Conditional Imports)

### Implementation Plan

1. **Create Interface/Stub:**
   ```dart
   // lib/services/pdf_viewer_service_stub.dart
   class PdfViewerService {
     static Future<bool> isAvailable() => Future.value(false);
     static Future<void> open(BuildContext context, String filePath) async {
       await OpenFile.open(filePath);
     }
   }
   ```

2. **Create Real Implementation:**
   ```dart
   // lib/services/pdf_viewer_service_impl.dart
   import 'package:pdf_editor_core/pdf_editor_core.dart';
   
   class PdfViewerService {
     static Future<bool> isAvailable() => Future.value(true);
     static Future<void> open(BuildContext context, String filePath) async {
       await PdfViewerWindow.open(context, filePath: filePath);
     }
   }
   ```

3. **Use Conditional Import:**
   ```dart
   // lib/services/pdf_viewer_service.dart
   import 'pdf_viewer_service_stub.dart'
       if (dart.library.io) 'pdf_viewer_service_impl.dart';
   ```

4. **Update Usage:**
   ```dart
   // In attachments_window.dart, etc.
   if (await PdfViewerService.isAvailable() && 
       await PdfViewerPreferenceService().useInternalViewer()) {
     await PdfViewerService.open(context, file.path);
   } else {
     await OpenFile.open(file.path);
   }
   ```

5. **Make Dependency Optional:**
   - Comment out `pdf_editor_core` in `pubspec.yaml` by default
   - Users who want PDF editor uncomment it
   - Or create separate build configurations

## Size Impact

### Without PDF Editor:
- **Current**: 95.7MB (with Syncfusion)
- **After removal**: ~65-75MB (estimated 20-30MB savings)
- **Dependencies removed**: Syncfusion PDF libraries (~25-35MB)

### With PDF Editor (Optional):
- Users who need it: Include dependency, get full functionality
- Users who don't: Smaller app size, use system PDF viewers

## User Experience

### Scenario 1: User Without PDF Editor
1. Opens PDF attachment
2. System file selector appears
3. Can choose any installed PDF app (Adobe, Chrome, etc.)
4. **No difference from current default behavior**

### Scenario 2: User With PDF Editor
1. Opens PDF attachment
2. If preference set: Internal viewer opens
3. If preference not set: System file selector (current default)
4. **Same as current behavior**

## Rollback Safety

Since we're using conditional imports:
- ✅ Code compiles with or without dependency
- ✅ Easy to add/remove by commenting `pubspec.yaml`
- ✅ No breaking changes to existing code
- ✅ Can test both scenarios easily

## Next Steps (If You Want to Proceed)

1. ✅ Create stub implementation
2. ✅ Create real implementation wrapper
3. ✅ Update all 3 usage points
4. ✅ Make dependency optional in `pubspec.yaml`
5. ✅ Test with and without dependency
6. ✅ Measure size difference

## Questions to Consider

1. **Distribution**: How will users "download" the PDF editor?
   - Separate app/plugin?
   - Build variant?
   - Just uncomment in source?

2. **Discovery**: How do users know PDF editor is available?
   - Settings toggle?
   - Auto-detect?
   - Documentation?

3. **Maintenance**: Two code paths to maintain?
   - Stub implementation
   - Real implementation
   - Worth the complexity?

## Recommendation

**Yes, it's possible and feasible** using conditional imports. The architecture already supports it (preference system + fallback). Main work is:
- Refactoring imports to use conditional loading
- Making dependency optional in `pubspec.yaml`
- Testing both scenarios

**Estimated effort**: 2-3 hours
**Size savings**: 20-30MB for users who don't need PDF editing
**Risk**: Low (fallback already exists)

