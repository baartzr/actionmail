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

    if (_shouldFetchOriginalContent) {
      unawaited(_loadOriginalMessageContent());
    }
  }

  @override
  void dispose() {
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
      final attachmentFiles = <File>[];
      for (final platformFile in _attachments) {
        final file = await _ensureAttachmentFile(platformFile);
        if (file != null) {
          attachmentFiles.add(file);
        }
      }
      
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
      } else if (_isReplyLike) {
        final originalPlain = (_originalPlainText ?? widget.originalMessage?.snippet ?? '').trimRight();
        final originalHtml = _originalPreviewHtml ?? _wrapPlainAsHtml(originalPlain);
        htmlBodyForSend = _wrapHtmlDocument(
          _buildReplyHtmlBody(_bodyController.text, originalHtml),
        );
        plainBody = _buildReplyPlainBody(_bodyController.text, originalPlain);
      } else if (plainBody.isNotEmpty) {
        htmlBodyForSend = _wrapHtmlDocument(_wrapPlainAsHtml(plainBody));
      }
      
      final success = await syncService.sendEmail(
        widget.accountId,
        to: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        body: plainBody,
        htmlBody: htmlBodyForSend,
        attachments: attachmentFiles,
        forwardedAttachments: forwardedAttachments,
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

      final extension = path.extension(file.path).toLowerCase();
      if (extension == '.pdf') {
        if (!mounted) return;
        await PdfViewerWindow.open(
          context,
          filePath: file.path,
        );
      } else {
        final result = await OpenFile.open(file.path);
        if (!mounted) return;
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open file: ${result.message}')),
          );
        }
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

  bool get _isReplyLike =>
      widget.mode == ComposeEmailMode.reply || widget.mode == ComposeEmailMode.replyAll;

  bool get _isForwardLike => widget.mode == ComposeEmailMode.forward;

  bool get _shouldShowOriginalPreview =>
      widget.originalMessage != null && widget.mode != ComposeEmailMode.newEmail;

  bool get _shouldFetchOriginalContent =>
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
      child: TextFormField(
        controller: _toController,
        decoration: InputDecoration(
          labelText: 'To',
          border: InputBorder.none,
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        style: const TextStyle(fontSize: 14),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter a recipient';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSubjectField(ThemeData theme) {
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
      title: 'Compose Email',
      bodyPadding: EdgeInsets.zero,
      headerActions: [
        if (_shouldShowOriginalPreview)
          IconButton(
            tooltip: _isOriginalLoading ? 'Loading original email...' : 'View original email',
            icon: const Icon(Icons.remove_red_eye_outlined, size: 20),
            color: theme.appBarTheme.foregroundColor,
            onPressed: _isOriginalLoading || _isSending ? null : _handleViewOriginal,
          ),
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
          onPressed: _isSending ? null : _sendEmail,
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToField(theme),
            _buildSubjectField(theme),
            if (_attachments.isNotEmpty) _buildAttachmentChips(theme),
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

