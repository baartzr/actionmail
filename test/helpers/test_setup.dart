import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:domail/data/db/app_database.dart';

/// Initialize test environment for Flutter tests
/// Call this at the start of test files that need database access
/// Note: debugPrint is automatically suppressed in Flutter tests, no need to modify it
void initializeTestEnvironment() {
  // Initialize FFI for desktop platforms
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // Set AppDatabase to use test database instead of production
  // This prevents tests from modifying production database
  AppDatabase.setTestMode(true);
}

/// Creates a ProviderScope with overrides for testing
/// Use this to provide mock implementations for providers
Widget createTestProviderScope({
  required Widget child,
  List<Override>? overrides,
}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: child,
  );
}

/// Waits for all async operations to complete
Future<void> pumpUntilSettled(WidgetTester tester) async {
  do {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  } while (tester.binding.transientCallbackCount > 0);
}

/// Extensions for easier testing
extension WidgetTesterExtensions on WidgetTester {
  /// Pump and wait for animations to settle
  Future<void> pumpAndSettle() async {
    await pumpUntilSettled(this);
  }
  
  /// Wait for a specific widget to appear
  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (!any(finder) && DateTime.now().isBefore(endTime)) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(any(finder), isTrue, reason: 'Widget not found within timeout');
  }
}

