import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  List<GoogleAccount> _accounts = [];
  bool _signingIn = false;
  bool _forceAdd = false;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _load();
    // No longer resize native window; open add-account as modal instead
  }

  Future<String?> _loadLastActiveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastActiveAccountId');
  }

  Future<void> _saveLastActiveAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastActiveAccountId', accountId);
  }

  static const MethodChannel _channel = MethodChannel('com.actionmail.actionmail/bringToFront');

  Future<void> _bringAppToFront() async {
    // Works on desktop platforms using window_manager
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {
        // Ignore errors if window_manager is not initialized
      }
    }
    // On Android, use platform channel to bring app to front
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('bringToFront');
      } catch (_) {
        // Ignore errors if method channel not set up
      }
    }
    // On iOS, navigation should bring app to front automatically
  }

  Future<void> _load() async {
    print('[splash] _load() started');
    final svc = GoogleAuthService();
    final accs = await svc.loadAccounts();
    print('[splash] loaded ${accs.length} accounts, _forceAdd=$_forceAdd, mounted=$mounted');
    setState(() {
      _accounts = accs;
    });
    if (_accounts.isNotEmpty && mounted && !_forceAdd) {
      print('[splash] auto-routing to home');
      // Get last active account from preferences
      final lastActiveAccountId = await _loadLastActiveAccount();
      
      // Find the account to use: last active if available, otherwise first
      GoogleAccount? accountToUse;
      if (lastActiveAccountId != null) {
        accountToUse = _accounts.firstWhere(
          (acc) => acc.id == lastActiveAccountId,
          orElse: () => _accounts.first,
        );
      } else {
        accountToUse = _accounts.first;
      }
      
      // Save the selected account as last active
      // accountToUse can never be null here since _accounts.isNotEmpty is checked above
      await _saveLastActiveAccount(accountToUse.id);
      
      // Auto-route to home using the selected account
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/home', (route) => false, arguments: accountToUse.id);
      return;
    }
    if (mounted && !_dialogShown) {
      print('[splash] showing dialog');
      _dialogShown = true;
      _showSplashWindow();
    }
  }

  void _showSplashWindow() async {
    print('[splash] _showSplashWindow() called');
    final result = await AppWindowDialog.show(
      context: context,
      title: _forceAdd ? 'Add Account' : 'Welcome to ActionMail',
      size: AppWindowSize.large,
      barrierDismissible: _forceAdd, // allow close only when explicitly adding
      bodyPadding: const EdgeInsets.all(32.0),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // App logo/icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    size: 60,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                // Sign in button - moved directly below graphic, centered
                FilledButton.icon(
                  onPressed: _signingIn
                      ? null
                        : () async {
                          print('[splash] sign-in button pressed');
                          setState(() => _signingIn = true);
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          print('[splash] calling signIn()');
                          final svc = GoogleAuthService();
                          final acc = await svc.signIn();
                          print('[splash] signIn returned, mounted=$mounted, acc=${acc != null}');
                          if (!mounted) return;
                          if (acc != null) {
                            print('[splash] calling upsertAccount');
                            final stored = await svc.upsertAccount(acc);
                            print('[splash] upsertAccount done, mounted=$mounted');
                            if (!mounted) return;
                            // Save as last active account
                            print('[splash] saving last active account');
                            await _saveLastActiveAccount(stored.id);
                            print('[splash] saved, mounted=$mounted');
                            if (!mounted) return;
                            // Bring app to front after sign-in
                            await _bringAppToFront();
                            if (!mounted) return;
                            
                            if (_forceAdd) {
                              // For add account flow, pop with account ID (this will pop AppWindowDialog)
                              Navigator.of(context).pop(stored.id);
                            } else {
                              // For normal sign-in, navigate to home
                              final navigator = Navigator.of(context, rootNavigator: true);
                              navigator.pushNamedAndRemoveUntil('/home', (route) => false, arguments: stored.id);
                            }
                          } else {
                            print('[splash] sign-in failed, showing snackbar');
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(content: Text('Google sign-in not supported on this platform.')),
                            );
                            setState(() => _signingIn = false);
                          }
                        },
                  icon: const Icon(Icons.login),
                  label: Text(_signingIn ? 'Signing in…' : 'Sign in with Google'),
                ),
                const SizedBox(height: 32),
                Text(
                  'ActionMail',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Email that helps you act faster',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _Benefit(icon: Icons.label_important_outline, text: 'Smart action labels and reminders'),
                        _Benefit(icon: Icons.swipe, text: 'Swipe to Archive, Trash, or Restore with one tap'),
                        _Benefit(icon: Icons.star_border_rounded, text: 'Star and filter important conversations'),
                        _Benefit(icon: Icons.sync, text: 'Fast 2‑minute background sync'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    print('[splash] AppWindowDialog.show() returned, result=$result');
    // If user dismissed the dialog without signing in, pop the route
    if (!mounted) return;
    if (_forceAdd) {
      print('[splash] forceAdd=true, popping SplashScreen route with result=$result');
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Read optional flag to prevent auto-route when adding accounts
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _forceAdd = (args['forceAdd'] as bool?) ?? _forceAdd;
      print('[splash] build() called, _forceAdd=$_forceAdd from args');
    }
    // Provide a branded background with gradient
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.email_outlined,
                  size: 48,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'ActionMail',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}


