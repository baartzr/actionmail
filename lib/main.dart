import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/app/actionmail_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:domail/firebase_options.dart';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:domail/services/actions/ml_action_extractor.dart';
import 'package:domail/data/db/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:domail/services/sync/firebase_init.dart';
import 'package:domail/services/sms/sms_sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database factory for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Pre-warm database connection to avoid delay on first email load
  try {
    final db = AppDatabase();
    await db.database; // Opens connection if not already open
    debugPrint('[Main] Database connection pre-warmed');
  } catch (e) {
    debugPrint('[Main] Database pre-warm error (non-fatal): $e');
  }
  
  // Kick off heavy initializations in background so UI can appear immediately
  // This includes Firebase (optional) and ML (optional). Neither is required to show local emails.
  // We also add timing logs to trace startup performance on desktop.
  // ignore: unawaited_futures
  Future<void>(() async {
    debugPrint('[Main] Starting Firebase initialization in background...');
    final t0 = DateTime.now();
    bool firebaseInitialized = false;
    try {
      // Initialize Firebase manually (consistent across all platforms)
      debugPrint('[Main] Checking Firebase.apps.isEmpty: ${Firebase.apps.isEmpty}');
      if (Firebase.apps.isEmpty) {
        debugPrint('[Main] Calling Firebase.initializeApp()...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final apps = Firebase.apps;
      if (apps.isEmpty) {
        debugPrint('[Main] Firebase.initializeApp() completed but no apps found');
      } else {
        debugPrint('[Main] Firebase app initialized: ${apps.first.name}');
        firebaseInitialized = true;
      }
      final t1 = DateTime.now();
      if (kDebugMode) {
        debugPrint('[perf] Firebase.initializeApp took ${t1.difference(t0).inMilliseconds}ms');
      }
      // Signal that Firebase init attempt completed
      FirebaseInit.instance.complete();

      final syncService = FirebaseSyncService();
      final syncInitStart = DateTime.now();
      final syncInitialized = await syncService.initialize();
      if (kDebugMode) {
        debugPrint('[perf] FirebaseSyncService.initialize took ${DateTime.now().difference(syncInitStart).inMilliseconds}ms');
      }
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
    } catch (e) {
      debugPrint('[Main] Firebase background initialization error: $e');
      // Still signal completion so awaiters don't hang
      FirebaseInit.instance.complete();
    }

    // Initialize ML Action Extractor (optional) in background
    try {
      final mlStart = DateTime.now();
      final mlInitialized = await MLActionExtractor.initialize();
      final mlMs = DateTime.now().difference(mlStart).inMilliseconds;
      if (kDebugMode) {
        if (mlInitialized) {
          debugPrint('[Main] ML Action Extractor initialized successfully in ${mlMs}ms');
        } else {
          debugPrint('[Main] ML Action Extractor initialized (rule-based) in ${mlMs}ms');
        }
      }
    } catch (e) {
      debugPrint('[Main] ML Action Extractor initialization error: $e');
    }

    // Initialize SMS Sync Manager (optional) in background
    try {
      final smsStart = DateTime.now();
      final smsManager = SmsSyncManager();
      await smsManager.start();
      final smsMs = DateTime.now().difference(smsStart).inMilliseconds;
      if (kDebugMode) {
        debugPrint('[Main] SMS Sync Manager initialization attempted in ${smsMs}ms');
      }
    } catch (e) {
      debugPrint('[Main] SMS Sync Manager initialization error: $e');
    }
  });

  runApp(
    const ProviderScope(
      child: ActionMailApp(),
    ),
  );
}
