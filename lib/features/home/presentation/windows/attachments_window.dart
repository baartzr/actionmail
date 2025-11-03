import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/personal_business_filter.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';
import 'package:actionmail/features/home/presentation/widgets/email_viewer_dialog.dart';
// import 'package:actionmail/services/auth/google_auth_service.dart'; // unused
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:open_file/open_file.dart';

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
          PersonalBusinessFilter(
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
      title: InkWell(
        onTap: () => _openEmail(m),
        child: Text(m.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openEmail(m),
            child: Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
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
                return InkWell(
                  onTap: () => _openAttachment(m, filename),
                  child: Chip(
                    label: Text(
                      filename,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    avatar: const Icon(Icons.insert_drive_file, size: 16),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
        ],
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

  Future<void> _openAttachment(MessageIndex message, String filename) async {
    try {
      debugPrint('[Attachments] Starting to open attachment: $filename');
      
      // Get attachment download info (includes URL and access token to avoid double token check)
      final info = await _syncService.getAttachmentDownloadInfo(message.accountId, message.id, filename);
      if (info == null) {
        debugPrint('[Attachments] Attachment info is null');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment not found')),
        );
        return;
      }

      final url = info['url'] as Uri;
      final accessToken = info['accessToken'] as String;
      debugPrint('[Attachments] Got attachment URL: ${url.toString()}');

      // Download the attachment using Gmail API with auth token
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      
      debugPrint('[Attachments] Download response status: ${resp.statusCode}');
      
      if (resp.statusCode == 200) {
        // Gmail API returns JSON with base64url-encoded data
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final base64Data = json['data'] as String?;
        if (base64Data == null || base64Data.isEmpty) {
          debugPrint('[Attachments] Attachment data is empty');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attachment data is empty')),
          );
          return;
        }

        // Decode base64url data (Gmail API uses base64url encoding)
        // Convert base64url to base64 for decoding
        String base64 = base64Data.replaceAll('-', '+').replaceAll('_', '/');
        // Add padding if needed
        switch (base64.length % 4) {
          case 1:
            base64 += '===';
            break;
          case 2:
            base64 += '==';
            break;
          case 3:
            base64 += '=';
            break;
        }
        final bytes = base64Decode(base64);
        debugPrint('[Attachments] Decoded ${bytes.length} bytes');

        // Save to file - use external storage directory on Android for shareability
        Directory targetDir;
        if (Platform.isAndroid) {
          // On Android, try external files directory first, then external storage, then temp
          targetDir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
          debugPrint('[Attachments] Android targetDir: ${targetDir.path}');
        } else {
          // On desktop, use temporary directory
          targetDir = await getTemporaryDirectory();
          debugPrint('[Attachments] Desktop targetDir: ${targetDir.path}');
        }
        
        // Sanitize filename to avoid issues with special characters
        final sanitizedFilename = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final file = File(path.join(targetDir.path, sanitizedFilename));
        await file.writeAsBytes(bytes);
        debugPrint('[Attachments] Saved file to: ${file.path}');
        debugPrint('[Attachments] File exists: ${await file.exists()}');
        debugPrint('[Attachments] File size: ${await file.length()}');

        // Open the file using platform-specific method
        if (Platform.isAndroid || Platform.isIOS) {
          // On mobile, use open_file package which handles FileProvider automatically
          try {
            debugPrint('[Attachments] Attempting to open file with open_file: ${file.path}');
            final result = await OpenFile.open(file.path);
            debugPrint('[Attachments] open_file result: type=${result.type}, message=${result.message}');
            if (result.type != ResultType.done) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cannot open file: ${result.message}')),
              );
            }
          } catch (e) {
            debugPrint('[Attachments] Error opening file with open_file: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error opening file: $e')),
            );
          }
        } else {
          // Desktop platforms
          try {
            final uri = Uri.file(file.path);
            debugPrint('[Attachments] Attempting to open file URI: ${uri.toString()}');
            final canLaunch = await canLaunchUrl(uri);
            debugPrint('[Attachments] canLaunchUrl result: $canLaunch');
            if (canLaunch) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              debugPrint('[Attachments] launchUrl completed');
            } else {
              // Fallback to Process.run for Windows if url_launcher fails
              if (Platform.isWindows) {
                debugPrint('[Attachments] Trying Windows Process.run fallback');
                final quotedPath = '"${file.path.replaceAll('"', '""')}"';
                await Process.run(
                  'cmd.exe',
                  ['/c', 'start', '', quotedPath],
                  runInShell: true,
                );
                debugPrint('[Attachments] Windows Process.run completed');
              } else {
                debugPrint('[Attachments] Cannot open file: no handler available');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Cannot open file: $filename')),
                );
              }
            }
          } catch (e) {
            debugPrint('[Attachments] Error opening file: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error opening file: $e')),
            );
          }
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download attachment: ${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening attachment: $e')),
      );
    }
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


