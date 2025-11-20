import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ViewMode {
  tile,
  table,
}

class ViewModeNotifier extends StateNotifier<ViewMode> {
  static const String _prefsKey = 'default_view_mode';
  
  ViewModeNotifier() : super(ViewMode.tile) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final modeString = prefs.getString(_prefsKey);
    if (modeString != null) {
      state = modeString == 'table' ? ViewMode.table : ViewMode.tile;
    }
  }

  Future<void> setViewMode(ViewMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode == ViewMode.table ? 'table' : 'tile');
  }

  Future<void> setDefaultView(ViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode == ViewMode.table ? 'table' : 'tile');
    // Also update current view if it matches the old default
    if (state == (mode == ViewMode.table ? ViewMode.tile : ViewMode.table)) {
      state = mode;
    }
  }

  Future<ViewMode> getDefaultView() async {
    final prefs = await SharedPreferences.getInstance();
    final modeString = prefs.getString(_prefsKey);
    return modeString == 'table' ? ViewMode.table : ViewMode.tile;
  }
}

final viewModeProvider = StateNotifierProvider<ViewModeNotifier, ViewMode>((ref) {
  return ViewModeNotifier();
});

