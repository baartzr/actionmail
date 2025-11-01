import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/app/actionmail_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database factory for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // TODO: Initialize database for ActionMail
  // TODO: Initialize auth services (reuse from inboxiq)
  
  runApp(
    const ProviderScope(
      child: ActionMailApp(),
    ),
  );
}
