import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/app_segmented_bar.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';

class SubscriptionsWindow extends ConsumerStatefulWidget {
  final String accountId;
  const SubscriptionsWindow({super.key, required this.accountId});

  @override
  ConsumerState<SubscriptionsWindow> createState() => _SubscriptionsWindowState();
}

class _SubscriptionsWindowState extends ConsumerState<SubscriptionsWindow> {
  String? _filterLocal;
  final Set<String> _unsubscribedIds = {};

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(emailListProvider);
    return AppWindowDialog(
      title: 'Subscriptions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmentedBar<String?>(
            values: const [null, 'Personal', 'Business'],
            labelBuilder: (v) => v ?? 'All',
            selected: _filterLocal,
            onChanged: (v) => setState(() => _filterLocal = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: messagesAsync.when(
              data: (list) {
                final filtered = list.where((m) {
                  final hasSubs = m.subsLocal;
                  if (!hasSubs) return false;
                  if (_filterLocal == null) return true;
                  return m.localTagPersonal == _filterLocal;
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No subscriptions found',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _subscriptionTile(filtered[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionTile(MessageIndex m) {
    final isDone = _unsubscribedIds.contains(m.id);
    return ListTile(
      dense: true,
      leading: const Icon(Icons.unsubscribe, size: 18),
      title: Text(
        m.subject, 
        maxLines: 2, 
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        m.from, 
        maxLines: 1, 
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: isDone
          ? FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 11),
              ),
              onPressed: null, 
              child: const Text('Unsubscribed'),
            )
          : FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 28),
          textStyle: const TextStyle(fontSize: 11),
        ),
        onPressed: () async {
          // Use stored unsubLink if present; fallback to sender domain
          final repo = MessageRepository();
          final stored = await repo.getUnsubLink(m.id);
          if (stored != null && stored.startsWith('mailto:')) {
            final ok = await GmailSyncService().sendUnsubscribeMailto(widget.accountId, stored);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? 'Unsubscribe email sent' : 'Failed to send unsubscribe email')),
            );
            if (ok) {
              await MessageRepository().updateLocalClassification(m.id, unsubscribed: true);
              setState(() => _unsubscribedIds.add(m.id));
            }
            return;
          }
          final url = stored != null && stored.isNotEmpty ? Uri.tryParse(stored) : _guessUnsubscribeUrl(m);
          // Debug which URL we're opening
          // ignore: avoid_print
          print('[subs] open unsub id=${m.id} url=${url?.toString() ?? 'null'}');
          if (url != null && await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
            if (!mounted) return;
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Manual Unsubscribe'),
                content: const Text('Were you able to unsubscribe successfully?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                ],
              ),
            );
            if (confirmed == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as unsubscribed')));
              await MessageRepository().updateLocalClassification(m.id, unsubscribed: true);
              setState(() => _unsubscribedIds.add(m.id));
            }
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No unsubscribe link available')));
          }
        },
        child: const Text('Unsubscribe'),
      ),
    );
  }

  Uri? _guessUnsubscribeUrl(MessageIndex m) {
    // Basic heuristic: open sender domain
    final from = m.from;
    final match = RegExp(r'<([^>]+)>').firstMatch(from);
    final email = match != null ? match.group(1)! : (from.contains('@') ? from : '');
    if (email.isEmpty) return null;
    final domain = email.split('@').last;
    return Uri.parse('https://$domain');
  }
}


