import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage PDF viewer preference
/// Controls whether PDFs are opened with internal viewer or system file opener
class PdfViewerPreferenceService {
  static const String _prefsKeyUseInternalViewer = 'pdf_use_internal_viewer';
  
  /// Check if internal PDF viewer should be used
  /// Returns true for internal viewer, false for system file opener
  /// Defaults to false (system file opener) to allow package selection
  Future<bool> useInternalViewer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyUseInternalViewer) ?? false;
  }
  
  /// Set whether to use internal PDF viewer
  Future<void> setUseInternalViewer(bool useInternal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyUseInternalViewer, useInternal);
  }
}

