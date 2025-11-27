# pdfx vs Syncfusion - Usage Analysis

## Current Usage

### Syncfusion (`syncfusion_flutter_pdfviewer` + `syncfusion_flutter_pdf`)

**Used for:**
1. **PDF Viewing** - `SfPdfViewer` widget (main viewer UI)
   - Location: `pdf_viewer_screen.dart` line 1040
   - Purpose: Display PDFs in the viewer interface
   - Features: Zoom, scroll, page navigation, text selection

2. **PDF Editing** - `PdfDocument`, `PdfPage`, `PdfPen`, etc.
   - Location: `static_pdf_editor_service.dart`
   - Purpose: 
     - Drawing checkboxes (`_drawCheckbox`)
     - Drawing text fields (`_drawTextField`)
     - Form field manipulation (`_applyFormFieldValues`)
     - Saving edited PDFs

3. **Page Size Detection**
   - Location: `pdf_viewer_screen.dart` line 611
   - Purpose: Get PDF page dimensions

### pdfx (`pdfx` package)

**Used for:**
1. **Text Extraction** - `PdfDocument.openFile()`
   - Location: `poppler_service.dart` lines 13, 88, 125
   - Purpose: Extract text from PDFs for editing
   - Note: Currently returns empty (text extraction not fully implemented)

2. **PDF Reading** - Opening PDFs for analysis
   - Purpose: Check for form fields, get page count
   - Note: Form field detection also returns false (not fully implemented)

3. **Alternative PDF Creation** - `applyTextEditsToPdf()`
   - Location: `poppler_service.dart` line 120
   - Purpose: Create new PDFs with edits (renders original as image + overlays)
   - Note: This method exists but may not be actively used

## Overlap Analysis

### Can pdfx Replace Syncfusion for Viewing?

**pdfx has `PdfViewer` widget** that could potentially replace `SfPdfViewer`:
- ✅ Can display PDFs
- ✅ Supports zoom, scroll, page navigation
- ❌ May not have all the same features (text selection, annotations, etc.)
- ❌ Different API - would require refactoring

### Can pdfx Replace Syncfusion for Editing?

**pdfx limitations:**
- ❌ No direct PDF editing API (can't draw on existing PDFs)
- ❌ No form field manipulation
- ✅ Can create new PDFs (but loses original structure)

**Syncfusion advantages:**
- ✅ Can edit existing PDFs in-place
- ✅ Preserves PDF structure (form fields, annotations)
- ✅ Can draw directly on pages
- ✅ Form field API for filling existing forms

## Current State

### Active Usage:
- **Syncfusion**: ✅ Actively used for viewing and editing
- **pdfx**: ⚠️ Mostly placeholder code (text extraction returns empty, form detection returns false)

### Redundancy:
- **Viewing**: Both can view PDFs, but only Syncfusion is used
- **Text Extraction**: pdfx is used but doesn't actually work (returns empty)
- **Editing**: Only Syncfusion can do in-place editing

## Recommendation

### Option 1: Keep Both (Current)
- **Syncfusion**: Primary viewer + editing
- **pdfx**: Text extraction (when implemented) + fallback operations
- **Size**: Both bundled (~25-35MB for Syncfusion + ~2-3MB for pdfx)

### Option 2: Remove pdfx
- **If text extraction is never implemented**, pdfx is mostly unused
- **Savings**: ~2-3MB
- **Risk**: Low - most pdfx code returns empty/false anyway

### Option 3: Replace Syncfusion with pdfx
- **For viewing**: Possible but requires refactoring
- **For editing**: ❌ **Not possible** - pdfx can't edit existing PDFs
- **Would lose**: Form field filling, in-place editing

## Answer: Do You Need Both?

**Short answer: No, but with caveats**

1. **pdfx is mostly unused** - Text extraction doesn't work, form detection doesn't work
2. **Syncfusion is essential** - Needed for viewing and editing
3. **pdfx could be removed** - If you're not planning to implement text extraction

**However:**
- If you plan to implement text extraction later, keep pdfx
- If you want a lighter alternative for viewing, pdfx could replace Syncfusion viewer (but lose editing)

## Size Impact

- **Remove pdfx**: Save ~2-3MB
- **Remove Syncfusion**: Save ~25-35MB (but lose editing capabilities)
- **Keep both**: Current state (~27-38MB total)

## Recommendation

**Remove pdfx** if:
- Text extraction is not a priority
- You don't need the alternative PDF creation method
- You want to save ~2-3MB

**Keep pdfx** if:
- You plan to implement text extraction
- You want a fallback option
- The 2-3MB doesn't matter

