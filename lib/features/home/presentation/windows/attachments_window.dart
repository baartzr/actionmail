import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/app_segmented_bar.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';
import 'package:intl/intl.dart';

class AttachmentsWindow extends ConsumerStatefulWidget {
  const AttachmentsWindow({super.key});

  @override
  ConsumerState<AttachmentsWindow> createState() => _AttachmentsWindowState();
}

class _AttachmentsWindowState extends ConsumerState<AttachmentsWindow> {
  String? _filterLocal;
  final Map<String, List<String>> _attachmentCache = {};
  final Map<String, bool> _loadingAttachments = {};
  final GmailSyncService _syncService = GmailSyncService();

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(emailListProvider);
    return AppWindowDialog(
      title: 'Attachments',
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
                  if (!m.hasAttachments) return false;
                  if (_filterLocal == null) return true;
                  return m.localTagPersonal == _filterLocal;
                }).toList();
                
                // Filter to only show emails that actually have real attachments (not just inline images)
                final emailsWithRealAttachments = filtered.where((message) {
                  final attachments = _attachmentCache[message.id];
                  final isLoading = _loadingAttachments[message.id] ?? false;
                  
                  // Show if:
                  // 1. We haven't checked yet (show while loading)
                  // 2. We're currently loading attachments
                  // 3. We've checked and found real attachments
                  if (isLoading) return true; // Show while loading
                  if (attachments == null) return true; // Haven't checked yet, show it
                  return attachments.isNotEmpty; // Only show if has real attachments
                }).toList();
                
                if (emailsWithRealAttachments.isEmpty) {
                  // Check if any emails are still loading
                  final hasLoading = filtered.any((m) => _loadingAttachments[m.id] ?? false);
                  if (hasLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const Center(child: Text('No emails with real attachments'));
                }
                
                return ListView.separated(
                  itemCount: emailsWithRealAttachments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _emailTile(emailsWithRealAttachments[i]),
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

  Widget _emailTile(MessageIndex m) {
    final df = DateFormat('dd-MMM yyyy');
    final dateStr = df.format(m.internalDate.toLocal());
    final isLoading = _loadingAttachments[m.id] ?? false;
    final attachments = _attachmentCache[m.id] ?? [];
    
    // Load attachments if not already loaded (defer to after build)
    if (!isLoading && attachments.isEmpty && !_attachmentCache.containsKey(m.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_attachmentCache.containsKey(m.id) && !(_loadingAttachments[m.id] ?? false)) {
          _loadAttachments(m);
        }
      });
    }
    
    return ListTile(
      leading: const Icon(Icons.attachment),
      title: Text(m.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(dateStr, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (attachments.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: attachments.map((filename) {
                return Chip(
                  label: Text(
                    filename,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  avatar: const Icon(Icons.insert_drive_file, size: 16),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
        ],
      ),
      onTap: () {
        // TODO: open email detail
      },
    );
  }

  Future<void> _loadAttachments(MessageIndex message) async {
    if (_loadingAttachments[message.id] == true) return;
    
    setState(() {
      _loadingAttachments[message.id] = true;
    });
    
    try {
      final filenames = await _syncService.getAttachmentFilenames(message.accountId, message.id);
      if (mounted) {
        setState(() {
          _attachmentCache[message.id] = filenames;
          _loadingAttachments[message.id] = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('[AttachmentsWindow] Error loading attachments for ${message.id}: $e');
      if (mounted) {
        setState(() {
          _attachmentCache[message.id] = [];
          _loadingAttachments[message.id] = false;
        });
      }
    }
  }
}


