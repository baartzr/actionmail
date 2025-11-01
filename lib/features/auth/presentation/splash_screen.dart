import 'package:flutter/material.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  List<GoogleAccount> _accounts = [];
  bool _loading = true;
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

  Future<void> _load() async {
    final svc = GoogleAuthService();
    final accs = await svc.loadAccounts();
    setState(() {
      _accounts = accs;
      _loading = false;
    });
    if (_accounts.isNotEmpty && mounted && !_forceAdd) {
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
      if (accountToUse != null) {
        await _saveLastActiveAccount(accountToUse.id);
      }
      
      // Auto-route to home using the selected account
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/home', (route) => false, arguments: accountToUse.id);
      return;
    }
    if (mounted && !_dialogShown) {
      _dialogShown = true;
      _showSplashWindow();
    }
  }

  void _showSplashWindow() {
    AppWindowDialog.show(
      context: context,
      title: 'Welcome to ActionMail',
      size: AppWindowSize.large,
      barrierDismissible: _forceAdd, // allow close only when explicitly adding
      bodyPadding: const EdgeInsets.all(32.0),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Column(
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
                      theme.colorScheme.primary.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
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
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _signingIn
                      ? null
                      : () async {
                          setState(() => _signingIn = true);
                          final svc = GoogleAuthService();
                          final acc = await svc.signIn();
                          if (!mounted) return;
                          if (acc != null) {
                            final stored = await svc.upsertAccount(acc);
                            if (!mounted) return;
                            // Save as last active account
                            await _saveLastActiveAccount(stored.id);
                            Navigator.of(context, rootNavigator: true)
                                .pushNamedAndRemoveUntil('/home', (route) => false, arguments: stored.id);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Google sign-in not supported on this platform.')),
                            );
                            setState(() => _signingIn = false);
                          }
                        },
                  icon: const Icon(Icons.login),
                  label: Text(_signingIn ? 'Signing in…' : 'Sign in with Google'),
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      _dialogShown = false;
      if (_forceAdd && mounted) {
        // Return to previous screen when launched as Add Account
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Read optional flag to prevent auto-route when adding accounts
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _forceAdd = (args['forceAdd'] as bool?) ?? _forceAdd;
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
                      theme.colorScheme.primary.withOpacity(0.7),
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


