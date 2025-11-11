import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:domail/features/home/presentation/screens/home_screen.dart';
import 'package:domail/features/auth/presentation/splash_screen.dart';
import 'package:domail/features/settings/presentation/accounts_settings_screen.dart';
import 'package:domail/constants/app_constants.dart';

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
