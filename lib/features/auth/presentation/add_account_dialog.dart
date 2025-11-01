import 'package:flutter/material.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  bool _signingIn = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: 'Add account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email that helps you act faster', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _signingIn
                  ? null
                  : () async {
                      setState(() => _signingIn = true);
                      final svc = GoogleAuthService();
                      final acc = await svc.signIn();
                      if (acc != null) {
                        final stored = await svc.upsertAccount(acc);
                        if (!mounted) return;
                        Navigator.of(context).pop(stored.id);
                      } else {
                        if (!mounted) return;
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
