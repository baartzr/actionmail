import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/app/actionmail_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:actionmail/firebase_options.dart';
import 'package:actionmail/services/sync/firebase_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database factory for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Initialize Firebase (optional - app works without it)
  // This requires:
  // 1. google-services.json in android/app/ (✅ DONE for Android)
  // 2. Run: flutterfire configure (REQUIRED for desktop - generates firebase_options.dart)
  bool firebaseInitialized = false;
  try {
    // Initialize Firebase with platform-specific options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Verify Firebase is actually initialized by checking if any apps exist
    final apps = Firebase.apps;
    if (apps.isEmpty) {
      debugPrint('[Main] Firebase.initializeApp() completed but no apps found');
      debugPrint('[Main] On desktop, you MUST run: flutterfire configure');
      debugPrint('[Main] This generates lib/firebase_options.dart with platform-specific config');
    } else {
      debugPrint('[Main] Firebase app initialized: ${apps.first.name}');
      firebaseInitialized = true;
    }
    
    final syncService = FirebaseSyncService();
    final syncInitialized = await syncService.initialize();
    if (syncInitialized && firebaseInitialized) {
      debugPrint('[Main] Firebase sync service initialized successfully');
    } else {
      if (!firebaseInitialized) {
        debugPrint('[Main] Firebase app not initialized - sync will not work');
      }
      if (!syncInitialized) {
        debugPrint('[Main] Firebase sync service initialization failed');
      }
    }
  } on PlatformException catch (e) {
    // Firebase platform channel errors
    debugPrint('[Main] Firebase PlatformException: $e');
    if (e.code == 'channel-error') {
      debugPrint('[Main] On desktop, you MUST run: flutterfire configure');
      debugPrint('[Main] This generates lib/firebase_options.dart with platform-specific config');
    }
  } on MissingPluginException catch (_) {
    // Firebase plugins not properly registered
    debugPrint('[Main] Firebase plugins not registered');
    debugPrint('[Main] Try: flutter clean && flutter pub get && flutter run');
  } catch (e) {
    // Other Firebase initialization errors
    debugPrint('[Main] Firebase initialization error: $e');
    debugPrint('[Main] Continuing without Firebase - sync feature will be disabled');
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      debugPrint('[Main] IMPORTANT: On desktop, run: flutterfire configure');
      debugPrint('[Main] This generates the required firebase_options.dart file');
    }
  }
  
  runApp(
    const ProviderScope(
      child: ActionMailApp(),
    ),
  );
}
