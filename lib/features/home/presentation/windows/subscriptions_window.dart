import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/personal_business_filter.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';
import 'package:actionmail/features/home/presentation/widgets/email_viewer_dialog.dart';

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
    final isMobile = MediaQuery.of(context).size.width < 900;
    return AppWindowDialog(
      title: 'Subscriptions',
      bodyPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8.0 : 24.0,
        vertical: 24.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PersonalBusinessFilter(
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

                // Group by sender and get most recent message per sender
                final Map<String, MessageIndex> senderToLatestMessage = {};
                final Map<String, List<MessageIndex>> senderToAllMessages = {};
                
                for (final m in filtered) {
                  final senderEmail = _extractEmail(m.from);
                  if (senderEmail.isEmpty) continue;
                  
                  senderToAllMessages.putIfAbsent(senderEmail, () => []).add(m);
                  
                  final existing = senderToLatestMessage[senderEmail];
                  if (existing == null || m.internalDate.isAfter(existing.internalDate)) {
                    senderToLatestMessage[senderEmail] = m;
                  }
                }

                // Sort by most recent date
                final latestMessages = senderToLatestMessage.values.toList()
                  ..sort((a, b) => b.internalDate.compareTo(a.internalDate));

                return ListView.separated(
                  itemCount: latestMessages.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final message = latestMessages[i];
                    final senderEmail = _extractEmail(message.from);
                    final allMessages = senderToAllMessages[senderEmail] ?? [];
                    return _subscriptionTile(message, allMessages);
                  },
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

  Widget _subscriptionTile(MessageIndex m, List<MessageIndex> allMessagesFromSender) {
    final isDone = _unsubscribedIds.contains(m.id);
    final isMobile = MediaQuery.of(context).size.width < 900;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // Calculate frequency and count
    final count = allMessagesFromSender.length;
    final frequency = _calculateFrequency(allMessagesFromSender);
    
    return InkWell(
      onTap: () => _openEmail(m),
      child: ListTile(
        dense: true,
        leading: isMobile ? null : const Icon(Icons.unsubscribe, size: 18),
        title: Text(
          m.subject, 
          maxLines: 2, 
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.from, 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              '$frequency • $count ${count == 1 ? 'email' : 'emails'}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: isDone
            ? FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  minimumSize: const Size(0, 28),
                  textStyle: const TextStyle(fontSize: 11),
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.8),
                  foregroundColor: cs.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: null, 
                child: const Text('Unsubscribed'),
              )
            : FilledButton(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
            minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
            textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11)),
            backgroundColor: WidgetStatePropertyAll(cs.primary.withValues(alpha:0.7)),
            foregroundColor: WidgetStatePropertyAll(cs.onPrimary),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            elevation: const WidgetStatePropertyAll(0),
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
              // Show confirmation dialog before opening browser
              if (!mounted) return;
              final shouldOpen = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Manual Unsubscribe'),
                  content: const Text('This website doesn\'t have auto-unsubscribe. Click OK to open the website for manual unsubscribe.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Close'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
              
              if (shouldOpen != true || !mounted) return;
              
              // Open the unsubscribe link
              await launchUrl(url, mode: LaunchMode.externalApplication);
              
              // Show confirmation dialog asking if they unsubscribed
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
      ),
    );
  }

  void _openEmail(MessageIndex message) {
    showDialog(
      context: context,
      builder: (ctx) => EmailViewerDialog(
        message: message,
        accountId: message.accountId,
      ),
    );
  }

  String _extractEmail(String from) {
    final match = RegExp(r'<([^>]+)>').firstMatch(from);
    if (match != null) {
      return match.group(1)!.trim().toLowerCase();
    }
    if (from.contains('@')) {
      return from.trim().toLowerCase();
    }
    return '';
  }

  String _calculateFrequency(List<MessageIndex> messages) {
    if (messages.length < 2) return 'Infrequent';
    
    // Sort by date
    final sorted = List<MessageIndex>.from(messages)
      ..sort((a, b) => a.internalDate.compareTo(b.internalDate));
    
    // Calculate average days between messages
    double totalDays = 0;
    int intervals = 0;
    
    for (int i = 1; i < sorted.length; i++) {
      final days = sorted[i].internalDate.difference(sorted[i - 1].internalDate).inDays;
      if (days > 0) {
        totalDays += days;
        intervals++;
      }
    }
    
    if (intervals == 0) return 'Infrequent';
    
    final avgDays = totalDays / intervals;
    
    if (avgDays < 1.5) return 'Daily';
    if (avgDays < 4) return 'Every few days';
    if (avgDays < 8) return 'Weekly';
    if (avgDays < 15) return 'Bi-weekly';
    if (avgDays < 35) return 'Monthly';
    if (avgDays < 90) return 'Quarterly';
    return 'Infrequent';
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


