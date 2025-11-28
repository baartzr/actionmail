import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:domail/services/gmail/gmail_sync_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:domail/features/home/presentation/widgets/pdf_viewer_window.dart';
import 'package:domail/services/pdf_viewer_preference_service.dart';
import 'package:domail/features/home/presentation/widgets/message_compose_type.dart';
import 'package:domail/features/home/presentation/widgets/contact_autocomplete_field.dart';
import 'package:domail/features/home/presentation/widgets/contact_picker_dialog.dart';
import 'package:domail/features/home/presentation/widgets/contacts_management_dialog.dart';
// import 'package:domail/services/sms/pushbullet_sms_sender.dart'; // Removed - using companion app now
import 'package:domail/services/sms/companion_sms_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/services/whatsapp/whatsapp_message_converter.dart';

enum ComposeEmailMode {
  newEmail,
  reply,
  replyAll,
  forward,
}

enum ComposeDialogResultType { sent, cancelled, viewOriginal }

class ComposeDraftState {
  final String to;
  final String subject;
  final String body;
  final List<PlatformFile> attachments;
  final List<GmailAttachmentData> forwardedAttachments;
  final String? originalHtml;
  final String? originalPlain;

  const ComposeDraftState({
    required this.to,
    required this.subject,
    required this.body,
    this.attachments = const [],
    this.forwardedAttachments = const [],
    this.originalHtml,
    this.originalPlain,
  });

  ComposeDraftState copyWith({
    String? to,
    String? subject,
    String? body,
    List<PlatformFile>? attachments,
    List<GmailAttachmentData>? forwardedAttachments,
    String? originalHtml,
    String? originalPlain,
  }) {
    return ComposeDraftState(
      to: to ?? this.to,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      attachments: attachments ?? this.attachments,
      forwardedAttachments: forwardedAttachments ?? this.forwardedAttachments,
      originalHtml: originalHtml ?? this.originalHtml,
      originalPlain: originalPlain ?? this.originalPlain,
    );
  }
}

class ComposeDialogResult {
  final ComposeDialogResultType type;
  final ComposeDraftState? draft;

  const ComposeDialogResult(this.type, [this.draft]);
}

/// Dialog for composing new emails
class ComposeEmailDialog extends StatefulWidget {
  final String? to;
  final String? subject;
  final String? body;
  final String accountId;
  final MessageIndex? originalMessage; // Original email when replying/forwarding
  final ComposeEmailMode mode;
  final ComposeDraftState? initialDraft;

  const ComposeEmailDialog({
    super.key,
    this.to,
    this.subject,
    this.body,
    required this.accountId,
    this.originalMessage,
    this.mode = ComposeEmailMode.newEmail,
    this.initialDraft,
  });

  @override
  State<ComposeEmailDialog> createState() => _ComposeEmailDialogState();
}

class _ComposeEmailDialogState extends State<ComposeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _isSending = false;
  final List<PlatformFile> _attachments = [];
  final List<String> _tempAttachmentPaths = [];
  bool _isOriginalLoading = false;
  String? _originalPreviewHtml;
  String? _originalPlainText;
  final List<GmailAttachmentData> _forwardedAttachments = [];
  static final DateFormat _previewDateFormat = DateFormat('EEE, MMM d, yyyy h:mm a');
  // final PushbulletSmsSender _smsSender = PushbulletSmsSender(); // Removed - SMS sending via Pushbullet disabled
  ComposeMessageType _messageType = ComposeMessageType.email;
  
  // Listeners for text field changes
  late final VoidCallback _toFieldListener;
  late final VoidCallback _bodyFieldListener;

  bool get _isEmailMessage => _messageType == ComposeMessageType.email;

  /// Check if send button should be disabled
  bool get _isSendDisabled {
    if (_isSending) return true;
    
    final toEmpty = _toController.text.trim().isEmpty;
    final bodyEmpty = _bodyController.text.trim().isEmpty;
    
    // For SMS and WhatsApp, both recipient and body are required
    if (_messageType == ComposeMessageType.sms || _messageType == ComposeMessageType.whatsapp) {
      return toEmpty || bodyEmpty;
    }
    
    // For email, only recipient is required (body can be empty)
    return toEmpty;
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    if (draft != null) {
      _toController.text = draft.to;
      _subjectController.text = draft.subject;
      _bodyController.text = draft.body;
      _attachments.addAll(draft.attachments);
      _forwardedAttachments.addAll(draft.forwardedAttachments);
      _originalPreviewHtml = draft.originalHtml;
      _originalPlainText = draft.originalPlain;
    } else {
      _toController.text = widget.to ?? '';
      _subjectController.text = widget.subject ?? '';
      _bodyController.text = widget.body ?? '';
    }

    if (widget.originalMessage != null) {
      final original = widget.originalMessage!;
      if (SmsMessageConverter.isSmsMessage(original)) {
        _messageType = ComposeMessageType.sms;
      } else if (WhatsAppMessageConverter.isWhatsAppMessage(original)) {
        _messageType = ComposeMessageType.whatsapp;
      }
    }

    // Add listeners to update UI when text changes
    _toFieldListener = () {
      if (mounted) setState(() {});
    };
    _bodyFieldListener = () {
      if (mounted) setState(() {});
    };
    _toController.addListener(_toFieldListener);
    _bodyController.addListener(_bodyFieldListener);

    if (_shouldFetchOriginalContent) {
      unawaited(_loadOriginalMessageContent());
    }
  }

  @override
  void dispose() {
    _toController.removeListener(_toFieldListener);
    _bodyController.removeListener(_bodyFieldListener);
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    for (final tempPath in _tempAttachmentPaths) {
      try {
        final file = File(tempPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // ignore cleanup errors
      }
    }
    _tempAttachmentPaths.clear();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (!_formKey.currentState!.validate()) return;
    switch (_messageType) {
      case ComposeMessageType.email:
        await _sendEmail();
        break;
      case ComposeMessageType.sms:
        await _sendSms();
        break;
      case ComposeMessageType.whatsapp:
        await _sendWhatsApp();
        break;
    }
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    if (_shouldFetchOriginalContent) {
      await _loadOriginalMessageContent();
    }

    setState(() {
      _isSending = true;
    });

    try {
      final syncService = GmailSyncService();
      
      // Materialize attachments (handles both file paths and in-memory bytes)
      // Create GmailAttachmentData directly to preserve original filenames
      final attachmentData = <GmailAttachmentData>[];
      debugPrint('[Compose] Processing ${_attachments.length} attachment(s) for mode: ${widget.mode}');
      for (final platformFile in _attachments) {
        final file = await _ensureAttachmentFile(platformFile);
        if (file != null) {
          final bytes = await file.readAsBytes();
          // Use the original filename from platformFile.name, not the temp file path
          final originalFilename = platformFile.name.isNotEmpty 
              ? platformFile.name 
              : file.path.split(Platform.pathSeparator).last;
          final mimeType = _determineMimeTypeFromFilename(originalFilename);
          attachmentData.add(
            GmailAttachmentData(
              filename: originalFilename,
              mimeType: mimeType,
              bytes: bytes,
            ),
          );
          debugPrint('[Compose] Added attachment: $originalFilename (${bytes.length} bytes)');
        } else {
          debugPrint('[Compose] Failed to ensure file for attachment: ${platformFile.name}');
        }
      }
      debugPrint('[Compose] Total attachmentData: ${attachmentData.length}');
      
      String? threadId;
      String? inReplyTo;
      List<String>? references;

      if (widget.mode == ComposeEmailMode.reply || widget.mode == ComposeEmailMode.replyAll) {
        final original = widget.originalMessage;
        if (original != null) {
          if (original.threadId.isNotEmpty) {
            threadId = original.threadId;
          }

          final replyContext = await syncService.fetchReplyContext(widget.accountId, original.id);
          final headerMessageId = replyContext?.messageIdHeader;
          if (replyContext != null) {
            final refs = List<String>.from(replyContext.references);
            if (headerMessageId != null && headerMessageId.isNotEmpty) {
              inReplyTo = headerMessageId;
              if (!refs.contains(headerMessageId)) {
                refs.add(headerMessageId);
              }
            }
            if (refs.isNotEmpty) {
              references = refs;
            }
          }
        }
      }

      String plainBody = _bodyController.text.trim();
      String? htmlBodyForSend;
      List<GmailAttachmentData> forwardedAttachments = [];

      if (_isForwardLike) {
        final originalPlain = (_originalPlainText ?? widget.originalMessage?.snippet ?? '').trimRight();
        final originalHtml = _originalPreviewHtml ?? _wrapPlainAsHtml(originalPlain);
        htmlBodyForSend = _wrapHtmlDocument(
          _buildForwardHtmlBody(_bodyController.text, originalHtml),
        );
        plainBody = _buildForwardPlainBody(_bodyController.text, originalPlain);
        forwardedAttachments = List<GmailAttachmentData>.from(_forwardedAttachments);
        debugPrint('[Compose] Forward: ${forwardedAttachments.length} forwarded attachment(s), ${attachmentData.length} new attachment(s)');
      } else if (_isReplyLike) {
        debugPrint('[Compose] Reply: ${attachmentData.length} new attachment(s)');
        final originalPlain = (_originalPlainText ?? widget.originalMessage?.snippet ?? '').trimRight();
        final originalHtml = _originalPreviewHtml ?? _wrapPlainAsHtml(originalPlain);
        htmlBodyForSend = _wrapHtmlDocument(
          _buildReplyHtmlBody(_bodyController.text, originalHtml),
        );
        plainBody = _buildReplyPlainBody(_bodyController.text, originalPlain);
      } else if (plainBody.isNotEmpty) {
        htmlBodyForSend = _wrapHtmlDocument(_wrapPlainAsHtml(plainBody));
      }
      
      debugPrint('[Compose] Sending email with: attachmentData=${attachmentData.length}, forwardedAttachments=${forwardedAttachments.length}, mode=${widget.mode}');
      final success = await syncService.sendEmail(
        widget.accountId,
        to: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        body: plainBody,
        htmlBody: htmlBodyForSend,
        attachments: null, // Pass null since we're using attachmentData
        attachmentData: attachmentData.isEmpty ? null : attachmentData, // Pass null if empty, not empty list
        forwardedAttachments: forwardedAttachments.isEmpty ? null : forwardedAttachments, // Pass null if empty, not empty list
        inReplyTo: inReplyTo,
        references: references,
        threadId: threadId,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email sent successfully')),
        );
        Navigator.of(context).pop(const ComposeDialogResult(ComposeDialogResultType.sent));
      } else {
        setState(() {
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send email. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send email: $e')),
      );
    }
  }

  Future<void> _sendSms() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Extract phone number from "to" field
    final toText = _toController.text.trim();
    if (toText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a phone number')),
        );
      }
      return;
    }
    
    // Extract phone number (remove any email-like formatting)
    final phone = toText.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid phone number')),
        );
      }
      return;
    }
    
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message body is required for SMS')),
        );
      }
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final companionSmsService = CompanionSmsService();
      final success = await companionSmsService.sendSms(phone, body);
      
      if (!mounted) return;
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS sent successfully')),
        );
        Navigator.of(context).pop(const ComposeDialogResult(ComposeDialogResultType.sent));
      } else {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send SMS. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send SMS: $e')),
      );
    }
  }

  Future<void> _sendWhatsApp() async {
    if (!_formKey.currentState!.validate()) {
      debugPrint('[Compose] WhatsApp send: Form validation failed');
      return;
    }
    final phone = _preparePhoneForWhatsApp(_toController.text);
    final body = _bodyController.text.trim();
    debugPrint('[Compose] WhatsApp send: phone="$phone", body length=${body.length}');
    
    if (phone.isEmpty) {
      debugPrint('[Compose] WhatsApp send: Phone number is empty after preparation');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }
    if (body.isEmpty) {
      debugPrint('[Compose] WhatsApp send: Message body is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message body is required for WhatsApp')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final encodedMessage = Uri.encodeComponent(body);
      final deepLink = Uri.parse('whatsapp://send?phone=$phone&text=$encodedMessage');
      debugPrint('[Compose] WhatsApp send: Attempting deep link: $deepLink');
      
      bool launched = false;
      if (await canLaunchUrl(deepLink)) {
        debugPrint('[Compose] WhatsApp send: canLaunchUrl returned true, launching...');
        launched = await launchUrl(deepLink, mode: LaunchMode.externalApplication);
        debugPrint('[Compose] WhatsApp send: launchUrl returned: $launched');
      } else {
        debugPrint('[Compose] WhatsApp send: canLaunchUrl returned false, trying web URL fallback...');
      }
      
      if (!launched) {
        final waMe = Uri.parse('https://wa.me/$phone?text=$encodedMessage');
        debugPrint('[Compose] WhatsApp send: Attempting web URL fallback: $waMe');
        try {
          // Try to launch the web URL even if canLaunchUrl returns false
          // (browser might still be able to open it)
          launched = await launchUrl(waMe, mode: LaunchMode.externalApplication);
          debugPrint('[Compose] WhatsApp send: Web URL launch returned: $launched');
        } catch (urlError) {
          debugPrint('[Compose] WhatsApp send: Error launching web URL: $urlError');
          // Re-throw with more context
          throw StateError('Failed to open WhatsApp web link. Please check your browser settings. Error: $urlError');
        }
      }
      
      if (!launched) {
        debugPrint('[Compose] WhatsApp send: Both deep link and web URL failed');
        throw StateError('Unable to open WhatsApp. On Windows, this will open WhatsApp Web in your browser. Please ensure your default browser is configured correctly.');
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening WhatsApp...')),
      );
      Navigator.of(context).pop(const ComposeDialogResult(ComposeDialogResultType.sent));
    } catch (e, stackTrace) {
      debugPrint('[Compose] WhatsApp send error: $e');
      debugPrint('[Compose] WhatsApp send stack trace: $stackTrace');
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to launch WhatsApp: $e')),
      );
    }
  }

  Future<void> _handleAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _attachments.addAll(result.files);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking files: $e')),
      );
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _openAttachmentPreview(PlatformFile attachment) async {
    try {
      final file = await _ensureAttachmentFile(attachment);
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot locate attachment "${attachment.name}".')),
        );
        return;
      }

      // Check preference for PDF viewer
      // Check both extension and filename for PDF (filename check handles cases where file path doesn't have extension)
      final extension = path.extension(file.path).toLowerCase();
      final isPdf = extension == '.pdf' || attachment.name.toLowerCase().endsWith('.pdf');
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

  Future<File?> _ensureAttachmentFile(PlatformFile attachment) async {
    if (attachment.path != null && attachment.path!.isNotEmpty) {
      return File(attachment.path!);
    }
    final bytes = attachment.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final attachmentsDir = Directory(path.join(tempDir.path, 'compose_attachments'));
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final sanitizedName = _sanitizeFilename(
      attachment.name.isNotEmpty ? attachment.name : 'attachment',
    );
    final tempFile = File(
      path.join(
        attachmentsDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_$sanitizedName',
      ),
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    _tempAttachmentPaths.add(tempFile.path);
    return tempFile;
  }

  String _sanitizeFilename(String name) {
    final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'attachment' : sanitized;
  }

  String _determineMimeTypeFromFilename(String filename) {
    final extension = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  bool get _isReplyLike =>
      widget.mode == ComposeEmailMode.reply || widget.mode == ComposeEmailMode.replyAll;

  bool get _isForwardLike => widget.mode == ComposeEmailMode.forward;

  String get _dialogTitle {
    switch (_messageType) {
      case ComposeMessageType.email:
        return 'Compose Email';
      case ComposeMessageType.sms:
        return 'Compose SMS';
      case ComposeMessageType.whatsapp:
        return 'Compose WhatsApp';
    }
  }

  bool get _shouldShowOriginalPreview =>
      _isEmailMessage && widget.originalMessage != null && widget.mode != ComposeEmailMode.newEmail;

  bool get _shouldFetchOriginalContent =>
      _isEmailMessage &&
      widget.originalMessage != null &&
      widget.mode != ComposeEmailMode.newEmail &&
      (_originalPreviewHtml == null ||
          _originalPlainText == null ||
          (_isForwardLike && _forwardedAttachments.isEmpty));

  Future<void> _loadOriginalMessageContent() async {
    final original = widget.originalMessage;
    if (original == null) return;
    setState(() {
      _isOriginalLoading = true;
    });
    try {
      final content = await GmailSyncService().fetchOriginalMessageContent(
        widget.accountId,
        original.id,
      );
      if (!mounted) return;
      final html = content?.htmlBody;
      final plain = content?.plainBody ??
          (html != null ? _htmlToPlainText(html) : (original.snippet ?? ''));
      if (content?.attachments.isNotEmpty ?? false) {
        _forwardedAttachments
          ..clear()
          ..addAll(content!.attachments);
      }
      setState(() {
        _originalPreviewHtml = html ?? _wrapPlainAsHtml(plain);
        _originalPlainText = plain;
        _isOriginalLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _originalPreviewHtml = null;
        _originalPlainText = widget.originalMessage?.snippet ?? '';
        _isOriginalLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load original message: $e')),
      );
    }
  }

  String _wrapHtmlDocument(String body) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;font-size:14px;line-height:1.5;color:#1a1a1a;">
$body
</body>
</html>
''';
  }

  String _wrapPlainAsHtml(String text) {
    final escaped = _escapeHtml(text);
    return '<pre style="white-space: pre-wrap; font-family: inherit;">$escaped</pre>';
  }

  String _convertUserTextToHtml(String text) {
    final escaped = _escapeHtml(text.trim());
    if (escaped.isEmpty) return '';
    return escaped.replaceAll('\n', '<br>');
  }

  String _buildForwardHtmlBody(String userText, String originalHtml) {
    final userSection = userText.trim().isNotEmpty
        ? '<div style="margin-bottom:16px;">${_convertUserTextToHtml(userText)}</div>'
        : '';
    final header = _forwardHeaderHtml();
    return '''
<div style="font-size:14px; color:#1a1a1a;">
  $userSection
  <div style="border-left:3px solid #d4d4d4; padding-left:12px;">
    $header
    <div style="margin-top:12px;">
      $originalHtml
    </div>
  </div>
</div>
''';
  }

  String _forwardHeaderHtml() {
    final original = widget.originalMessage;
    if (original == null) return '<div><strong>Forwarded message</strong></div>';
    final formattedDate = _previewDateFormat.format(original.internalDate.toLocal());
    final buffer = StringBuffer()
      ..writeln('<div><strong>--- Forwarded message ---</strong></div>')
      ..writeln('<div><strong>From:</strong> ${_escapeHtml(original.from)}</div>')
      ..writeln('<div><strong>To:</strong> ${_escapeHtml(original.to)}</div>')
      ..writeln('<div><strong>Date:</strong> ${_escapeHtml(formattedDate)}</div>')
      ..writeln('<div><strong>Subject:</strong> ${_escapeHtml(original.subject)}</div>');
    return buffer.toString();
  }

  String _buildForwardPlainBody(String userText, String originalPlain) {
    final buffer = StringBuffer();
    final trimmedUser = userText.trim();
    if (trimmedUser.isNotEmpty) {
      buffer.writeln(trimmedUser);
      buffer.writeln();
    }
    buffer.writeln('--- Forwarded message ---');
    final original = widget.originalMessage;
    if (original != null) {
      final formattedDate = _previewDateFormat.format(original.internalDate.toLocal());
      buffer.writeln('From: ${original.from}');
      buffer.writeln('To: ${original.to}');
      buffer.writeln('Date: $formattedDate');
      buffer.writeln('Subject: ${original.subject}');
      buffer.writeln();
    }
    buffer.writeln(originalPlain);
    return buffer.toString().trimRight();
  }

  String _buildReplyHtmlBody(String userText, String originalHtml) {
    final userSection = userText.trim().isNotEmpty
        ? '<div style="margin-bottom:16px;">${_convertUserTextToHtml(userText)}</div>'
        : '';
    final header = _replyHeaderHtml();
    return '''
<div style="font-size:14px; color:#1a1a1a;">
  $userSection
  <div style="border-left:3px solid #d4d4d4; padding-left:12px;">
    $header
    <div style="margin-top:12px;">
      $originalHtml
    </div>
  </div>
</div>
''';
  }

  String _replyHeaderHtml() {
    final original = widget.originalMessage;
    if (original == null) return '';
    final formattedDate = _previewDateFormat.format(original.internalDate.toLocal());
    final senderName = _escapeHtml(_extractSenderName(original.from));
    return '<div>On $formattedDate, $senderName wrote:</div>';
  }

  String _buildReplyPlainBody(String userText, String originalPlain) {
    final buffer = StringBuffer();
    final trimmedUser = userText.trim();
    if (trimmedUser.isNotEmpty) {
      buffer.writeln(trimmedUser);
      buffer.writeln();
    }
    final original = widget.originalMessage;
    if (original != null) {
      final formattedDate = _previewDateFormat.format(original.internalDate.toLocal());
      final senderName = _extractSenderName(original.from);
      buffer.writeln('On $formattedDate, $senderName wrote:');
      buffer.writeln();
    }
    buffer.writeln(originalPlain);
    return buffer.toString().trimRight();
  }

  Widget _buildToField(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: ContactAutocompleteField(
        controller: _toController,
        messageType: _messageType,
        decoration: InputDecoration(
          labelText: 'Recipient',
          border: InputBorder.none,
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        style: const TextStyle(fontSize: 14),
        enabled: !_isSending,
        validator: _validateRecipient,
        onTapContactPicker: _isSending ? null : _openContactPicker,
      ),
    );
  }

  Widget _buildSubjectField(ThemeData theme) {
    if (!_isEmailMessage) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: TextFormField(
        controller: _subjectController,
        decoration: InputDecoration(
          labelText: 'Subject',
          border: InputBorder.none,
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildMessageTypeSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SegmentedButton<ComposeMessageType>(
        segments: const [
          ButtonSegment(
            value: ComposeMessageType.email,
            label: Text('Email'),
            icon: Icon(Icons.email_outlined),
          ),
          ButtonSegment(
            value: ComposeMessageType.sms,
            label: Text('SMS'),
            icon: Icon(Icons.sms_outlined),
          ),
          ButtonSegment(
            value: ComposeMessageType.whatsapp,
            label: Text('WhatsApp'),
            icon: Icon(Icons.chat_outlined),
          ),
        ],
        selected: <ComposeMessageType>{_messageType},
        onSelectionChanged: (selection) {
          final next = selection.first;
          if (next == _messageType) return;
          setState(() {
            _messageType = next;
            if (!_isEmailMessage) {
              _attachments.clear();
              _forwardedAttachments.clear();
            }
          });
          _formKey.currentState?.validate();
        },
      ),
    );
  }

  Widget _buildAttachmentChips(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_attachments.length, (index) {
          final attachment = _attachments[index];
          return InputChip(
            avatar: Icon(
              Icons.attach_file,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                attachment.name,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onPressed: () => _openAttachmentPreview(attachment),
            onDeleted: () => _removeAttachment(index),
            deleteIcon: Icon(
              Icons.close,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }),
      ),
    );
  }

  Future<void> _openContactPicker() async {
    final value = await ContactPickerDialog.show(
      context: context,
      messageType: _messageType,
    );
    if (value != null && value.isNotEmpty) {
      setState(() {
        _toController.text = value;
      });
      _formKey.currentState?.validate();
    }
  }

  String? _validateRecipient(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Please enter a recipient';
    }
    if (_isEmailMessage) {
      if (!trimmed.contains('@')) {
        return 'Enter a valid email address';
      }
    } else {
      final digits = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
      if (digits.isEmpty) {
        return 'Enter a valid phone number';
      }
    }
    return null;
  }


  String _preparePhoneForWhatsApp(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    
    // Check if it starts with +
    final hasPlus = trimmed.startsWith('+');
    
    // Extract all digits
    var digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digits.isEmpty) return '';
    
    // Handle leading 00 (international prefix that should become +)
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
      // After removing 00, add + for international format
      return '+$digits';
    }
    
    // If it had +, add it back (WhatsApp requires + for international format)
    if (hasPlus) {
      return '+$digits';
    }
    
    // For numbers without +, assume they need country code
    // Return digits only - WhatsApp web (wa.me) can handle both formats
    return digits;
  }

  void _handleViewOriginal() {
    final draft = _collectDraftState();
    Navigator.of(context).pop(ComposeDialogResult(ComposeDialogResultType.viewOriginal, draft));
  }

  ComposeDraftState _collectDraftState() {
    return ComposeDraftState(
      to: _toController.text.trim(),
      subject: _subjectController.text.trim(),
      body: _bodyController.text,
      attachments: List<PlatformFile>.from(_attachments),
      forwardedAttachments: List<GmailAttachmentData>.from(_forwardedAttachments),
      originalHtml: _originalPreviewHtml,
      originalPlain: _originalPlainText,
    );
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
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

  String _extractEmail(String from) {
    final regex = RegExp(r'<([^>]+)>');
    final match = regex.firstMatch(from);
    if (match != null) return match.group(1)!.trim();
    if (from.contains('@')) return from.trim();
    return '';
  }

  String _htmlToPlainText(String text) {
    var result = text.replaceAll('\r\n', '\n');
    result = result.replaceAll(
      RegExp(r'<(script|style|head|meta|link)[^>]*?>.*?<\s*/\s*\1\s*>',
          caseSensitive: false, dotAll: true, multiLine: true),
      '\n',
    );
    result = result.replaceAll(
      RegExp(r'<(script|style|head|meta|link)[^>]*?>',
          caseSensitive: false, dotAll: true, multiLine: true),
      '\n',
    );
    result = result.replaceAll(
      RegExp(r'<!--.*?-->', caseSensitive: false, dotAll: true, multiLine: true),
      '\n',
    );
    result = result.replaceAll(
      RegExp(r'<!\[CDATA\[.*?\]\]>', caseSensitive: false, dotAll: true, multiLine: true),
      '\n',
    );
    result = result.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    result = result.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    result = result.replaceAll(RegExp(r'<div[^>]*>', caseSensitive: false), '\n');
    result = result.replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');
    result = result.replaceAll(RegExp(r'<[^>]+>'), '');
    result = result.replaceAll('&nbsp;', ' ');
    result = result.replaceAll('&amp;', '&');
    result = result.replaceAll('&lt;', '<');
    result = result.replaceAll('&gt;', '>');
    result = result.replaceAll('&quot;', '"');
    result = result.replaceAll('&#39;', "'");
    result = result.replaceAll('&#x27;', "'");
    result = result.replaceAll('&apos;', "'");
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: _dialogTitle,
      bodyPadding: EdgeInsets.zero,
      headerActions: [
        IconButton(
          tooltip: 'Manage contacts',
          icon: const Icon(Icons.manage_accounts_outlined, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _isSending ? null : () => ContactsManagementDialog.show(context),
        ),
        if (_shouldShowOriginalPreview && _isEmailMessage)
          IconButton(
            tooltip: _isOriginalLoading ? 'Loading original email...' : 'View original email',
            icon: const Icon(Icons.remove_red_eye_outlined, size: 20),
            color: theme.appBarTheme.foregroundColor,
            onPressed: _isOriginalLoading || _isSending ? null : _handleViewOriginal,
          ),
        if (_isEmailMessage)
          IconButton(
            tooltip: 'Attachments',
            icon: const Icon(Icons.attach_file, size: 20),
            color: theme.appBarTheme.foregroundColor,
            onPressed: _isSending ? null : _handleAttachments,
          ),
        IconButton(
          tooltip: 'Send',
          icon: const Icon(Icons.send, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _isSendDisabled ? null : _handleSend,
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMessageTypeSelector(theme),
            _buildToField(theme),
            _buildSubjectField(theme),
            if (_isEmailMessage && _attachments.isNotEmpty) _buildAttachmentChips(theme),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  controller: _bodyController,
                  decoration: InputDecoration(
                    hintText: 'Compose your message...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ),
            if (_isSending)
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sending...',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

