import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/app_segmented_bar.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/models/message_index.dart';
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
                  if (m.actionDate == null && (m.actionInsightText == null || m.actionInsightText!.isEmpty)) return false;
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
    final df = DateFormat('dd-MMM yyyy');
    final dateStr = m.actionDate != null ? df.format(m.actionDate!.toLocal()) : '';
    return ListTile(
      leading: const Icon(Icons.event_note),
      title: Text(m.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.actionInsightText != null && m.actionInsightText!.isNotEmpty) Text(m.actionInsightText!),
          if (dateStr.isNotEmpty) Text('Action date: $dateStr', style: const TextStyle(fontSize: 12)),
        ],
      ),
      trailing: Text(m.localTagPersonal ?? '', style: const TextStyle(fontSize: 12)),
      onTap: () {
        // TODO: open email detail
        Navigator.of(context).maybePop();
      },
    );
  }
}


