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
  final Set<String> _pendingLoads = {}; // Track messages currently being loaded to prevent duplicates
  final Set<String> _seenMessages = {}; // Track which messages we've seen to prevent showing before check starts
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
                // First filter by hasAttachments and local tag
                final filtered = list.where((m) {
                  if (!m.hasAttachments) return false;
                  if (_filterLocal == null) return true;
                  return m.localTagPersonal == _filterLocal;
                }).toList();
                
                // Start verification for emails that haven't been checked yet
                // NOTE: We mark as "seen" in postFrameCallback, not during build, to prevent showing before verification starts
                bool needsAsyncLoad = false;
                final newMessages = <String>[];
                
                for (final message in filtered) {
                  if (!_attachmentCache.containsKey(message.id)) {
                    if (!_seenMessages.contains(message.id)) {
                      // Track new messages to mark as seen after rebuild
                      newMessages.add(message.id);
                    }
                    if (!(_loadingAttachments[message.id] ?? false)) {
                      // Mark as loading and trigger async check
                      _loadingAttachments[message.id] = true;
                      needsAsyncLoad = true;
                    }
                  }
                }
                
                // Mark new messages as seen and trigger async loading in postFrameCallback
                if (needsAsyncLoad || newMessages.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    // Mark as seen AFTER first build, so they only show after verification starts
                    for (final messageId in newMessages) {
                      _seenMessages.add(messageId);
                    }
                    // Trigger rebuild to show emails that are now "seen" and loading
                    if (newMessages.isNotEmpty) {
                      setState(() {});
                    }
                    // Actually perform the async load
                    for (final message in filtered) {
                      if (_loadingAttachments[message.id] == true && !_attachmentCache.containsKey(message.id)) {
                        _loadAttachments(message);
                      }
                    }
                  });
                }
                
                // Filter to only show emails that have been verified to have real attachments
                // CRITICAL: Only show emails that have completed verification (attachments != null)
                // This prevents emails from appearing before verification completes
                final emailsWithRealAttachments = filtered.where((message) {
                  final attachments = _attachmentCache[message.id];
                  
                  // ONLY show if verification is complete AND we found real attachments
                  if (attachments != null && attachments.isNotEmpty) {
                    return true;
                  }
                  
                  // Don't show if:
                  // - Not verified yet (attachments == null)
                  // - Verified but no real attachments (attachments.isEmpty)
                  return false;
                }).toList();
                
                // Check if any emails are still being verified
                final hasPendingVerification = filtered.any((m) {
                  return !_attachmentCache.containsKey(m.id);
                });
                
                if (hasPendingVerification) {
                  // Show loading indicator while verification is in progress
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (emailsWithRealAttachments.isEmpty) {
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
    final isMobile = MediaQuery.of(context).size.width < 900;
    
    // Note: Attachment loading is triggered in the build method above to avoid duplicates
    
    return ListTile(
      leading: isMobile ? null : const Icon(Icons.attachment),
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
    // Prevent duplicate concurrent loads
    if (_attachmentCache.containsKey(message.id)) {
      // Already loaded, no need to reload
      return;
    }
    
    if (_pendingLoads.contains(message.id)) {
      // Already loading, don't start another load
      return;
    }
    
    // Mark as pending and loading
    _pendingLoads.add(message.id);
    bool wasAlreadyLoading = _loadingAttachments[message.id] == true;
    if (!wasAlreadyLoading) {
      if (!mounted) {
        _pendingLoads.remove(message.id);
        return;
      }
      setState(() {
        _loadingAttachments[message.id] = true;
      });
    } else if (mounted) {
      // If already marked as loading, trigger rebuild to show loading state
      setState(() {});
    }
    
    try {
      final filenames = await _syncService.getAttachmentFilenames(message.accountId, message.id);
      if (mounted) {
        setState(() {
          _attachmentCache[message.id] = filenames;
          _loadingAttachments[message.id] = false;
          _pendingLoads.remove(message.id);
        });
      } else {
        _pendingLoads.remove(message.id);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[AttachmentsWindow] Error loading attachments for ${message.id}: $e');
      if (mounted) {
        setState(() {
          _attachmentCache[message.id] = [];
          _loadingAttachments[message.id] = false;
          _pendingLoads.remove(message.id);
        });
      } else {
        _pendingLoads.remove(message.id);
      }
    }
  }
}


