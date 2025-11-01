import 'package:flutter/material.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  bool _signingIn = false;

  Future<void> _saveLastActiveAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastActiveAccountId', accountId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: 'Add Account',
      size: AppWindowSize.large,
      bodyPadding: const EdgeInsets.all(32.0),
      child: SingleChildScrollView(
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
          FilledButton.icon(
            onPressed: _signingIn
                ? null
                : () async {
                    setState(() => _signingIn = true);
                    final navigator = Navigator.of(context);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final svc = GoogleAuthService();
                    final acc = await svc.signIn();
                    if (!mounted) return;
                    if (acc != null) {
                      final stored = await svc.upsertAccount(acc);
                      if (!mounted) return;
                      // Save as last active account
                      await _saveLastActiveAccount(stored.id);
                      if (!mounted) return;
                      navigator.pop(stored.id);
                    } else {
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
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Line(icon: Icons.label_important_outline, text: 'Smart action labels and reminders'),
                  _Line(icon: Icons.swipe, text: 'Swipe to Archive, Trash, or Restore with one tap'),
                  _Line(icon: Icons.star_border_rounded, text: 'Star and filter important conversations'),
                  _Line(icon: Icons.sync, text: 'Fast 2‑minute background sync'),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
