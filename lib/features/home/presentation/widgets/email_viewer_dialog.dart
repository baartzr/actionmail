import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'package:domail/features/home/presentation/widgets/pdf_viewer_window.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/services/local_folders/local_folder_service.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Information about an attachment
class AttachmentInfo {
  final String filename;
  final String mimeType;
  final String attachmentId;
  final int? size;

  AttachmentInfo({
    required this.filename,
    required this.mimeType,
    required this.attachmentId,
    this.size,
  });
}

class _InlineImageData {
  final String mimeType;
  final String base64Data;

  const _InlineImageData({
    required this.mimeType,
    required this.base64Data,
  });
}

class _InlineImagePart {
  final String cid;
  final String mimeType;
  final String? attachmentId;
  final String? inlineData;

  const _InlineImagePart({
    required this.cid,
    required this.mimeType,
    this.attachmentId,
    this.inlineData,
  });
}

class _InlineImageLoadResult {
  final Map<String, _InlineImageData> images;
  final Set<String> consumedAttachmentIds;

  const _InlineImageLoadResult({
    required this.images,
    required this.consumedAttachmentIds,
  });
}

enum _ReplyMenuAction { reply, replyAll, forward }

/// Dialog for viewing email content in a webview
class EmailViewerDialog extends StatefulWidget {
  final MessageIndex message;
  final String accountId;
  final VoidCallback? onMarkRead;
  final String? localFolderName; // If provided, load from local folder instead of Gmail

  const EmailViewerDialog({
    super.key,
    required this.message,
    required this.accountId,
    this.onMarkRead,
    this.localFolderName,
  });

  @override
  State<EmailViewerDialog> createState() => _EmailViewerDialogState();
}

class _EmailViewerDialogState extends State<EmailViewerDialog> {
  // ignore: unused_field
  InAppWebViewController? _webViewController;
  late MessageIndex _currentMessage;
  String? _accountEmail;
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;
  bool _canGoBack = false;
  bool _showNavigationExtras = false;
  bool _isViewingOriginal = true;
  bool _isConversationMode = false;
  bool _isThreadLoading = false;
  String? _threadError;
  Uri? _currentUrl;
  List<MessageIndex> _threadMessages = [];
  List<AttachmentInfo> _attachments = [];
  final Map<String, List<AttachmentInfo>> _conversationAttachments = {};
  final Set<String> _loadingConversationAttachmentIds = {};
  final Set<String> _tempFilePaths = {};
  final Map<String, String> _attachmentFileCache = {};
  ComposeDraftState? _pendingComposeDraft;
  ComposeEmailMode? _pendingComposeMode;

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.message;
    _loadAccountEmail();
    _loadEmailBody();
    // Mark as read when dialog opens
    if (!_currentMessage.isRead && widget.onMarkRead != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onMarkRead!();
      });
    }
  }

  @override
  void dispose() {
    for (final path in _tempFilePaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // ignore cleanup errors
      }
    }
    _tempFilePaths.clear();
    super.dispose();
  }

  Future<void> _loadAccountEmail() async {
    final account = await GoogleAuthService().getAccountById(widget.accountId);
    if (!mounted) return;
    setState(() {
      _accountEmail = account?.email.toLowerCase();
    });
  }

  Future<void> _loadEmailBody() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      } else {
      }

      // If viewing from local folder, load from saved file
      if (widget.localFolderName != null) {
        final folderService = LocalFolderService();
        final body = await folderService.loadEmailBody(widget.localFolderName!, _currentMessage.id);
        if (!mounted) return;
        if (body != null) {
          debugPrint('[EmailViewer] Email body loaded from local folder, loading attachments...');
          debugPrint('[EmailViewer] Message hasAttachments flag: ${_currentMessage.hasAttachments}');
          
          // Load attachments from local folder
          final localAttachments = await folderService.loadAttachments(widget.localFolderName!, _currentMessage.id);
          debugPrint('[EmailViewer] loadAttachments returned ${localAttachments.length} attachments');
          
          final inlineResult = await _buildInlineImagesFromLocal(body, localAttachments);
          final filteredLocalAttachments = localAttachments
              .where((raw) {
                final attachmentId = raw['attachmentId'] as String?;
                if (attachmentId == null) return false;
                return !inlineResult.consumedAttachmentIds.contains(attachmentId);
              })
              .toList();
          final attachments = _mapLocalAttachments(filteredLocalAttachments);
          
          debugPrint('[EmailViewer] Created ${attachments.length} AttachmentInfo objects');
          
          setState(() {
            _htmlContent = inlineResult.images.isNotEmpty ? _embedInlineImages(body, inlineResult.images) : body;
            _attachments = attachments;
            _isLoading = false;
            _conversationAttachments[_currentMessage.id] = attachments;
          });
          final controller = _webViewController;
          if (controller != null) {
            unawaited(_loadHtmlIntoWebView(controller));
          }
          debugPrint('[EmailViewer] Loaded from local folder - found ${attachments.length} attachments, setState called');
          return;
        } else {
          setState(() {
            _error = 'Email body not found in local folder';
            _isLoading = false;
          });
          return;
        }
      }
      
      // Otherwise load from Gmail API
      debugPrint('[EmailViewer] Starting to load email ${_currentMessage.id} from Gmail API');
      final account = await GoogleAuthService().ensureValidAccessToken(widget.accountId);
      final accessToken = account?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('[EmailViewer] ERROR: No access token available');
        if (!mounted) return;
        setState(() {
          _error = 'No access token available';
          _isLoading = false;
        });
        return;
      }

      debugPrint('[EmailViewer] Fetching message from Gmail API...');
      final resp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/${_currentMessage.id}?format=full'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      
      debugPrint('[EmailViewer] Gmail API response status: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _error = 'Failed to load email: ${resp.statusCode}';
          _isLoading = false;
        });
        return;
      }

      debugPrint('[EmailViewer] Parsing response...');
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final payload = map['payload'] as Map<String, dynamic>?;
      debugPrint('[EmailViewer] Payload found: ${payload != null}');
      
      String? htmlBody;
      String? plainBody;

      // Walk through the payload structure to find HTML and plain text parts
      void extractBody(dynamic part) {
        if (part is! Map<String, dynamic>) return;
        
        final mimeType = (part['mimeType'] as String? ?? '').toLowerCase();
        final body = part['body'] as Map<String, dynamic>?;
        final data = body?['data'] as String?;
        
        if (data != null) {
          try {
            final decoded = utf8.decode(
              base64Url.decode(data.replaceAll('-', '+').replaceAll('_', '/')),
            );
            if (mimeType.contains('text/html')) {
              htmlBody = decoded;
            } else if (mimeType.contains('text/plain')) {
              plainBody = decoded;
            }
          } catch (e) {
            // Continue to next part
          }
        }
        
        // Recursively check nested parts
        final parts = part['parts'] as List<dynamic>?;
        if (parts != null) {
          for (final p in parts) {
            extractBody(p);
          }
        }
      }

      extractBody(payload ?? {});
      debugPrint('[EmailViewer] Body extracted, starting attachment extraction...');
      
      // Extract real attachments from payload
      var attachments = _extractAttachmentsFromPayload(payload);

      // Prefer HTML over plain text
      final bodyContent = htmlBody ?? plainBody ?? _currentMessage.snippet ?? 'No content available';
      var bodyHtml = htmlBody != null
          ? bodyContent
          : '<pre style="white-space: pre-wrap; font-family: inherit;">${_escapeHtml(bodyContent)}</pre>';

      if (htmlBody != null && payload != null) {
        final inlineResult = await _loadInlineImages(payload, _currentMessage.id, accessToken);
        if (inlineResult.images.isNotEmpty) {
          bodyHtml = _embedInlineImages(bodyHtml, inlineResult.images);
        }
        if (inlineResult.consumedAttachmentIds.isNotEmpty) {
          attachments = attachments
              .where((attachment) => !inlineResult.consumedAttachmentIds.contains(attachment.attachmentId))
              .toList();
        }
      }

      // Create a complete HTML document with proper styling
      final fullHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      margin: 0;
      padding: 16px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      color: #1a1a1a;
      background-color: #ffffff;
    }
    .email-header {
      border-bottom: 1px solid #e0e0e0;
      padding-bottom: 16px;
      margin-bottom: 16px;
    }
    .email-header h2 {
      margin: 0 0 8px 0;
      font-size: 20px;
      font-weight: 600;
    }
    .email-header .meta {
      color: #666;
      font-size: 12px;
    }
    .email-body {
      max-width: 100%;
      overflow-wrap: break-word;
    }
    .email-body img {
      max-width: 100%;
      height: auto;
    }
    @media (prefers-color-scheme: dark) {
      body {
        background-color: #1a1a1a;
        color: #e0e0e0;
      }
      .email-header {
        border-bottom-color: #333;
      }
      .email-header .meta {
        color: #999;
      }
    }
  </style>
</head>
<body>
  <div class="email-header">
    <h2>${_escapeHtml(_currentMessage.subject)}</h2>
    <div class="meta">
      <div><strong>From:</strong> ${_escapeHtml(_currentMessage.from)}</div>
      <div><strong>To:</strong> ${_escapeHtml(_currentMessage.to)}</div>
      <div><strong>Date:</strong> ${_formatDate(_currentMessage.internalDate)}</div>
    </div>
  </div>
  <div class="email-body">
    $bodyHtml
  </div>
</body>
</html>
      ''';

      if (!mounted) return;
      setState(() {
        _htmlContent = fullHtml;
        _attachments = attachments;
        _isLoading = false;
        _conversationAttachments[_currentMessage.id] = attachments;
      });
      final controller = _webViewController;
      if (controller != null) {
        unawaited(_loadHtmlIntoWebView(controller));
      }
      
      // Debug: Print attachment count
      debugPrint('[EmailViewer] Attachment extraction complete for message ${_currentMessage.id}');
      debugPrint('[EmailViewer]   hasAttachments flag: ${_currentMessage.hasAttachments}');
      debugPrint('[EmailViewer]   Found ${attachments.length} real attachments');
      if (attachments.isNotEmpty) {
        for (final att in attachments) {
          debugPrint('[EmailViewer]     - ${att.filename} (${att.mimeType}, ${att.size ?? 0} bytes, attachmentId: ${att.attachmentId})');
        }
      } else if (_currentMessage.hasAttachments) {
        debugPrint('[EmailViewer]   WARNING: Message has hasAttachments=true but no real attachments found!');
      }
    } catch (e, stackTrace) {
      debugPrint('[EmailViewer] ERROR loading email: $e');
      debugPrint('[EmailViewer] Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'Error loading email: $e';
        _isLoading = false;
      });
    }
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _extractEmail(String from) {
    final regex = RegExp(r'<([^>]+)>');
    final match = regex.firstMatch(from);
    if (match != null) return match.group(1)!.trim();
    if (from.contains('@')) return from.trim();
    return '';
  }

  String _extractSenderName(String from) {
    final regex = RegExp(r'<([^>]+)>');
    final match = regex.firstMatch(from);
    if (match != null) {
      final cleaned = from.replaceAll(match.group(0)!, '').trim();
      if (cleaned.isNotEmpty) {
        return cleaned.replaceAll('"', '');
      }
    }
    final email = _extractEmail(from);
    return email.isNotEmpty ? email : from;
  }

  Future<void> _openCompose({
    required ComposeEmailMode mode,
    String? to,
    String? subject,
    ComposeDraftState? draft,
  }) async {
    final result = await showDialog<ComposeDialogResult>(
      context: context,
      builder: (ctx) => ComposeEmailDialog(
        to: draft?.to ?? to,
        subject: draft?.subject ?? subject,
        accountId: widget.accountId,
        originalMessage: _currentMessage,
        mode: mode,
        initialDraft: draft,
      ),
    );

    if (!mounted || result == null) return;

    switch (result.type) {
      case ComposeDialogResultType.viewOriginal:
        if (result.draft != null) {
          setState(() {
            _pendingComposeDraft = result.draft;
            _pendingComposeMode = mode;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                mode == ComposeEmailMode.forward
                    ? 'Forward draft saved. Tap the edit icon to continue.'
                    : 'Reply draft saved. Tap the edit icon to continue.',
              ),
            ),
          );
        }
        break;
      case ComposeDialogResultType.sent:
        setState(() {
          _pendingComposeDraft = null;
          _pendingComposeMode = null;
        });
        break;
      case ComposeDialogResultType.cancelled:
        break;
    }
  }

  Future<void> _resumePendingCompose() async {
    final draft = _pendingComposeDraft;
    final mode = _pendingComposeMode;
    if (draft == null || mode == null) return;
    await _openCompose(mode: mode, draft: draft);
  }

  Widget _buildAttachmentChip(AttachmentInfo attachment) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) => _showAttachmentContextMenu(
          details.globalPosition,
          attachment,
        ),
        onLongPress: () async {
          if (Platform.isAndroid || Platform.isIOS) {
            await _showAttachmentActionSheet(attachment);
          }
        },
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openAttachment(attachment),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      attachment.filename,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<AttachmentInfo> _mapLocalAttachments(List<Map<String, dynamic>> localAttachments) {
    return localAttachments
        .map((raw) {
          final attachmentId = raw['attachmentId'] as String?;
          if (attachmentId == null || attachmentId.isEmpty) {
            return null;
          }
          return AttachmentInfo(
            filename: raw['filename'] as String? ?? 'attachment',
            mimeType: raw['mimeType'] as String? ?? 'application/octet-stream',
            attachmentId: attachmentId,
            size: raw['size'] as int?,
          );
        })
        .whereType<AttachmentInfo>()
        .toList();
  }

  Future<_InlineImageLoadResult> _buildInlineImagesFromLocal(String html, List<Map<String, dynamic>> localAttachments) async {
    final inlineImages = <String, _InlineImageData>{};
    final consumedAttachmentIds = <String>{};

    const cidPattern = r'''cid:([^"'\s>]+)''';
    final cidRegex = RegExp(cidPattern, caseSensitive: false);
    final cidsInHtml = cidRegex
        .allMatches(html)
        .map((match) => _normalizeContentId(match.group(1) ?? ''))
        .where((cid) => cid.isNotEmpty)
        .toSet();

    Future<void> embedFromRaw(Map<String, dynamic> raw, String cid) async {
      final attachmentId = raw['attachmentId'] as String? ?? '';
      if (attachmentId.isEmpty) return;

      final localPath = raw['localPath'] as String? ?? '';
      if (localPath.isEmpty) return;

      try {
        final file = File(localPath);
        if (!await file.exists()) return;

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return;

        final mimeType = (raw['mimeType'] as String? ?? 'application/octet-stream').toLowerCase();
        inlineImages[cid] = _InlineImageData(
          mimeType: mimeType,
          base64Data: base64Encode(bytes),
        );
        consumedAttachmentIds.add(attachmentId);
      } catch (e) {
        debugPrint('[EmailViewer] Failed to load inline image from $localPath: $e');
      }
    }

    // Pass 1: use explicit inline markers
    for (final raw in localAttachments) {
      final isInline = raw['isInline'] as bool? ?? false;
      if (!isInline) continue;

      final contentId = _normalizeContentId(raw['contentId'] as String? ?? '');
      if (contentId.isEmpty) continue;

      await embedFromRaw(raw, contentId);
    }

    // Pass 2: use contentId match even if not marked inline
    if (inlineImages.length < cidsInHtml.length) {
      for (final raw in localAttachments) {
        final attachmentId = raw['attachmentId'] as String? ?? '';
        if (attachmentId.isEmpty || consumedAttachmentIds.contains(attachmentId)) continue;

        final contentId = _normalizeContentId(raw['contentId'] as String? ?? '');
        if (contentId.isEmpty || inlineImages.containsKey(contentId) || !cidsInHtml.contains(contentId)) continue;

        await embedFromRaw(raw, contentId);
      }
    }

    // Pass 3: heuristics based on order for remaining CIDs
    if (inlineImages.length < cidsInHtml.length) {
      final remainingCids = cidsInHtml.where((cid) => !inlineImages.containsKey(cid)).toList();
      final candidateAttachments = localAttachments.where((raw) {
        final attachmentId = raw['attachmentId'] as String? ?? '';
        if (attachmentId.isEmpty || consumedAttachmentIds.contains(attachmentId)) return false;
        final mimeType = (raw['mimeType'] as String? ?? '').toLowerCase();
        return mimeType.startsWith('image/');
      }).toList();

      for (var i = 0; i < remainingCids.length && i < candidateAttachments.length; i++) {
        await embedFromRaw(candidateAttachments[i], remainingCids[i]);
      }
    }

    return _InlineImageLoadResult(
      images: inlineImages,
      consumedAttachmentIds: consumedAttachmentIds,
    );
  }

  List<AttachmentInfo> _extractAttachmentsFromPayload(Map<String, dynamic>? payload) {
    final attachments = <AttachmentInfo>[];

    void walk(dynamic part) {
      if (part is! Map<String, dynamic>) return;

      final rawMimeType = (part['mimeType'] as String? ?? '').toLowerCase();
      final mimeType = rawMimeType.split(';').first.trim();
      var filename = part['filename'] as String?;
      final body = part['body'] as Map<String, dynamic>?;
      final attachmentId = body?['attachmentId'] as String?;
      final size = body?['size'] as int?;
      final headers = (part['headers'] as List<dynamic>?) ?? [];

      final parts = part['parts'] as List<dynamic>?;

      if (attachmentId == null || attachmentId.isEmpty) {
        if (parts != null) {
          for (final p in parts) {
            walk(p);
          }
        }
        return;
      }

      final headerMap = <String, String>{};
      for (final h in headers) {
        if (h is Map<String, dynamic>) {
          final name = (h['name'] as String? ?? '').toLowerCase();
          final value = h['value'] as String? ?? '';
          if (name.isNotEmpty) {
            headerMap[name] = value;
          }
        }
      }

      final disp = headerMap['content-disposition'] ?? '';
      final cid = headerMap['content-id'] ?? '';
      final dispLower = disp.toLowerCase();

      if (dispLower.contains('inline') && !dispLower.contains('attachment')) {
        if (parts != null) {
          for (final p in parts) {
            walk(p);
          }
        }
        return;
      }

      if (cid.isNotEmpty) {
        if (parts != null) {
          for (final p in parts) {
            walk(p);
          }
        }
        return;
      }

      if (mimeType.startsWith('image/') && !dispLower.contains('attachment')) {
        if (parts != null) {
          for (final p in parts) {
            walk(p);
          }
        }
        return;
      }

      if (filename == null || filename.isEmpty) {
        final matchFilename = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disp);
        if (matchFilename != null) {
          filename = matchFilename.group(1)?.trim();
        } else {
          final contentType = headerMap['content-type'] ?? '';
          final matchName = RegExp(r'name="?([^";]+)"?', caseSensitive: false).firstMatch(contentType);
          if (matchName != null) {
            filename = matchName.group(1)?.trim();
          }
        }
      }

      if (filename == null || filename.isEmpty) {
        if (parts != null) {
          for (final p in parts) {
            walk(p);
          }
        }
        return;
      }

      attachments.add(AttachmentInfo(
        filename: filename,
        mimeType: mimeType,
        attachmentId: attachmentId,
        size: size,
      ));

      if (parts != null) {
        for (final p in parts) {
          walk(p);
        }
      }
    }

    walk(payload ?? {});
    return attachments;
  }

  List<_InlineImagePart> _collectInlineImageParts(Map<String, dynamic> payload) {
    final inlineParts = <_InlineImagePart>[];

    void collect(dynamic part) {
      if (part is! Map<String, dynamic>) {
        return;
      }

      final rawMimeType = (part['mimeType'] as String? ?? '');
      final mimeType = rawMimeType.toLowerCase().split(';').first.trim();
      final body = part['body'] as Map<String, dynamic>?;
      final attachmentId = body?['attachmentId'] as String?;
      final inlineData = body?['data'] as String?;
      final headers = (part['headers'] as List<dynamic>?) ?? const [];

      String cid = '';
      String disposition = '';

      for (final header in headers) {
        if (header is Map<String, dynamic>) {
          final name = (header['name'] as String? ?? '').toLowerCase();
          final value = header['value'] as String? ?? '';
          if (name == 'content-id') {
            cid = value;
          } else if (name == 'content-disposition') {
            disposition = value;
          }
        }
      }

      final hasInlinePayload = (attachmentId != null && attachmentId.isNotEmpty) || (inlineData != null && inlineData.isNotEmpty);
      final isInlineImage = mimeType.startsWith('image/') && (cid.isNotEmpty || disposition.toLowerCase().contains('inline'));

      if (isInlineImage && cid.isNotEmpty && hasInlinePayload) {
        inlineParts.add(
          _InlineImagePart(
            cid: cid,
            mimeType: mimeType.isNotEmpty ? mimeType : rawMimeType.toLowerCase(),
            attachmentId: attachmentId,
            inlineData: inlineData,
          ),
        );
      }

      final parts = part['parts'] as List<dynamic>?;
      if (parts != null) {
        for (final child in parts) {
          collect(child);
        }
      }
    }

    collect(payload);
    return inlineParts;
  }

  Future<_InlineImageLoadResult> _loadInlineImages(
    Map<String, dynamic> payload,
    String messageId,
    String accessToken,
  ) async {
    final inlineParts = _collectInlineImageParts(payload);

    if (inlineParts.isEmpty) {
      debugPrint('[EmailViewer] No inline image parts detected for message $messageId');
      return const _InlineImageLoadResult(images: {}, consumedAttachmentIds: {});
    }

    final inlineImages = <String, _InlineImageData>{};
    final consumedAttachmentIds = <String>{};
    debugPrint('[EmailViewer] Found ${inlineParts.length} potential inline image parts for message $messageId');

    for (final part in inlineParts) {
      final cid = _normalizeContentId(part.cid);
      if (cid.isEmpty) {
        continue;
      }

      List<int>? bytes;
      if (part.inlineData != null && part.inlineData!.isNotEmpty) {
        try {
          final normalized = part.inlineData!.replaceAll('-', '+').replaceAll('_', '/');
          bytes = base64Decode(normalized);
        } catch (e) {
          debugPrint('[EmailViewer] Failed to decode inline image data for cid=$cid: $e');
        }
      }

      if ((bytes == null || bytes.isEmpty) && part.attachmentId != null && part.attachmentId!.isNotEmpty) {
        bytes = await _downloadAttachmentBytes(messageId, part.attachmentId!, accessToken);
      }

      if (bytes == null || bytes.isEmpty) {
        debugPrint('[EmailViewer] Inline image cid=$cid missing data');
        continue;
      }

      final embedMimeType = part.mimeType.isNotEmpty ? part.mimeType : 'application/octet-stream';
      inlineImages[cid] = _InlineImageData(
        mimeType: embedMimeType,
        base64Data: base64Encode(bytes),
      );
      final attachmentId = part.attachmentId;
      if (attachmentId != null && attachmentId.isNotEmpty) {
        consumedAttachmentIds.add(attachmentId);
      }
      debugPrint('[EmailViewer] Inline image cid=$cid prepared (${part.mimeType}, bytes=${bytes.length})');
    }

    return _InlineImageLoadResult(
      images: inlineImages,
      consumedAttachmentIds: consumedAttachmentIds,
    );
  }

  String _normalizeContentId(String cid) {
    var normalized = cid.trim();
    if (normalized.startsWith('<') && normalized.endsWith('>')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized;
  }

  String _embedInlineImages(String html, Map<String, _InlineImageData> inlineImages) {
    var processed = html;
    inlineImages.forEach((cid, image) {
      final pattern = RegExp('cid:${RegExp.escape(cid)}', caseSensitive: false);
      processed = processed.replaceAll(
        pattern,
        'data:${image.mimeType};base64,${image.base64Data}',
      );
    });
    return processed;
  }

  Future<void> _loadHtmlIntoWebView(InAppWebViewController controller) async {
    final html = _htmlContent;
    if (html == null) {
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      final htmlBytes = utf8.encode(html);
      const navigateToStringLimit = 1500000; // keep well under WebView2 NavigateToString limit
      final containsDataUri = html.contains('data:');
      if (htmlBytes.length > navigateToStringLimit || containsDataUri) {
        final filePath = await _createTempHtmlFile(htmlBytes);
        if (filePath != null) {
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri.uri(Uri.file(filePath))),
          );
          return;
        }
      }
    }

    await controller.loadData(
      data: html,
      mimeType: 'text/html',
      encoding: 'utf8',
    );
  }

  Future<String?> _createTempHtmlFile(List<int> htmlBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final htmlDir = Directory(path.join(tempDir.path, 'domail_email_html'));
      if (!await htmlDir.exists()) {
        await htmlDir.create(recursive: true);
      }

      final fileName = 'email_${_currentMessage.id}_${DateTime.now().millisecondsSinceEpoch}.html';
      final filePath = path.join(htmlDir.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(htmlBytes, flush: true);
      _tempFilePaths.add(filePath);
      debugPrint('[EmailViewer] Large HTML written to temp file for Windows WebView: $filePath (bytes=${htmlBytes.length})');
      return filePath;
    } catch (e, stackTrace) {
      debugPrint('[EmailViewer] Failed to write temp HTML file: $e');
      debugPrint(stackTrace.toString());
      return null;
    }
  }


  Future<List<int>?> _downloadAttachmentBytes(
    String messageId,
    String attachmentId,
    String accessToken,
  ) async {
    try {
      final resp = await http.get(
        Uri.parse(
          'https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId/attachments/$attachmentId',
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (resp.statusCode != 200) {
        debugPrint(
          '[EmailViewer] _downloadAttachmentBytes failed for $messageId/$attachmentId (status ${resp.statusCode})',
        );
        return null;
      }

      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = map['data'] as String?;
      if (data == null) {
        return null;
      }

      final normalized = data.replaceAll('-', '+').replaceAll('_', '/');
      return base64Decode(normalized);
    } catch (e) {
      debugPrint('[EmailViewer] _downloadAttachmentBytes error: $e');
      return null;
    }
  }

  Future<void> _loadAttachmentsForConversationMessage(MessageIndex message) async {
    if (_conversationAttachments.containsKey(message.id)) {
      return;
    }
    if (_loadingConversationAttachmentIds.contains(message.id)) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingConversationAttachmentIds.add(message.id);
      });
    } else {
      _loadingConversationAttachmentIds.add(message.id);
    }

    try {
      List<AttachmentInfo> attachments = const [];

      if (widget.localFolderName != null) {
        final folderService = LocalFolderService();
        final localAttachments = await folderService.loadAttachments(widget.localFolderName!, message.id);
        attachments = _mapLocalAttachments(localAttachments);
      } else {
        final account = await GoogleAuthService().ensureValidAccessToken(message.accountId);
        final accessToken = account?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          throw Exception('No access token available');
        }

        final resp = await http.get(
          Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );

        if (resp.statusCode != 200) {
          throw Exception('Failed to load attachments (${resp.statusCode})');
        }

        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        final payload = map['payload'] as Map<String, dynamic>?;
        attachments = _extractAttachmentsFromPayload(payload);
        if (payload != null) {
          final inlineParts = _collectInlineImageParts(payload);
          if (inlineParts.isNotEmpty) {
            final inlineIds = inlineParts
                .map((part) => part.attachmentId)
                .whereType<String>()
                .toSet();
            if (inlineIds.isNotEmpty) {
              attachments = attachments
                  .where((attachment) => !inlineIds.contains(attachment.attachmentId))
                  .toList();
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _conversationAttachments[message.id] = attachments;
      });
    } catch (e) {
      debugPrint('[EmailViewer] Failed to load conversation attachments for ${message.id}: $e');
      if (!mounted) return;
      setState(() {
        _conversationAttachments[message.id] = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingConversationAttachmentIds.remove(message.id);
        });
      } else {
        _loadingConversationAttachmentIds.remove(message.id);
      }
    }
  }

  Widget _buildConversationAttachmentChip(MessageIndex message, AttachmentInfo attachment, Color textColor) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showAttachmentContextMenu(
        details.globalPosition,
        attachment,
        sourceMessage: message,
      ),
      onLongPress: () async {
        if (Platform.isAndroid || Platform.isIOS) {
          await _showAttachmentActionSheet(
            attachment,
            sourceMessage: message,
          );
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openAttachment(attachment, sourceMessage: message),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: textColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.attach_file,
                  size: 18,
                  color: textColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    attachment.filename,
                    style: theme.textTheme.bodySmall?.copyWith(color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachment(AttachmentInfo attachment, {MessageIndex? sourceMessage}) async {
    final message = sourceMessage ?? _currentMessage;
    try {
      final file = await _ensureAttachmentFile(attachment, message);
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open ${attachment.filename}')),
        );
        return;
      }

      final extension = path.extension(file.path).toLowerCase();
      if (extension == '.pdf') {
        if (!mounted) return;
        await PdfViewerWindow.open(
          context,
          filePath: file.path,
        );
        return;
      }

      final result = await OpenFile.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open file: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening attachment: $e')),
      );
    }
  }

  Future<void> _applyScrollEnhancements(InAppWebViewController controller) async {
    const script = '''
(function() {
  if (window.__domailScrollPatchApplied) {
    return;
  }
  window.__domailScrollPatchApplied = true;

  const LINE_HEIGHT = 35;
  const PAGE_HEIGHT = 560;

  function normalizeDelta(delta, mode) {
    switch (mode) {
      case 1: return delta * LINE_HEIGHT; // DOM_DELTA_LINE
      case 2: return delta * PAGE_HEIGHT; // DOM_DELTA_PAGE
      default: return delta; // pixel
    }
  }

  function clamp(value) {
    if (Math.abs(value) < 1) {
      return value < 0 ? -1 : 1;
    }
    return value;
  }

  window.addEventListener('wheel', function(event) {
    if (event.ctrlKey) {
      return;
    }

    const rawVertical = normalizeDelta(event.deltaY, event.deltaMode);
    const rawHorizontal = normalizeDelta(event.deltaX, event.deltaMode);

    // Comment out noisy debug logs after validation.
    // if (window.console && console.debug) {
    //   console.debug('[EmailViewer][wheel]', JSON.stringify({
    //     dx: event.deltaX,
    //     dy: event.deltaY,
    //     mode: event.deltaMode,
    //     resolvedVertical: Math.abs(rawVertical) >= Math.abs(rawHorizontal) ? rawVertical : rawHorizontal,
    //   }));
    // }

    const dominant = Math.abs(rawVertical) >= Math.abs(rawHorizontal)
      ? rawVertical
      : rawHorizontal;

    const shouldReRouteHorizontally = Math.abs(rawHorizontal) > Math.abs(rawVertical) ||
      (!event.shiftKey && rawHorizontal !== 0);

    if (shouldReRouteHorizontally) {
      event.preventDefault();
      const scaled = clamp(dominant);
      window.scrollBy({
        top: scaled,
        left: 0,
        behavior: 'auto',
      });
      return;
    }

    // Allow native vertical handling when vertical is dominant.
  }, { passive: false });
})();
''';

    await controller.evaluateJavascript(source: script);
  }

  void _logPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      debugPrint(
        '[PointerScroll] dx=${event.scrollDelta.dx}, dy=${event.scrollDelta.dy}, kind=${event.kind}',
      );
    }
  }

  Future<File?> _ensureAttachmentFile(AttachmentInfo attachment, MessageIndex message) async {
    final cacheKey = '${message.id}:${attachment.attachmentId}';
    final cachedPath = _attachmentFileCache[cacheKey];
    if (cachedPath != null) {
      final cachedFile = File(cachedPath);
      if (await cachedFile.exists()) {
        return cachedFile;
      }
      _attachmentFileCache.remove(cacheKey);
    }

    if (widget.localFolderName != null) {
      final folderService = LocalFolderService();
      final localPath = await folderService.getAttachmentPath(
        widget.localFolderName!,
        message.id,
        attachment.attachmentId,
      );
      if (localPath != null) {
        final localFile = File(localPath);
        if (await localFile.exists()) {
          _attachmentFileCache[cacheKey] = localFile.path;
          return localFile;
        }
      }
      return null;
    }

    final account = await GoogleAuthService().ensureValidAccessToken(widget.accountId);
    final accessToken = account?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No access token available')),
      );
      return null;
    }

    final bytes = await _downloadAttachmentBytes(
      message.id,
      attachment.attachmentId,
      accessToken,
    );
    if (bytes == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to download ${attachment.filename}')),
      );
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final downloadDir = Directory(path.join(tempDir.path, 'domail_attachments', message.id));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final sanitizedName = _sanitizeFilename(attachment.filename);
    final filePath = path.join(downloadDir.path, sanitizedName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    _attachmentFileCache[cacheKey] = file.path;
    _tempFilePaths.add(file.path);
    return file;
  }

  Future<void> _saveAttachment(AttachmentInfo attachment, {MessageIndex? sourceMessage}) async {
    final message = sourceMessage ?? _currentMessage;
    try {
      final file = await _ensureAttachmentFile(attachment, message);
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save ${attachment.filename}')),
        );
        return;
      }

      String? targetPath;
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        targetPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save attachment',
          fileName: attachment.filename,
        );
      }
      if (targetPath == null || targetPath.isEmpty) {
        final downloads = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        targetPath = path.join(downloads.path, attachment.filename);
      }

      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      await file.copy(targetPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${path.basename(targetPath)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving attachment: $e')),
      );
    }
  }

  Future<void> _showAttachmentContextMenu(
    Offset globalPosition,
    AttachmentInfo attachment, {
    MessageIndex? sourceMessage,
  }) async {
    final overlayState = Overlay.of(context);
    final overlayRenderBox = overlayState.context.findRenderObject() as RenderBox?;
    final size = overlayRenderBox?.size ?? MediaQuery.of(context).size;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        size.width - globalPosition.dx,
        size.height - globalPosition.dy,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.open_in_new),
            title: Text('Open'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'save',
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('Save as…'),
          ),
        ),
      ],
    );

    if (selected == 'open') {
      await _openAttachment(attachment, sourceMessage: sourceMessage);
    } else if (selected == 'save') {
      await _saveAttachment(attachment, sourceMessage: sourceMessage);
    }
  }

  Future<void> _showAttachmentActionSheet(
    AttachmentInfo attachment, {
    MessageIndex? sourceMessage,
  }) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () => Navigator.of(ctx).pop('open'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Save as…'),
              onTap: () => Navigator.of(ctx).pop('save'),
            ),
          ],
        ),
      ),
    );

    if (result == 'open') {
      await _openAttachment(attachment, sourceMessage: sourceMessage);
    } else if (result == 'save') {
      await _saveAttachment(attachment, sourceMessage: sourceMessage);
    }
  }

  String _sanitizeFilename(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'attachment' : sanitized;
  }

  void _handleReply() {
    final to = _extractEmail(_currentMessage.from);
    final subject = _currentMessage.subject.startsWith('Re:') 
        ? _currentMessage.subject 
        : 'Re: ${_currentMessage.subject}';
    setState(() {
      _pendingComposeDraft = null;
      _pendingComposeMode = null;
    });
    _openCompose(
      mode: ComposeEmailMode.reply,
      to: to,
      subject: subject,
    );
  }

  void _handleReplyAll() {
    final to = _extractEmail(_currentMessage.from);
    // TODO: Extract all recipients from the email
    final subject = _currentMessage.subject.startsWith('Re:') 
        ? _currentMessage.subject 
        : 'Re: ${_currentMessage.subject}';
    setState(() {
      _pendingComposeDraft = null;
      _pendingComposeMode = null;
    });
    _openCompose(
      mode: ComposeEmailMode.replyAll,
      to: to,
      subject: subject,
    );
  }

  void _handleForward() {
    final subject = _currentMessage.subject.startsWith('Fwd:') 
        ? _currentMessage.subject 
        : 'Fwd: ${_currentMessage.subject}';
    setState(() {
      _pendingComposeDraft = null;
      _pendingComposeMode = null;
    });
    _openCompose(
      mode: ComposeEmailMode.forward,
      subject: subject,
    );
  }

  void _toggleConversationMode() {
    if (_isConversationMode) {
      setState(() {
        _isConversationMode = false;
      });
      _updateNavigationState();
      return;
    }

    setState(() {
      _isConversationMode = true;
      _threadMessages = [_currentMessage];
      _isThreadLoading = true;
      _threadError = null;
      _showNavigationExtras = false;
      _canGoBack = false;
    });

    unawaited(_loadThreadMessages());
  }

  Future<void> _loadThreadMessages() async {
    final threadId = _currentMessage.threadId;
    if (threadId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _threadMessages = [_currentMessage];
        _isThreadLoading = false;
        _threadError = 'No conversation history available for this email.';
      });
      return;
    }

    try {
      final repo = MessageRepository();
      final messages = await repo.getMessagesByThread(widget.accountId, threadId);
      if (!mounted) return;
      setState(() {
        _threadMessages = messages.isEmpty ? [_currentMessage] : messages;
        _isThreadLoading = false;
        _threadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _threadMessages = [_currentMessage];
        _isThreadLoading = false;
        _threadError = 'Failed to load conversation: $e';
      });
    }
  }

  bool _isOutgoing(MessageIndex message) {
    final accountEmail = _accountEmail;
    if (accountEmail == null || accountEmail.isEmpty) {
      return false;
    }
    final senderEmail = _extractEmail(message.from).toLowerCase();
    return senderEmail == accountEmail;
  }

  Widget _buildConversationList() {
    if (_isThreadLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_threadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            _threadError!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final messages = _threadMessages.isEmpty ? <MessageIndex>[_currentMessage] : _threadMessages;
    final showConversationHint = messages.length <= 1;
    final itemCount = showConversationHint ? messages.length + 1 : messages.length;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth <= 600 ? constraints.maxWidth * 0.8 : 520.0;
        final minWidth = constraints.maxWidth <= 600 ? constraints.maxWidth * 0.6 : maxWidth * 0.6;
        final resolvedMinWidth = minWidth > maxWidth ? maxWidth : minWidth;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (showConversationHint && index == itemCount - 1) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    'No additional messages in this conversation yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }

            final message = messages[index];
            final isOutgoing = _isOutgoing(message);
            final alignment = isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start;
            final bubbleColor = isOutgoing
                ? ActionMailTheme.sentMessageColor
                : ActionMailTheme.incomingMessageColor;
            final textColor = theme.colorScheme.onPrimary;
            final metaColor = textColor.withValues(alpha: 0.8);
            final isActive = message.id == _currentMessage.id;

            final senderEmail = _extractEmail(message.from);
            final senderName = _extractSenderName(message.from);
            final attachments = _conversationAttachments[message.id];
            final isLoadingAttachments = _loadingConversationAttachmentIds.contains(message.id);

            if ((message.hasAttachments || (attachments != null && attachments.isNotEmpty)) && attachments == null && !isLoadingAttachments) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _loadAttachmentsForConversationMessage(message);
              });
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: alignment,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      minWidth: resolvedMinWidth,
                    ),
                    child: Material(
                      color: bubbleColor,
                      elevation: isActive ? 2 : 0,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showMessageFromThread(message),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$senderName <$senderEmail>',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(message.internalDate),
                                style: theme.textTheme.labelSmall?.copyWith(color: metaColor),
                              ),
                              if (message.to.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'To: ${message.to}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: metaColor),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                message.subject,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (message.snippet != null && message.snippet!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  message.snippet!,
                                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                                ),
                              ],
                              if ((attachments != null && attachments.isNotEmpty) || isLoadingAttachments) ...[
                                const SizedBox(height: 12),
                                if (attachments != null && attachments.isNotEmpty)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: attachments
                                        .map((attachment) => _buildConversationAttachmentChip(message, attachment, textColor))
                                        .toList(),
                                  )
                                else if (isLoadingAttachments)
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMessageFromThread(MessageIndex message) async {
    if (message.id == _currentMessage.id) {
      setState(() {
        _isConversationMode = false;
      });
      _updateNavigationState();
      return;
    }

    setState(() {
      _currentMessage = message;
      _isConversationMode = false;
      _htmlContent = null;
      _attachments = [];
      _error = null;
      _isLoading = true;
      _isViewingOriginal = true;
      _showNavigationExtras = false;
      _canGoBack = false;
      _currentUrl = null;
    });

    await _loadEmailBody();
  }

  Future<void> _openCurrentInBrowser() async {
    final url = _currentUrl;
    if (url == null) {
      return;
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open in browser: ${url.toString()}')),
      );
    }
  }

  Future<void> _updateNavigationState() async {
    final controller = _webViewController;
    if (controller == null) {
      if (_canGoBack || _showNavigationExtras) {
        setState(() {
          _canGoBack = false;
          _showNavigationExtras = false;
        });
      }
      return;
    }

    final canGoBack = await controller.canGoBack();
    final shouldShowExtras = !_isViewingOriginal;
    final nextCanGoBack = shouldShowExtras && canGoBack;
    if (mounted && (nextCanGoBack != _canGoBack || shouldShowExtras != _showNavigationExtras)) {
      setState(() {
        _canGoBack = nextCanGoBack;
        _showNavigationExtras = shouldShowExtras;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): DoNothingIntent(),
      },
      child: AppWindowDialog(
        title: 'Email',
        fullscreen: false,
        windowId: 'emailWindow',
        headerActions: [
          if (!_isConversationMode && _showNavigationExtras && _canGoBack)
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, size: 20),
          color: theme.appBarTheme.foregroundColor,
              onPressed: () async {
                if (_webViewController != null && await _webViewController!.canGoBack()) {
                  await _webViewController!.goBack();
                  await _updateNavigationState();
                }
              },
            ),
          if (!_isConversationMode && _showNavigationExtras)
            IconButton(
              tooltip: 'Original Email',
              icon: const Icon(Icons.home, size: 20),
          color: theme.appBarTheme.foregroundColor,
              onPressed: () async {
                if (_webViewController != null && _htmlContent != null) {
                  if (mounted) {
                    setState(() {
                      _isViewingOriginal = true;
                      _currentUrl = null;
                    });
                  }
                  await _loadHtmlIntoWebView(_webViewController!);
                  await _updateNavigationState();
                }
              },
            ),
          if (!_isConversationMode && _showNavigationExtras && _currentUrl != null)
            IconButton(
              tooltip: 'Open in Browser',
              icon: const Icon(Icons.open_in_new, size: 20),
          color: theme.appBarTheme.foregroundColor,
              onPressed: _openCurrentInBrowser,
            ),
          if (_currentMessage.threadId.isNotEmpty)
            IconButton(
              tooltip: _isConversationMode ? 'Exit Conversation Mode' : 'Conversation Mode',
              icon: Icon(
                _isConversationMode ? Icons.forum : Icons.forum_outlined,
                size: 20,
              ),
              color: _isConversationMode
                  ? theme.colorScheme.primary
                  : theme.appBarTheme.foregroundColor,
              onPressed: _toggleConversationMode,
            ),
          if (_pendingComposeDraft != null && _pendingComposeMode != null)
            IconButton(
              tooltip: _pendingComposeMode == ComposeEmailMode.forward
                  ? 'Return to forward draft'
                  : 'Return to reply draft',
              icon: const Icon(Icons.edit_note, size: 20),
              color: theme.appBarTheme.foregroundColor,
              onPressed: _resumePendingCompose,
            ),
          PopupMenuButton<_ReplyMenuAction>(
            tooltip: 'Reply options',
            icon: const Icon(Icons.reply, size: 20, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case _ReplyMenuAction.reply:
                  _handleReply();
                  break;
                case _ReplyMenuAction.replyAll:
                  _handleReplyAll();
                  break;
                case _ReplyMenuAction.forward:
                  _handleForward();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<_ReplyMenuAction>(
                value: _ReplyMenuAction.reply,
                child: Text('Reply'),
              ),
              const PopupMenuItem<_ReplyMenuAction>(
                value: _ReplyMenuAction.replyAll,
                child: Text('Reply all'),
              ),
              const PopupMenuItem<_ReplyMenuAction>(
                value: _ReplyMenuAction.forward,
                child: Text('Forward'),
              ),
            ],
        ),
        Builder(
          builder: (ctx) {
            final controller = AppWindowScope.maybeOf(ctx);
            if (controller == null) {
              return const SizedBox.shrink();
            }
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final isFullscreen = controller.isFullscreen;
                return IconButton(
                  tooltip: isFullscreen ? 'Exit Full Screen' : 'Full Screen',
                  icon: Icon(
                    isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    size: 20,
                  ),
                  color: theme.appBarTheme.foregroundColor,
                  onPressed: controller.toggleFullscreen,
                );
              },
            );
          },
        ),
      ],
      child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _error = null;
                                });
                                _loadEmailBody();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                        )
                      : _isConversationMode
                          ? Column(
                              children: [
                                Expanded(child: _buildConversationList()),
                              ],
                      )
                    : _htmlContent != null
                        ? Column(
                            children: [
                              if (_attachments.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _attachments.map((attachment) => _buildAttachmentChip(attachment)).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Listener(
                                  onPointerSignal: _logPointerSignal,
                                  behavior: HitTestBehavior.translucent,
                                  child: InAppWebView(
                                  gestureRecognizers: {
                                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                                  },
                                  initialData: InAppWebViewInitialData(
                                    data: '<html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head><body></body></html>',
                                    mimeType: 'text/html',
                                    encoding: 'utf8',
                                  ),
                                  // ignore: deprecated_member_use
                                  initialOptions: InAppWebViewGroupOptions(
                                    // ignore: deprecated_member_use
                                    crossPlatform: InAppWebViewOptions(
                                      useShouldOverrideUrlLoading: true,
                                      mediaPlaybackRequiresUserGesture: false,
                                      supportZoom: true,
                                      javaScriptEnabled: true,
                                    ),
                                    // ignore: deprecated_member_use
                                    android: AndroidInAppWebViewOptions(
                                      useHybridComposition: true,
                                    ),
                                    // ignore: deprecated_member_use
                                    ios: IOSInAppWebViewOptions(
                                      allowsInlineMediaPlayback: true,
                                    ),
                                  ),
                                  onWebViewCreated: (controller) {
                                    _webViewController = controller;
                                    unawaited(_loadHtmlIntoWebView(controller));
                                    _isViewingOriginal = true;
                                    _currentUrl = null;
                                    _updateNavigationState();
                                  },
                                  onConsoleMessage: (controller, consoleMessage) {
                                    debugPrint('[WebViewConsole] ${consoleMessage.message}');
                                  },
                                  onLoadStart: (controller, url) {
                                    final isExternal = url != null && (url.scheme == 'http' || url.scheme == 'https');
                                    if (mounted) {
                                      setState(() {
                                        _isViewingOriginal = !isExternal;
                                        _currentUrl = isExternal ? url : null;
                                      });
                                    }
                                    _updateNavigationState();
                                  },
                                  onLoadStop: (controller, url) async {
                                    final currentUrl = await controller.getUrl();
                                    final isExternal = currentUrl != null && (currentUrl.scheme == 'http' || currentUrl.scheme == 'https');
                                    if (mounted) {
                                      setState(() {
                                        _isViewingOriginal = !isExternal;
                                        _currentUrl = isExternal ? currentUrl : null;
                                      });
                                    }
                                    await _updateNavigationState();
                                    await _applyScrollEnhancements(controller);
                                  },
                                  onReceivedError: (controller, request, error) {
                                    _updateNavigationState();
                                  },
                                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                                    final url = navigationAction.request.url;
                                    if (url == null) {
                                      return NavigationActionPolicy.ALLOW;
                                    }

                                    final scheme = url.scheme.toLowerCase();

                                    if (scheme.isEmpty || scheme == 'about') {
                                      return NavigationActionPolicy.ALLOW;
                                    }

                                    if (scheme == 'mailto') {
                                      final messenger = ScaffoldMessenger.of(context);
                                      final canLaunch = await canLaunchUrl(url);
                                      if (!mounted) {
                                        return NavigationActionPolicy.CANCEL;
                                      }

                                      if (canLaunch) {
                                        await launchUrl(
                                          url,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Cannot open link: ${url.toString()}')),
                                        );
                                      }
                                      return NavigationActionPolicy.CANCEL;
                                    }

                                    // Allow HTTP/HTTPS to load inside the webview so users can navigate back
                                    return NavigationActionPolicy.ALLOW;
                                  },
                                ),
                              ),
                                ),
                            ],
                          )
                        : const Center(child: Text('No content available')),
      ),
    );
  }
}


