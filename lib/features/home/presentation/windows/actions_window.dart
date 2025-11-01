import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/app_segmented_bar.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:intl/intl.dart';

class ActionsWindow extends ConsumerStatefulWidget {
  const ActionsWindow({super.key});

  @override
  ConsumerState<ActionsWindow> createState() => _ActionsWindowState();
}

class _ActionsWindowState extends ConsumerState<ActionsWindow> {
  String? _filterLocal; // null=All, 'Personal', 'Business'

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(emailListProvider);
    return AppWindowDialog(
      title: 'Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppSegmentedBar<String?>(
                values: const [null, 'Personal', 'Business'],
                labelBuilder: (v) => v ?? 'All',
                selected: _filterLocal,
                onChanged: (v) => setState(() => _filterLocal = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: messagesAsync.when(
              data: (list) {
                final filtered = list.where((m) {
                  // Only show INBOX emails
                  if (m.folderLabel != 'INBOX') return false;
                  // Must have an action
                  if (m.actionDate == null && (m.actionInsightText == null || m.actionInsightText!.isEmpty)) return false;
                  // Apply Personal/Business filter if set
                  if (_filterLocal == null) return true;
                  return m.localTagPersonal == _filterLocal;
                }).toList()
                  ..sort((a, b) => (a.actionDate ?? DateTime(2100)).compareTo(b.actionDate ?? DateTime(2100)));
                if (filtered.isEmpty) {
                  return const Center(child: Text('No actions'));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _actionTile(filtered[i]),
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

  Widget _actionTile(MessageIndex m) {
    final actionDateFmt = DateFormat('dd-MMM yyyy');
    final receivedDateFmt = DateFormat('dd-MMM yyyy HH:mm');
    final actionDateStr = m.actionDate != null ? actionDateFmt.format(m.actionDate!.toLocal()) : '';
    final receivedDateStr = receivedDateFmt.format(m.internalDate.toLocal());
    
    // Parse sender name and email
    final parsedSender = _parseFrom(m.from);
    final senderName = parsedSender.item1;
    final senderEmail = parsedSender.item2;
    final senderDisplay = senderName.isNotEmpty 
        ? '$senderName <$senderEmail>'
        : senderEmail;
    
    return ListTile(
      leading: const Icon(Icons.event_note),
      title: Text(m.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From: $senderDisplay', style: const TextStyle(fontSize: 12)),
          Text('Received: $receivedDateStr', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          if (m.actionInsightText != null && m.actionInsightText!.isNotEmpty) 
            Text(m.actionInsightText!, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (actionDateStr.isNotEmpty) 
            Text('Action date: $actionDateStr', style: const TextStyle(fontSize: 12)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _openEditActionDialog(m),
            tooltip: 'Edit action',
          ),
          Text(m.localTagPersonal ?? '', style: const TextStyle(fontSize: 12)),
        ],
      ),
      onTap: () => _openEmailViewer(m),
    );
  }

  void _openEmailViewer(MessageIndex message) {
    showDialog(
      context: context,
      builder: (ctx) => EmailViewerDialog(
        message: message,
        accountId: message.accountId,
      ),
    );
  }

  Future<void> _openEditActionDialog(MessageIndex message) async {
    DateTime? tempDate = message.actionDate ?? DateTime.now();
    final textController = TextEditingController(text: message.actionInsightText ?? '');

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sbSet) {
            return AlertDialog(
              title: const Text('Edit Action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        sbSet(() {
                          tempDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(tempDate != null
                        ? DateFormat('dd-MMM, y').format(tempDate!)
                        : 'Pick date'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'actionDate': tempDate,
                      'actionText': textController.text.trim(),
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final actionDate = result['actionDate'] as DateTime?;
      final actionText = result['actionText'] as String?;
      // Persist to database
      await MessageRepository().updateAction(message.id, actionDate, actionText);
      // Update in-memory state
      ref.read(emailListProvider.notifier).setAction(
        message.id,
        actionDate,
        actionText,
      );
    }
  }

  /// Parse sender name and email from "from" field
  Tuple2<String, String> _parseFrom(String from) {
    final emailRegex = RegExp(r'<([^>]+)>');
    final match = emailRegex.firstMatch(from);
    if (match != null) {
      final email = match.group(1)!.trim();
      final name = from.replaceAll(match.group(0)!, '').trim();
      return Tuple2(name.replaceAll('"', ''), email);
    }
    // Fallbacks
    if (from.contains('@')) {
      return Tuple2('', from.trim());
    }
    return Tuple2(from.trim(), from.trim());
  }
}

class Tuple2<A, B> {
  final A item1;
  final B item2;
  const Tuple2(this.item1, this.item2);
}


