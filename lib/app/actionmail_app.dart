import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/app/theme/actionmail_theme.dart';
import 'package:actionmail/features/home/presentation/screens/home_screen.dart';
import 'package:actionmail/features/auth/presentation/splash_screen.dart';
import 'package:actionmail/features/settings/presentation/accounts_settings_screen.dart';
import 'package:actionmail/constants/app_constants.dart';

class ActionMailApp extends ConsumerWidget {
  const ActionMailApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: ActionMailTheme.lightTheme,
      darkTheme: ActionMailTheme.darkTheme,
      themeMode: ThemeMode.system,
      routes: {
        '/': (_) => const SplashScreen(),
        '/home': (ctx) => const HomeScreen(),
        '/settings/accounts': (ctx) => const AccountsSettingsScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
