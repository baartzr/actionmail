import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'package:actionmail/services/local_folders/local_folder_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:open_file/open_file.dart';
import 'dart:io';

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
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;
  bool _isFullscreen = false;
  List<AttachmentInfo> _attachments = [];

  @override
  void initState() {
    super.initState();
    _loadEmailBody();
    // Mark as read when dialog opens
    if (!widget.message.isRead && widget.onMarkRead != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onMarkRead!();
      });
    }
  }

  Future<void> _loadEmailBody() async {
    try {
      // If viewing from local folder, load from saved file
      if (widget.localFolderName != null) {
        final folderService = LocalFolderService();
        final body = await folderService.loadEmailBody(widget.localFolderName!, widget.message.id);
        if (!mounted) return;
        if (body != null) {
          debugPrint('[EmailViewer] Email body loaded from local folder, loading attachments...');
          debugPrint('[EmailViewer] Message hasAttachments flag: ${widget.message.hasAttachments}');
          
          // Load attachments from local folder
          final localAttachments = await folderService.loadAttachments(widget.localFolderName!, widget.message.id);
          debugPrint('[EmailViewer] loadAttachments returned ${localAttachments.length} attachments');
          
          final attachments = localAttachments.map((att) {
            debugPrint('[EmailViewer] Converting attachment: ${att['filename']}');
            return AttachmentInfo(
              filename: att['filename'] as String,
              mimeType: att['mimeType'] as String,
              attachmentId: att['attachmentId'] as String,
              size: att['size'] as int?,
            );
          }).toList();
          
          debugPrint('[EmailViewer] Created ${attachments.length} AttachmentInfo objects');
          
          setState(() {
            _htmlContent = body;
            _attachments = attachments;
            _isLoading = false;
          });
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
      debugPrint('[EmailViewer] Starting to load email ${widget.message.id} from Gmail API');
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
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/${widget.message.id}?format=full'),
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
      final attachments = <AttachmentInfo>[];
      void extractAttachments(dynamic part) {
        if (part is! Map<String, dynamic>) return;
        
        final mimeType = (part['mimeType'] as String? ?? '').toLowerCase();
        var filename = part['filename'] as String?;
        final body = part['body'] as Map<String, dynamic>?;
        final attachmentId = body?['attachmentId'] as String?;
        final size = body?['size'] as int?;
        final headers = (part['headers'] as List<dynamic>?) ?? [];
        
        // Must have attachmentId — this marks it as an actual attachment part
        if (attachmentId == null || attachmentId.isEmpty) {
          // Recursively check nested parts even if this part isn't an attachment
          final parts = part['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final p in parts) {
              extractAttachments(p);
            }
          }
          return;
        }
        
        // Build header map for easier lookup
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
        
        // Skip inline parts unless explicitly marked as attachment
        if (dispLower.contains('inline') && !dispLower.contains('attachment')) {
          // Skip - recursively check nested parts
          final parts = part['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final p in parts) {
              extractAttachments(p);
            }
          }
          return;
        }
        
        // Skip if has Content-ID (inline images)
        if (cid.isNotEmpty) {
          // Skip - recursively check nested parts
          final parts = part['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final p in parts) {
              extractAttachments(p);
            }
          }
          return;
        }
        
        // Skip image/* types (unless explicitly marked as attachment)
        if (mimeType.startsWith('image/')) {
          // Only include images if explicitly marked as attachment
          if (!dispLower.contains('attachment')) {
            // Skip - recursively check nested parts
            final parts = part['parts'] as List<dynamic>?;
            if (parts != null) {
              for (final p in parts) {
                extractAttachments(p);
              }
            }
            return;
          }
        }
        
        // Determine the filename - extract from headers if not present
        if (filename == null || filename.isEmpty) {
          // Try to extract from Content-Disposition header
          final matchFilename = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disp);
          if (matchFilename != null) {
            filename = matchFilename.group(1)?.trim();
          } else {
            // Try Content-Type header
            final contentType = headerMap['content-type'] ?? '';
            final matchName = RegExp(r'name="?([^";]+)"?', caseSensitive: false).firstMatch(contentType);
            if (matchName != null) {
              filename = matchName.group(1)?.trim();
            }
          }
        }
        
        // Must have filename to be considered an attachment
        if (filename == null || filename.isEmpty) {
          // Skip - recursively check nested parts
          final parts = part['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final p in parts) {
              extractAttachments(p);
            }
          }
          return;
        }
        
        // This is a real attachment
        attachments.add(AttachmentInfo(
          filename: filename,
          mimeType: mimeType,
          attachmentId: attachmentId,
          size: size,
        ));
        
        // Recursively check nested parts
        final parts = part['parts'] as List<dynamic>?;
        if (parts != null) {
          for (final p in parts) {
            extractAttachments(p);
          }
        }
      }
      
      extractAttachments(payload ?? {});

      // Prefer HTML over plain text
      final bodyContent = htmlBody ?? plainBody ?? widget.message.snippet ?? 'No content available';
      final bodyHtml = htmlBody != null 
          ? bodyContent 
          : '<pre style="white-space: pre-wrap; font-family: inherit;">${_escapeHtml(bodyContent)}</pre>';

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
    <h2>${_escapeHtml(widget.message.subject)}</h2>
    <div class="meta">
      <div><strong>From:</strong> ${_escapeHtml(widget.message.from)}</div>
      <div><strong>To:</strong> ${_escapeHtml(widget.message.to)}</div>
      <div><strong>Date:</strong> ${_formatDate(widget.message.internalDate)}</div>
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
      });
      
      // Debug: Print attachment count
      debugPrint('[EmailViewer] Attachment extraction complete for message ${widget.message.id}');
      debugPrint('[EmailViewer]   hasAttachments flag: ${widget.message.hasAttachments}');
      debugPrint('[EmailViewer]   Found ${attachments.length} real attachments');
      if (attachments.isNotEmpty) {
        for (final att in attachments) {
          debugPrint('[EmailViewer]     - ${att.filename} (${att.mimeType}, ${att.size ?? 0} bytes, attachmentId: ${att.attachmentId})');
        }
      } else if (widget.message.hasAttachments) {
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

  Widget _buildAttachmentChip(AttachmentInfo attachment) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(
          Icons.insert_drive_file,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        label: Text(
          attachment.filename,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: () => _downloadAttachment(attachment),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
    );
  }

  Future<void> _downloadAttachment(AttachmentInfo attachment) async {
    try {
      // If viewing from local folder, open the file directly
      if (widget.localFolderName != null) {
        final folderService = LocalFolderService();
        final localPath = await folderService.getAttachmentPath(
          widget.localFolderName!,
          widget.message.id,
          attachment.attachmentId,
        );
        
        if (localPath != null) {
          // Open the file directly from local folder
          final result = await OpenFile.open(localPath);
          if (!mounted) return;
          
          if (result.type != ResultType.done) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opened: ${attachment.filename}')),
            );
          }
          return;
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Attachment file not found: ${attachment.filename}')),
          );
          return;
        }
      }
      
      // Otherwise download from Gmail API
      final account = await GoogleAuthService().ensureValidAccessToken(widget.accountId);
      final accessToken = account?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No access token available')),
        );
        return;
      }

      // Show loading indicator
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading ${attachment.filename}...')),
      );

      // Download attachment from Gmail API
      final resp = await http.get(
        Uri.parse(
          'https://gmail.googleapis.com/gmail/v1/users/me/messages/${widget.message.id}/attachments/${attachment.attachmentId}',
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (resp.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download attachment: ${resp.statusCode}')),
        );
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final fileData = data['data'] as String?;
      if (fileData == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attachment data received')),
        );
        return;
      }

      // Decode base64url
      final bytes = base64Url.decode(fileData.replaceAll('-', '+').replaceAll('_', '/'));

      // Save to downloads directory
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access downloads directory')),
        );
        return;
      }

      final filePath = path.join(directory.path, attachment.filename);
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      // Open the file
      final result = await OpenFile.open(filePath);
      if (!mounted) return;

      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded: ${attachment.filename}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading attachment: $e')),
      );
    }
  }

  void _handleReply() {
    final to = _extractEmail(widget.message.from);
    final subject = widget.message.subject.startsWith('Re:') 
        ? widget.message.subject 
        : 'Re: ${widget.message.subject}';
    showDialog(
      context: context,
      builder: (ctx) => ComposeEmailDialog(
        to: to,
        subject: subject,
        accountId: widget.accountId,
        originalMessage: widget.message,
      ),
    );
  }

  void _handleReplyAll() {
    final to = _extractEmail(widget.message.from);
    // TODO: Extract all recipients from the email
    final subject = widget.message.subject.startsWith('Re:') 
        ? widget.message.subject 
        : 'Re: ${widget.message.subject}';
    showDialog(
      context: context,
      builder: (ctx) => ComposeEmailDialog(
        to: to,
        subject: subject,
        accountId: widget.accountId,
        originalMessage: widget.message,
      ),
    );
  }

  void _handleForward() {
    final subject = widget.message.subject.startsWith('Fwd:') 
        ? widget.message.subject 
        : 'Fwd: ${widget.message.subject}';
    showDialog(
      context: context,
      builder: (ctx) => ComposeEmailDialog(
        subject: subject,
        body: '\n\n--- Forwarded message ---\nFrom: ${widget.message.from}\nDate: ${_formatDate(widget.message.internalDate)}\nSubject: ${widget.message.subject}\n\n',
        accountId: widget.accountId,
        originalMessage: widget.message,
      ),
    );
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: 'Email',
      fullscreen: _isFullscreen,
      headerActions: [
        IconButton(
          tooltip: 'Reply',
          icon: const Icon(Icons.reply, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _handleReply,
        ),
        IconButton(
          tooltip: 'Reply All',
          icon: const Icon(Icons.reply_all, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _handleReplyAll,
        ),
        IconButton(
          tooltip: 'Forward',
          icon: const Icon(Icons.forward, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _handleForward,
        ),
        IconButton(
          tooltip: _isFullscreen ? 'Exit Full Screen' : 'Full Screen',
          icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _toggleFullscreen,
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
                    : _htmlContent != null
                        ? Column(
                            children: [
                              // Attachments section
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
                              // Email content
                              Expanded(
                                child: InAppWebView(
                                  initialData: InAppWebViewInitialData(data: _htmlContent!, mimeType: 'text/html', encoding: 'utf8'),
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
                                    // Controller stored for potential future use
                                    // ignore: unused_local_variable
                                    _webViewController = controller;
                                  },
                                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                                    // Open external links in default browser
                                    final url = navigationAction.request.url;
                                    if (url != null && (url.scheme == 'http' || url.scheme == 'https')) {
                                      // Allow navigation within the email HTML (like images, anchors)
                                      // but we could block external links if desired
                                      return NavigationActionPolicy.ALLOW;
                                    }
                                    return NavigationActionPolicy.CANCEL;
                                  },
                                ),
                              ),
                            ],
                          )
                        : const Center(child: Text('No content available')),
    );
  }
}

