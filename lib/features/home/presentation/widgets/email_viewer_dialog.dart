import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'package:domail/features/home/presentation/widgets/pdf_viewer_window.dart';
import 'package:domail/services/pdf_viewer_preference_service.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/services/gmail/gmail_sync_service.dart';
import 'package:domail/services/local_folders/local_folder_service.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/services/sms/pushbullet_sms_sender.dart';
import 'package:domail/services/whatsapp/whatsapp_message_converter.dart';
import 'package:domail/services/whatsapp/whatsapp_sender.dart';

const int _maxInlineImageCount = 0; // 0 means no limit
const int _maxInlineImageTotalBytes = 0; // 0 means no limit

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

class _CachedInlineImage {
  final String mimeType;
  final String base64Data;
  final DateTime expiresAt;

  const _CachedInlineImage({
    required this.mimeType,
    required this.base64Data,
    required this.expiresAt,
  });
}

class _InlineImagePart {
  final String cid;
  final String mimeType;
  final String? attachmentId;
  final String? inlineData;
  final int sourceIndex;

  const _InlineImagePart({
    required this.cid,
    required this.mimeType,
    this.attachmentId,
    this.inlineData,
    required this.sourceIndex,
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

/// Represents a pending sent message (not yet loaded from Gmail)
class _PendingSentMessage {
  final String threadId;
  final String to;
  final String subject;
  String body; // Mutable so we can update it as user types
  final DateTime sentDate;
  final String from;
  bool isSent; // true when send completes, false while sending
  final TextEditingController? textController; // For editable messages
  final bool isSms;
  final String? smsPhoneNumber;
  final bool isWhatsApp;
  final String? whatsappPhoneNumber;

  _PendingSentMessage({
    required this.threadId,
    required this.to,
    required this.subject,
    required this.body,
    required this.sentDate,
    required this.from,
    this.isSent = false,
    this.textController,
    this.isSms = false,
    this.smsPhoneNumber,
    this.isWhatsApp = false,
    this.whatsappPhoneNumber,
  });
  
  bool get isEditable => !isSent && textController != null;
  
  void dispose() {
    textController?.dispose();
  }
}

/// Helper class to combine real messages and pending messages in conversation list
class _ConversationItem {
  final MessageIndex? message;
  final _PendingSentMessage? pending;
  final bool isPending;

  _ConversationItem({
    this.message,
    this.pending,
    required this.isPending,
  }) : assert((message != null && !isPending) || (pending != null && isPending));
}

/// Dialog for viewing email content in a webview
class EmailViewerDialog extends ConsumerStatefulWidget {
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
  ConsumerState<EmailViewerDialog> createState() => _EmailViewerDialogState();
}

class _EmailViewerDialogState extends ConsumerState<EmailViewerDialog> {
  static final Map<String, _CachedInlineImage> _inlineImageCache = {};
  static const Duration _inlineImageCacheDuration = Duration(minutes: 30);

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
  bool _allowInlineImages = false;
  bool _hasInlinePlaceholders = false;
  bool _isLoadingInlineImages = false;
  final Map<String, List<AttachmentInfo>> _conversationAttachments = {};
  final Set<String> _loadingConversationAttachmentIds = {};
  final Set<String> _tempFilePaths = {};
  final Map<String, String> _attachmentFileCache = {};
  ComposeDraftState? _pendingComposeDraft;
  ComposeEmailMode? _pendingComposeMode;
  final TextEditingController _inlineReplyController = TextEditingController();
  bool _isSendingInlineReply = false;
  
  // Pending sent messages (in-memory only, cleared on window close or when real message arrives)
  final List<_PendingSentMessage> _pendingSentMessages = [];
  final PushbulletSmsSender _smsSender = PushbulletSmsSender();
  final WhatsAppSender _whatsAppSender = WhatsAppSender();
  Timer? _conversationRefreshTimer;
  final ScrollController _conversationScrollController = ScrollController();
  
  // Expanded message state for conversation mode (allow multiple bubbles to be expanded)
  final Set<String> _expandedMessageIds = {};
  final Map<String, String> _expandedMessageBodies = {};
  final Map<String, bool> _expandedMessageLoading = {};

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.message;
    // Auto-enable conversation mode for SMS and WhatsApp messages
    final isSmsMessage = SmsMessageConverter.isSmsMessage(_currentMessage);
    final isWhatsAppMessage = WhatsAppMessageConverter.isWhatsAppMessage(_currentMessage);
    // Load conversation mode state from provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isConversationMode = ref.read(conversationModeProvider);
      if (isConversationMode || isSmsMessage || isWhatsAppMessage) {
        setState(() {
          _isConversationMode = true;
          _threadMessages = [_currentMessage];
          _isThreadLoading = true;
          _threadError = null;
          _showNavigationExtras = false;
          _canGoBack = false;
        });
        unawaited(_loadThreadMessages());
        if (!isSmsMessage) {
          _startConversationRefreshTimer();
        }
      }
    });
    _loadAccountEmail();
    _loadEmailBody();
    // Mark as read when dialog opens
    if (!_currentMessage.isRead && widget.onMarkRead != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onMarkRead!();
      });
    }
  }

  void _pruneInlineImageCache() {
    final now = DateTime.now();
    _inlineImageCache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
  }

  String _inlineImageCacheKey(String messageId, String cid) {
    return '$widget.accountId::$messageId::${cid.toLowerCase()}';
  }

  bool _hasCachedInlineImages(Map<String, dynamic> payload, String messageId) {
    _pruneInlineImageCache();
    final parts = _collectInlineImageParts(payload);
    if (parts.isEmpty) {
      return false;
    }

    final now = DateTime.now();
    for (final part in parts) {
      final cid = _normalizeContentId(part.cid);
      if (cid.isEmpty) {
        continue;
      }
      final cacheKey = _inlineImageCacheKey(messageId, cid);
      final cached = _inlineImageCache[cacheKey];
      if (cached == null || cached.expiresAt.isBefore(now)) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _inlineReplyController.dispose();
    _conversationRefreshTimer?.cancel();
    _conversationScrollController.dispose();
    for (final pending in _pendingSentMessages) {
      pending.dispose();
    }
    _pendingSentMessages.clear();
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
    // Clear WebView controller reference to prevent post-dispose callbacks
    // Note: The WebView will dispose itself, but clearing the reference prevents
    // our code from trying to use it after disposal
    _webViewController = null;
    super.dispose();
  }

  Future<void> _loadAccountEmail() async {
    final account = await GoogleAuthService().getAccountById(widget.accountId);
    if (!mounted) return;
    setState(() {
      _accountEmail = account?.email.toLowerCase();
    });
  }

  Future<void> _loadEmailBody({bool reloadInlineOnly = false}) async {
    try {
      debugPrint('[EmailViewer] >>> loadEmailBody start <<< messageId=${_currentMessage.id}');
      final stopTiming = _startTiming('[EmailViewer] loadEmailBody timing');

      if (!reloadInlineOnly) {
        _allowInlineImages = false;
        _hasInlinePlaceholders = false;
      }

      if (!reloadInlineOnly) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }
      }

      // For SMS messages, use locally stored content (subject field contains the message body)
      if (SmsMessageConverter.isSmsMessage(_currentMessage)) {
        debugPrint('[EmailViewer] Loading SMS message from local content');
        final smsBody = _currentMessage.subject;
        final bodyHtml = _wrapPlainAsHtml(smsBody);
        
        if (!mounted) return;
        setState(() {
          _htmlContent = bodyHtml;
          _attachments = [];
          _isLoading = false;
          _conversationAttachments[_currentMessage.id] = [];
          _allowInlineImages = true;
          _hasInlinePlaceholders = false;
        });
        final controller = _webViewController;
        if (controller != null) {
          unawaited(_loadHtmlIntoWebView(controller));
        }
        debugPrint('[EmailViewer] <<< loadEmailBody end (SMS) >>> messageId=${_currentMessage.id}');
        return;
      }

      // For WhatsApp messages, use locally stored content (subject field contains the message body)
      if (WhatsAppMessageConverter.isWhatsAppMessage(_currentMessage)) {
        debugPrint('[EmailViewer] Loading WhatsApp message from local content');
        final whatsappBody = _currentMessage.subject;
        final bodyHtml = _wrapPlainAsHtml(whatsappBody);
        
        if (!mounted) return;
        setState(() {
          _htmlContent = bodyHtml;
          _attachments = [];
          _isLoading = false;
          _conversationAttachments[_currentMessage.id] = [];
          _allowInlineImages = true;
          _hasInlinePlaceholders = false;
        });
        final controller = _webViewController;
        if (controller != null) {
          unawaited(_loadHtmlIntoWebView(controller));
        }
        stopTiming?.call();
        debugPrint('[EmailViewer] <<< loadEmailBody end (SMS) >>> messageId=${_currentMessage.id}');
        return;
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
            _allowInlineImages = true;
            _hasInlinePlaceholders = false;
          });
          final controller = _webViewController;
          if (controller != null) {
            unawaited(_loadHtmlIntoWebView(controller));
          }
          debugPrint('[EmailViewer] Loaded from local folder - found ${attachments.length} attachments, setState called');
          stopTiming?.call();
          debugPrint('[EmailViewer] <<< loadEmailBody end (local) >>> messageId=${_currentMessage.id}');
          return;
        } else {
          setState(() {
            _error = 'Email body not found in local folder';
            _isLoading = false;
          });
          stopTiming?.call();
          debugPrint('[EmailViewer] <<< loadEmailBody end (local-missing) >>> messageId=${_currentMessage.id}');
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

      String initialBodyHtml = bodyHtml;
      bool inlinePlaceholdersCreated = false;
      if (!_allowInlineImages && !reloadInlineOnly && htmlBody != null && payload != null) {
        if (_hasCachedInlineImages(payload, _currentMessage.id)) {
          _allowInlineImages = true;
        }
      }

      if (!_allowInlineImages && !reloadInlineOnly) {
        final placeholderRegex = RegExp(r'<img[^>]+src="cid:([^\"]+)"[^>]*>', caseSensitive: false);
        bodyHtml = bodyHtml.replaceAllMapped(placeholderRegex, (match) {
          inlinePlaceholdersCreated = true;
          final cid = match.group(1) ?? '';
          final encodedCid = Uri.encodeComponent(cid);
          return '<div class="inline-placeholder" data-inline-placeholder="$encodedCid" '
              'style="padding:12px;border:1px dashed rgba(120,144,156,0.4);border-radius:8px;text-align:center;margin:8px 0;">'
              '<span style="font-size:18px;color:#90a4ae;">&#128444;</span>'
              '</div>';
        });
      }

      if (!reloadInlineOnly) {
        final initialHtml = _buildEmailHtml(initialBodyHtml);
        if (mounted) {
          setState(() {
            _htmlContent = initialHtml;
            _isLoading = false;
            _attachments = attachments;
            _conversationAttachments[_currentMessage.id] = attachments;
            _hasInlinePlaceholders = inlinePlaceholdersCreated;
          });
        }
      }

      if (htmlBody != null && payload != null && (_allowInlineImages || reloadInlineOnly)) {
        final inlineResult = await _loadInlineImages(
          payload,
          _currentMessage.id,
          accessToken,
          maxCount: _maxInlineImageCount,
          maxTotalBytes: _maxInlineImageTotalBytes,
        );
        if (inlineResult.images.isNotEmpty) {
          bodyHtml = _embedInlineImages(bodyHtml, inlineResult.images);
        }
        if (inlineResult.consumedAttachmentIds.isNotEmpty) {
          attachments = attachments
              .where((attachment) => !inlineResult.consumedAttachmentIds.contains(attachment.attachmentId))
              .toList();
        }

        final fullHtml = _buildEmailHtml(bodyHtml);
        if (mounted && !reloadInlineOnly) {
          setState(() {
            _htmlContent = fullHtml;
            _attachments = attachments;
            _conversationAttachments[_currentMessage.id] = attachments;
            _hasInlinePlaceholders = false;
            _isLoading = false;
            _allowInlineImages = true;
            _isLoadingInlineImages = false;
          });
          final controller = _webViewController;
          if (controller != null) {
            unawaited(_loadHtmlIntoWebView(controller));
          }
        } else {
          if (mounted) {
            setState(() {
              _attachments = attachments;
              _conversationAttachments[_currentMessage.id] = attachments;
              _hasInlinePlaceholders = false;
              _allowInlineImages = true;
              _isLoadingInlineImages = false;
            });
          } else {
            _isLoadingInlineImages = false;
          }
        }
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
      stopTiming?.call();
      debugPrint('[EmailViewer] <<< loadEmailBody end (remote) >>> messageId=${_currentMessage.id}');
    } catch (e, stackTrace) {
      debugPrint('[EmailViewer] ERROR loading email: $e');
      debugPrint('[EmailViewer] Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'Error loading email: $e';
        _isLoading = false;
        _isLoadingInlineImages = false;
      });
    }
  }

  VoidCallback? _startTiming(String label) {
    final stopwatch = Stopwatch()..start();
    debugPrint('$label started');
    return () {
      stopwatch.stop();
      debugPrint('$label finished in ${stopwatch.elapsedMilliseconds} ms');
    };
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

  Future<void> _loadEmbeddedImages() async {
    if (_allowInlineImages || _isLoadingInlineImages) {
      return;
    }
    setState(() {
      _allowInlineImages = true;
      _isLoadingInlineImages = true;
    });
    try {
      await _loadEmailBody(reloadInlineOnly: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInlineImages = false;
        });
      } else {
        _isLoadingInlineImages = false;
      }
    }
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

    void collect(dynamic part, int index) {
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
            sourceIndex: index,
          ),
        );
      }

      final parts = part['parts'] as List<dynamic>?;
      if (parts != null) {
        for (final child in parts) {
          collect(child, index);
        }
      }
    }

    collect(payload, 0);
    return inlineParts;
  }

  Future<_InlineImageLoadResult> _loadInlineImages(
    Map<String, dynamic> payload,
    String messageId,
    String accessToken, {
    int maxCount = _maxInlineImageCount,
    int maxTotalBytes = _maxInlineImageTotalBytes,
  }) async {
    _pruneInlineImageCache();
    final inlineParts = _collectInlineImageParts(payload);
    inlineParts.sort((a, b) => a.sourceIndex.compareTo(b.sourceIndex));

    if (inlineParts.isEmpty) {
      debugPrint('[EmailViewer] No inline image parts detected for message $messageId');
      return const _InlineImageLoadResult(images: {}, consumedAttachmentIds: {});
    }

    final inlineImages = <String, _InlineImageData>{};
    final consumedAttachmentIds = <String>{};
    debugPrint('[EmailViewer] Found ${inlineParts.length} potential inline image parts for message $messageId');

    int processed = 0;
    int totalBytes = 0;
    for (final part in inlineParts) {
      final hasCountLimit = maxCount > 0;
      final hasSizeLimit = maxTotalBytes > 0;
      if ((hasCountLimit && processed >= maxCount) || (hasSizeLimit && totalBytes >= maxTotalBytes)) {
        debugPrint('[EmailViewer] Inline image budget reached (processed=$processed totalBytes=$totalBytes). Remaining parts skipped.');
        break;
      }

      final cid = _normalizeContentId(part.cid);
      if (cid.isEmpty) {
        continue;
      }

      final cacheKey = _inlineImageCacheKey(messageId, cid);
      final cached = _inlineImageCache[cacheKey];
      if (cached != null) {
        if (cached.expiresAt.isAfter(DateTime.now())) {
          final data = _InlineImageData(mimeType: cached.mimeType, base64Data: cached.base64Data);
          inlineImages[cid] = data;
          unawaited(_replaceInlineImageInView(cid, data));
          processed += 1;
          totalBytes += (base64Decode(cached.base64Data)).length;
          debugPrint('[EmailViewer] Inline image cid=$cid served from cache');
          continue;
        } else {
          _inlineImageCache.remove(cacheKey);
        }
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

      totalBytes += bytes.length;
      processed += 1;

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

      unawaited(_replaceInlineImageInView(cid, inlineImages[cid]!));

      _inlineImageCache[cacheKey] = _CachedInlineImage(
        mimeType: embedMimeType,
        base64Data: inlineImages[cid]!.base64Data,
        expiresAt: DateTime.now().add(_inlineImageCacheDuration),
      );
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

  Future<void> _replaceInlineImageInView(String cid, _InlineImageData image) async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    final cidAttr = Uri.encodeComponent(cid);
    final lowerCid = cid.toLowerCase();
    final dataUrl = 'data:${image.mimeType};base64,${image.base64Data}';
    final script = '''
(function() {
  const dataUrl = ${jsonEncode(dataUrl)};
  const placeholder = document.querySelector('[data-inline-placeholder="$cidAttr"]');
  if (placeholder) {
    const img = document.createElement('img');
    img.src = dataUrl;
    img.style.maxWidth = '100%';
    img.style.height = 'auto';
    placeholder.replaceWith(img);
    return;
  }
  const nodes = document.querySelectorAll('img[src^="cid:"]');
  nodes.forEach((node) => {
    const src = (node.getAttribute('src') || '').toLowerCase();
    if (src === ${jsonEncode('cid:$lowerCid')}) {
      node.setAttribute('src', dataUrl);
    }
  });
})();
''';
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[EmailViewer] Failed to inject inline image cid=$cid via JS: $e');
    }
  }

  String _buildEmailHtml(String bodyHtml) {
    return '''
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

      // Check preference for PDF viewer
      // Check both extension and filename for PDF (filename check handles cases where file path doesn't have extension)
      final extension = path.extension(file.path).toLowerCase();
      final isPdf = extension == '.pdf' || attachment.filename.toLowerCase().endsWith('.pdf');
      if (isPdf) {
        final useInternal = await PdfViewerPreferenceService().useInternalViewer();
        if (useInternal) {
          if (!mounted) return;
          await PdfViewerWindow.open(
            context,
            filePath: file.path,
          );
          return;
        }
      }
      
      // Use system file opener (allows package selection on Windows)
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

  void _handleReply() async {
    final isSmsThread = _isSmsConversation();
    final isWhatsAppThread = _isWhatsAppConversation();
    if (!_isConversationMode && (isSmsThread || isWhatsAppThread)) {
      _toggleConversationMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isWhatsAppThread 
            ? 'Conversation mode enabled for WhatsApp replies'
            : 'Conversation mode enabled for SMS replies')),
        );
      }
      return;
    }

    // In conversation mode, create an empty message bubble at the top
    if (_isConversationMode) {
      // Find the last received email (not sent by user) to get the "To" address
      MessageIndex? lastReceivedMessage;
      final accountEmail = _accountEmail?.toLowerCase() ?? '';
      
      // Combine all messages (thread + current)
      final allThreadMessages = _threadMessages.isEmpty 
          ? <MessageIndex>[_currentMessage] 
          : List<MessageIndex>.from(_threadMessages);
      
      // Find the most recent message that was NOT sent by the user
      for (final msg in allThreadMessages) {
        final senderEmail = _extractEmail(msg.from).toLowerCase();
        if (senderEmail != accountEmail && accountEmail.isNotEmpty) {
          if (lastReceivedMessage == null || 
              msg.internalDate.isAfter(lastReceivedMessage.internalDate)) {
            lastReceivedMessage = msg;
          }
        }
      }
      
      // Fallback to current message if no received message found
      final messageToReplyTo = lastReceivedMessage ?? _currentMessage;
      
      final isSmsReply = SmsMessageConverter.isSmsMessage(messageToReplyTo);
      final isWhatsAppReply = WhatsAppMessageConverter.isWhatsAppMessage(messageToReplyTo);
      final smsPhone = isSmsReply ? _extractSmsPhone(messageToReplyTo) : null;
      final whatsappPhone = isWhatsAppReply ? _extractWhatsAppPhone(messageToReplyTo) : null;
      
      if (isSmsReply && (smsPhone == null || smsPhone.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to determine the SMS recipient number. Please reply directly from your phone.',
              ),
            ),
          );
        }
        return;
      }
      
      if (isWhatsAppReply && (whatsappPhone == null || whatsappPhone.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to determine the WhatsApp recipient number. Please send this message from your phone.',
              ),
            ),
          );
        }
        return;
      }

      // Use the sender of the last received email/SMS/WhatsApp as the "To" address
      final to = isSmsReply 
          ? smsPhone! 
          : isWhatsAppReply 
              ? whatsappPhone! 
              : _extractEmail(messageToReplyTo.from);
      final subject = isSmsReply
          ? 'SMS to $to'
          : isWhatsAppReply
              ? 'WhatsApp to $to'
              : messageToReplyTo.subject.startsWith('Re:')
                  ? messageToReplyTo.subject
                  : 'Re: ${messageToReplyTo.subject}';
      final threadId = messageToReplyTo.threadId.isNotEmpty ? messageToReplyTo.threadId : '';
      
      // Get account email for "From" field
      final account = await GoogleAuthService().getAccountById(widget.accountId);
      final fromEmail = account?.email ?? '';
      
      // Create an empty editable pending message
      final textController = TextEditingController();
      final pendingMessage = _PendingSentMessage(
        threadId: threadId,
        to: to,
        subject: subject,
        body: '', // Empty - will be filled when user types
        sentDate: DateTime.now(),
        from: isSmsReply && fromEmail.isNotEmpty 
            ? '$fromEmail (SMS)' 
            : isWhatsAppReply && fromEmail.isNotEmpty 
                ? '$fromEmail (WhatsApp)' 
                : fromEmail,
        isSent: false,
        textController: textController,
        isSms: isSmsReply,
        smsPhoneNumber: smsPhone,
        isWhatsApp: isWhatsAppReply,
        whatsappPhoneNumber: whatsappPhone,
      );
      
      setState(() {
        _pendingSentMessages.add(pendingMessage);
      });
      
      // Scroll to top to show the new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_conversationScrollController.hasClients) {
          _conversationScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      return;
    }
    
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
    if (_isSmsConversation()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply all is not available for SMS conversations')),
        );
      }
      return;
    }
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
    if (_isSmsConversation()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forward is not available for SMS conversations')),
        );
      }
      return;
    }
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
      ref.read(conversationModeProvider.notifier).state = false;
      _conversationRefreshTimer?.cancel();
      _conversationRefreshTimer = null;
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
    ref.read(conversationModeProvider.notifier).state = true;

    unawaited(_loadThreadMessages());
    _startConversationRefreshTimer();
  }

  void _startConversationRefreshTimer() {
    _conversationRefreshTimer?.cancel();
    if (!_isConversationMode) return;
    
    // Refresh every 30 seconds to check for new messages
    _conversationRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isConversationMode || !mounted) {
        _conversationRefreshTimer?.cancel();
        return;
      }
      // Silent refresh - no loading indicator
      await _refreshConversation();
    });
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
      
      // Clear pending messages when new emails with same threadId arrive
      // Track previous message IDs to detect new messages
      final previousMessageIds = _threadMessages.map((m) => m.id).toSet();
      final newMessageIds = messages.map((m) => m.id).toSet();
      final hasNewMessages = newMessageIds.difference(previousMessageIds).isNotEmpty;
      
      if (hasNewMessages) {
        // Remove all pending messages for this thread when any new message is received
        _pendingSentMessages.removeWhere((pending) => pending.threadId == threadId);
      }
      
      setState(() {
        _threadMessages = messages.isEmpty ? [_currentMessage] : messages;
        _isThreadLoading = false;
        _threadError = null;
      });
      
      // Scroll to top (position 0) when new messages arrive
      if (hasNewMessages && _conversationScrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_conversationScrollController.hasClients) {
            _conversationScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _threadMessages = [_currentMessage];
        _isThreadLoading = false;
        _threadError = 'Failed to load conversation: $e';
      });
    }
  }

  Future<void> _refreshConversation({bool showLoading = false}) async {
    if (!_isConversationMode) return;
    
    // Skip Gmail sync for SMS conversations - they are managed by Pushbullet
    if (_isSmsConversation()) {
      // Just reload thread messages from local database
      if (showLoading && mounted) {
        setState(() {
          _isThreadLoading = true;
        });
      }
      await _loadThreadMessages();
      if (showLoading && mounted) {
        setState(() {
          _isThreadLoading = false;
        });
      }
      return;
    }
    
    try {
      if (showLoading && mounted) {
        setState(() {
          _isThreadLoading = true;
        });
      }
      
      final syncService = GmailSyncService();
      // Run incremental sync
      await syncService.incrementalSync(widget.accountId);
      // Reload thread messages (silently if not showing loading)
      await _loadThreadMessages();
      
      if (showLoading && mounted) {
        setState(() {
          _isThreadLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EmailViewer] Failed to refresh conversation: $e');
      if (showLoading && mounted) {
        setState(() {
          _isThreadLoading = false;
        });
      }
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

  bool _isSmsConversation() {
    if (SmsMessageConverter.isSmsMessage(_currentMessage)) {
      return true;
    }
    return _threadMessages.any(SmsMessageConverter.isSmsMessage);
  }

  bool _isWhatsAppConversation() {
    if (WhatsAppMessageConverter.isWhatsAppMessage(_currentMessage)) {
      return true;
    }
    return _threadMessages.any(WhatsAppMessageConverter.isWhatsAppMessage);
  }

  String? _extractSmsPhone(MessageIndex message) {
    String? candidate;
    final match = RegExp(r'<([^>]+)>').firstMatch(message.from);
    if (match != null) {
      candidate = match.group(1)?.trim();
    } else {
      candidate = message.from.trim();
    }

    if (candidate == null || candidate.isEmpty) {
      return null;
    }

    // Require at least one digit so Pushbullet can route the SMS.
    final hasDigits = RegExp(r'\d').hasMatch(candidate);
    return hasDigits ? candidate : null;
  }

  String? _extractWhatsAppPhone(MessageIndex message) {
    return WhatsAppMessageConverter.extractPhoneNumber(message);
  }


  String _wrapPlainAsHtml(String plain) {
    return '<pre style="white-space: pre-wrap; font-family: inherit;">${_escapeHtml(plain)}</pre>';
  }

  Widget _buildPendingSentMessageBubble(
    _PendingSentMessage pending,
    ThemeData theme,
    double maxWidth,
    double minWidth,
  ) {
    final cs = theme.colorScheme;
    final textColor = cs.onPrimary;
    final metaColor = textColor.withValues(alpha: 0.8);
    final isEditable = pending.isEditable;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, -20 * (1 - value)), // Slide down from top
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                minWidth: minWidth,
              ),
              child: Material(
                color: ActionMailTheme.sentMessageColor,
                elevation: 0,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pending.from,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(pending.sentDate),
                                  style: theme.textTheme.labelSmall?.copyWith(color: metaColor),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  pending.isSms
                                      ? 'SMS to ${pending.smsPhoneNumber ?? pending.to}'
                                      : 'To: ${pending.to}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: metaColor),
                                ),
                                const SizedBox(height: 12),
                                if (!pending.isSms)
                                  Text(
                                    pending.subject,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: textColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else
                                  Text(
                                    'Reply via SMS',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: textColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isEditable)
                            IconButton(
                              icon: Icon(Icons.close, size: 18, color: textColor),
                              onPressed: () {
                                setState(() {
                                  pending.dispose();
                                  _pendingSentMessages.remove(pending);
                                });
                              },
                              tooltip: 'Cancel',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      if (isEditable) ...[
                        const SizedBox(height: 12),
                        Builder(
                          key: ValueKey('textfield_${pending.threadId}'),
                          builder: (context) {
                            return TextField(
                              key: ValueKey('textfield_input_${pending.threadId}'),
                              controller: pending.textController,
                              autofocus: false,
                              style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                              decoration: InputDecoration(
                                hintText: 'Type your message...',
                                hintStyle: TextStyle(color: metaColor),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: metaColor.withValues(alpha: 0.3)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: metaColor.withValues(alpha: 0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: textColor.withValues(alpha: 0.5)),
                                ),
                                filled: true,
                                fillColor: textColor.withValues(alpha: 0.1),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: null,
                              minLines: 3,
                              textInputAction: TextInputAction.newline,
                              keyboardType: TextInputType.multiline,
                              enableSuggestions: false,
                              autocorrect: false,
                              onChanged: (value) {
                                // Update the body without calling setState immediately to avoid losing focus
                                // We'll call setState in a post-frame callback to update the UI
                                pending.body = value;
                                // Update UI after the current frame to preserve focus
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(() {
                                      // Trigger rebuild to update button state
                                    });
                                  }
                                });
                              },
                              onSubmitted: (value) {
                                // Explicitly do nothing - prevent auto-send
                                // User must click Send button to send
                                // Even if Enter is pressed, don't send
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Builder(
                            key: ValueKey('sendbutton_${pending.body.length}_$_isSendingInlineReply'),
                            builder: (context) {
                              // Only create callback if body is not empty AND not sending
                              final bool canSend = pending.body.trim().isNotEmpty && !_isSendingInlineReply;
                              final VoidCallback? sendCallback = canSend
                                  ? () {
                                      if (pending.body.trim().isEmpty || _isSendingInlineReply) {
                                        return;
                                      }
                                      _sendPendingMessage(pending);
                                    }
                                  : null;
                              
                              return TextButton.icon(
                                onPressed: sendCallback, // Will be null if canSend is false
                                autofocus: false, // Explicitly prevent autofocus
                                icon: !canSend
                                    ? (_isSendingInlineReply
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.send, size: 18, color: Colors.grey))
                                    : const Icon(Icons.send, size: 18),
                                label: Text(_isSendingInlineReply ? 'Sending...' : 'Send'),
                                style: TextButton.styleFrom(
                                  foregroundColor: textColor,
                                  disabledForegroundColor: Colors.grey,
                                ),
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        if (pending.body.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            pending.body,
                            style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            pending.isSent ? 'Sent' : 'Sending...',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: metaColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _sendPendingMessage(_PendingSentMessage pending) async {
    final text = pending.body.trim();
    // Prevent sending if text is too short (less than 2 characters) - this prevents accidental sends
    if (text.isEmpty || text.length < 2 || _isSendingInlineReply) {
      return;
    }

    if (pending.isSms) {
      await _sendPendingSms(pending, text);
      return;
    }

    if (pending.isWhatsApp) {
      await _sendPendingWhatsApp(pending, text);
      return;
    }

    // Find the message to reply to
    MessageIndex? lastReceivedMessage;
    final accountEmail = _accountEmail?.toLowerCase() ?? '';
    
    final allThreadMessages = _threadMessages.isEmpty 
        ? <MessageIndex>[_currentMessage] 
        : List<MessageIndex>.from(_threadMessages);
    
    for (final msg in allThreadMessages) {
      final senderEmail = _extractEmail(msg.from).toLowerCase();
      if (senderEmail != accountEmail && accountEmail.isNotEmpty) {
        if (lastReceivedMessage == null || 
            msg.internalDate.isAfter(lastReceivedMessage.internalDate)) {
          lastReceivedMessage = msg;
        }
      }
    }
    
    final messageToReplyTo = lastReceivedMessage ?? _currentMessage;
    
    setState(() {
      _isSendingInlineReply = true;
      pending.isSent = false; // Mark as sending
    });

    try {
      final syncService = GmailSyncService();

      String? inReplyTo;
      List<String>? references;

      // Try to fetch reply context from Gmail API
      // For local folder messages, this may fail if the message doesn't exist in Gmail,
      // but that's okay - we'll just send without reply headers
      try {
        final replyContext = await syncService.fetchReplyContext(widget.accountId, messageToReplyTo.id);
        if (replyContext != null) {
          final headerMessageId = replyContext.messageIdHeader;
          if (headerMessageId != null && headerMessageId.isNotEmpty) {
            inReplyTo = headerMessageId;
          }
          final refs = replyContext.references;
          if (refs.isNotEmpty) {
            references = List<String>.from(refs);
            if (inReplyTo != null && !references.contains(inReplyTo)) {
              references.add(inReplyTo);
            }
          }
        }
      } catch (e) {
        // If fetching reply context fails (e.g., for local folder messages),
        // just log it and continue without reply headers
        debugPrint('[EmailViewer] Failed to fetch reply context: $e');
      }

      final success = await syncService.sendEmail(
        widget.accountId,
        to: pending.to,
        subject: pending.subject,
        body: text,
        htmlBody: _wrapPlainAsHtml(text),
        inReplyTo: inReplyTo,
        references: references,
        threadId: pending.threadId.isNotEmpty ? pending.threadId : null,
      );

      if (!success) {
        throw Exception('Failed to send email (sendEmail returned false)');
      }

      if (!mounted) return;
      
      setState(() {
        pending.isSent = true;
        _isSendingInlineReply = false;
      });

      // Refresh conversation to get the actual sent message
      await _refreshConversation(showLoading: false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent successfully')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending.isSent = false;
        _isSendingInlineReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    }
  }

  Future<void> _sendPendingSms(_PendingSentMessage pending, String text) async {
    final phone = pending.smsPhoneNumber ?? pending.to;
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Missing SMS recipient number. Please reply directly from your phone.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSendingInlineReply = true;
      pending.isSent = false;
    });

    try {
      await _smsSender.sendSms(
        accountId: widget.accountId,
        phoneNumber: phone,
        message: text,
      );
      if (!mounted) return;
      setState(() {
        pending.isSent = true;
        _isSendingInlineReply = false;
      });
      await _refreshConversation(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS sent via Pushbullet')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending.isSent = false;
        _isSendingInlineReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send SMS: $e')),
      );
    }
  }

  Future<void> _sendPendingWhatsApp(_PendingSentMessage pending, String text) async {
    final phone = pending.whatsappPhoneNumber ?? pending.to;
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing WhatsApp recipient number')),
      );
      return;
    }

    setState(() {
      _isSendingInlineReply = true;
      pending.isSent = false;
    });

    try {
      await _whatsAppSender.sendWhatsApp(
        accountId: widget.accountId,
        phoneNumber: phone,
        message: text,
      );
      if (!mounted) return;
      setState(() {
        pending.isSent = true;
        _isSendingInlineReply = false;
      });
      await _refreshConversation(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp message sent')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending.isSent = false;
        _isSendingInlineReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send WhatsApp message: $e')),
      );
    }
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
    
    // Combine real messages with pending sent messages
    final threadId = _currentMessage.threadId;
    final pendingForThread = _pendingSentMessages
        .where((p) => p.threadId == threadId)
        .toList();
    
    // Create a combined list with pending messages
    final allMessages = <_ConversationItem>[];
    for (final msg in messages) {
      allMessages.add(_ConversationItem(message: msg, isPending: false));
    }
    for (final pending in pendingForThread) {
      allMessages.add(_ConversationItem(pending: pending, isPending: true));
    }
    
    // Sort by date (newest first) - newest at index 0, appears at top
    allMessages.sort((a, b) {
      final dateA = a.isPending ? a.pending!.sentDate : a.message!.internalDate;
      final dateB = b.isPending ? b.pending!.sentDate : b.message!.internalDate;
      return dateB.compareTo(dateA); // Newest first
    });
    
    final showConversationHint = allMessages.length <= 1 && pendingForThread.isEmpty;
    final itemCount = showConversationHint ? allMessages.length + 1 : allMessages.length;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth <= 600 ? constraints.maxWidth * 0.8 : 520.0;
        final minWidth = constraints.maxWidth <= 600 ? constraints.maxWidth * 0.6 : maxWidth * 0.6;
        final resolvedMinWidth = minWidth > maxWidth ? maxWidth : minWidth;

        return ListView.builder(
          controller: _conversationScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // allMessages is sorted newest first (index 0 = newest)
            // ListView index 0 = top, so allMessages[0] appears at top
            if (showConversationHint && index == itemCount - 1) {
              return Padding(
                key: const ValueKey('conversation_hint'),
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

            if (index < 0 || index >= allMessages.length) {
              return const SizedBox.shrink();
            }
            
            final item = allMessages[index];
            final isPending = item.isPending;
            
            if (isPending) {
              return _buildPendingSentMessageBubble(item.pending!, theme, maxWidth, resolvedMinWidth);
            }
            
            final message = item.message!;
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
            // For SMS messages, check if there's a contact name structure
            final isSms = SmsMessageConverter.isSmsMessage(message);
            final hasSmsContactName = isSms && message.from.contains('<') && message.from.contains('>');
            // Debug logging for SMS messages
            if (isSms) {
              debugPrint('[EmailViewer] SMS sender display - from: "${message.from}", senderName: "$senderName", senderEmail: "$senderEmail"');
              debugPrint('[EmailViewer] SMS display - hasContactName: $hasSmsContactName');
            }
            final attachments = _conversationAttachments[message.id];
            final isLoadingAttachments = _loadingConversationAttachmentIds.contains(message.id);

            if ((message.hasAttachments || (attachments != null && attachments.isNotEmpty)) && attachments == null && !isLoadingAttachments) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _loadAttachmentsForConversationMessage(message);
              });
            }

            final isExpanded = _expandedMessageIds.contains(message.id);
            final isLoadingBody = _expandedMessageLoading[message.id] == true;
            final bodyHtml = _expandedMessageBodies[message.id];

            return Padding(
              key: ValueKey('conversation_message_${message.id}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: alignment,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        onTap: () {
                          // Single-click: expand/collapse
                          if (isExpanded) {
                            setState(() {
                              _expandedMessageIds.remove(message.id);
                            });
                          } else {
                            setState(() {
                              _expandedMessageIds.add(message.id);
                            });
                            
                            // Load email body if not already loaded
                            if (!_expandedMessageBodies.containsKey(message.id) && !isLoadingBody) {
                              unawaited(_loadEmailBodyForMessage(message));
                            }
                          }
                        },
                        onDoubleTap: () {
                          // Double-click: open in normal view
                          _showMessageFromThread(message);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // For SMS messages, show name on first row and phone on second row
                              if (isSms) ...[
                                if (hasSmsContactName) ...[
                                  // First row: Contact name (what's before < >)
                                  Text(
                                    senderName,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: textColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  // Second row: Phone number (what's inside < >)
                                  Text(
                                    senderEmail.isNotEmpty ? senderEmail : senderName,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: metaColor,
                                    ),
                                  ),
                                ] else ...[
                                  // No contact name, just phone number - show on first row only
                                  Text(
                                    senderName.isNotEmpty ? senderName : message.from,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: textColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ] else ...[
                                Text(
                                  '$senderName <$senderEmail>',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
                              if (!isExpanded) ...[
                                // Normal collapsed view - show snippet
                                if (message.snippet != null && message.snippet!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    message.snippet!,
                                    style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                                  ),
                                ],
                              ] else ...[
                                // Expanded view - show full body
                                const SizedBox(height: 12),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: 400, // Twice normal height (approximately)
                                  ),
                                  child: SingleChildScrollView(
                                    child: isLoadingBody
                                        ? Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: textColor,
                                              ),
                                            ),
                                          )
                                        : bodyHtml != null
                                            ? _buildExpandedBodyContent(bodyHtml, textColor, theme)
                                            : Text(
                                                'No content available',
                                                style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                                              ),
                                  ),
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

  String _htmlToPlainText(String html) {
    // Simple HTML to plain text converter
    // Remove script and style tags and their content
    String text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    
    // Replace common HTML entities
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll('&apos;', "'");
    
    // Replace block-level elements with newlines
    text = text.replaceAll(RegExp(r'</(p|div|br|li|h[1-6]|tr)[^>]*>', caseSensitive: false), '\n');
    
    // Remove all remaining HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    
    // Decode remaining HTML entities (basic ones)
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code != null && code >= 32 && code <= 126) {
        return String.fromCharCode(code);
      }
      return match.group(0) ?? '';
    });
    
    // Clean up whitespace
    text = text.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');
    text = text.trim();
    
    return text;
  }

  Widget _buildExpandedBodyContent(String htmlBody, Color textColor, ThemeData theme) {
    // Try to detect if it's HTML or plain text
    final isHtml = htmlBody.contains('<') && htmlBody.contains('>');
    
    if (isHtml) {
      // For HTML content, convert to plain text for simple display
      final plainText = _htmlToPlainText(htmlBody);
      return SelectableText(
        plainText,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          height: 1.5,
        ),
      );
    } else {
      // Already plain text
      return SelectableText(
        htmlBody,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          height: 1.5,
        ),
      );
    }
  }

  Future<void> _loadEmailBodyForMessage(MessageIndex message) async {
    // If already loaded, don't reload
    if (_expandedMessageBodies.containsKey(message.id)) {
      return;
    }

    // Mark as loading
    if (mounted) {
      setState(() {
        _expandedMessageLoading[message.id] = true;
      });
    }

    try {
      String? bodyHtml;

      // For SMS messages, use locally stored content (subject field contains the message body)
      if (SmsMessageConverter.isSmsMessage(message)) {
        final smsBody = message.subject;
        bodyHtml = _wrapPlainAsHtml(smsBody);
      } else if (widget.localFolderName != null) {
        // If viewing from local folder, load from saved file
        final folderService = LocalFolderService();
        final body = await folderService.loadEmailBody(widget.localFolderName!, message.id);
        if (body != null) {
          bodyHtml = body;
        }
      } else {
        // Load from Gmail API
        final account = await GoogleAuthService().ensureValidAccessToken(widget.accountId);
        final accessToken = account?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          throw Exception('No access token available');
        }

        final resp = await http.get(
          Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );

        if (resp.statusCode != 200) {
          throw Exception('Failed to load email: ${resp.statusCode}');
        }

        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        final payload = map['payload'] as Map<String, dynamic>?;

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

        // Prefer HTML over plain text
        final bodyContent = htmlBody ?? plainBody ?? message.snippet ?? 'No content available';
        bodyHtml = htmlBody != null
            ? bodyContent
            : '<pre style="white-space: pre-wrap; font-family: inherit;">${_escapeHtml(bodyContent)}</pre>';
      }

      if (mounted) {
        setState(() {
          _expandedMessageBodies[message.id] = bodyHtml ?? 'No content available';
          _expandedMessageLoading[message.id] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _expandedMessageBodies[message.id] = 'Error loading email: $e';
          _expandedMessageLoading[message.id] = false;
        });
      }
    }
  }

  Future<void> _showMessageFromThread(MessageIndex message) async {
    // Always exit conversation mode and show the clicked email
    setState(() {
      _isConversationMode = false;
      _currentMessage = message;
      _htmlContent = null;
      _attachments = [];
      _error = null;
      _isLoading = true;
      _isViewingOriginal = true;
      _showNavigationExtras = false;
      _canGoBack = false;
      _currentUrl = null;
    });
    ref.read(conversationModeProvider.notifier).state = false;
    _conversationRefreshTimer?.cancel();
    _conversationRefreshTimer = null;
    _updateNavigationState();
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
    final isSmsThread = _isSmsConversation();
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
                if (!mounted) return;
                if (_webViewController != null && await _webViewController!.canGoBack()) {
                  await _webViewController!.goBack();
                  if (mounted) {
                    await _updateNavigationState();
                  }
                }
              },
            ),
          if (!_isConversationMode && _showNavigationExtras)
            IconButton(
              tooltip: 'Original Email',
              icon: const Icon(Icons.home, size: 20),
              color: theme.appBarTheme.foregroundColor,
              onPressed: () async {
                if (!mounted) return;
                if (_webViewController != null && _htmlContent != null) {
                  if (mounted) {
                    setState(() {
                      _isViewingOriginal = true;
                      _currentUrl = null;
                    });
                  }
                  if (mounted && _webViewController != null) {
                    await _loadHtmlIntoWebView(_webViewController!);
                  }
                }
              },
            ),
          if (_hasInlinePlaceholders || _isLoadingInlineImages)
            IconButton(
              tooltip: _isLoadingInlineImages ? 'Loading images…' : 'Load embedded images',
              color: theme.appBarTheme.foregroundColor,
              icon: _isLoadingInlineImages
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : const Icon(Icons.image_outlined, size: 20),
              onPressed: _isLoadingInlineImages ? null : _loadEmbeddedImages,
            ),
          if (!_isConversationMode && _showNavigationExtras && _currentUrl != null)
            IconButton(
              tooltip: 'Open in Browser',
              icon: const Icon(Icons.open_in_new, size: 20),
              color: theme.appBarTheme.foregroundColor,
              onPressed: _openCurrentInBrowser,
            ),
          if (_isConversationMode)
            IconButton(
              tooltip: 'Refresh conversation',
              icon: const Icon(Icons.refresh, size: 20),
              color: theme.appBarTheme.foregroundColor,
              onPressed: () => _refreshConversation(showLoading: true),
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
              PopupMenuItem<_ReplyMenuAction>(
                value: _ReplyMenuAction.reply,
                child: Text(isSmsThread ? 'Reply via SMS' : 'Reply'),
              ),
              if (!isSmsThread)
                const PopupMenuItem<_ReplyMenuAction>(
                  value: _ReplyMenuAction.replyAll,
                  child: Text('Reply all'),
                ),
              if (!isSmsThread)
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
                        ? Builder(
                            builder: (context) {
                              final attachmentChips = _attachments.map(_buildAttachmentChip).toList();

                              return Column(
                                children: [
                                  if (attachmentChips.isNotEmpty)
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
                                            children: [
                                              ...attachmentChips,
                                            ],
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
                              );
                            },
                          )
                        : const Center(child: Text('No content available')),
      ),
    );
  }
}


