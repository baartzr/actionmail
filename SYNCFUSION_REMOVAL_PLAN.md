# Syncfusion Removal Plan - Rollback Guide

## Files to be Modified

1. `../pdf_editor/packages/pdf_editor_core/pubspec.yaml` - Comment out Syncfusion dependencies
2. `../pdf_editor/packages/pdf_editor_core/lib/screens/pdf_viewer_screen.dart` - Replace Syncfusion with pdfx
3. `../pdf_editor/packages/pdf_editor_core/lib/services/static_pdf_editor_service.dart` - Replace Syncfusion PDF with pdf package
4. `../pdf_editor/packages/pdf_editor_core/lib/widgets/checkbox_click_handler.dart` - Update controller type
5. `../pdf_editor/packages/pdf_editor_core/lib/widgets/pdf_toolbar.dart` - Update controller type

## Rollback Instructions

If you need to rollback:

1. **Restore pubspec.yaml:**
   - Uncomment lines with `syncfusion_flutter_pdfviewer` and `syncfusion_flutter_pdf`
   - Remove comments we added

2. **Restore code files:**
   - Use git to restore: `git checkout HEAD -- ../pdf_editor/packages/pdf_editor_core/lib/`
   - Or manually revert changes using git diff

3. **Run:**
   ```bash
   flutter pub get
   flutter clean
   flutter build apk --release
   ```

## Current Status

- [x] Dependencies commented out in pubspec.yaml
- [ ] Code updated to use pdfx (IN PROGRESS)
- [ ] Tested
- [ ] Size measured

## Implementation Strategy

We'll replace Syncfusion components with pdfx equivalents:

1. **SfPdfViewer** → **PdfViewer** (from pdfx)
2. **PdfViewerController** (Syncfusion) → **PdfxController** (from pdfx)  
3. **PdfDocument** (Syncfusion) → **PdfDocument** (from pdf package - already in dependencies)

## Rollback Steps

1. In `../pdf_editor/packages/pdf_editor_core/pubspec.yaml`:
   - Uncomment the two syncfusion lines
   - Remove the comment markers

2. Restore code files:
   ```bash
   git checkout HEAD -- ../pdf_editor/packages/pdf_editor_core/lib/
   ```

3. Run:
   ```bash
   cd ../pdf_editor/packages/pdf_editor_core
   flutter pub get
   cd ../../../domail
   flutter clean
   flutter pub get
   ```

