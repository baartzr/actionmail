import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dialog for viewing email content in a webview
class EmailViewerDialog extends StatefulWidget {
  final MessageIndex message;
  final String accountId;

  const EmailViewerDialog({
    super.key,
    required this.message,
    required this.accountId,
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

  @override
  void initState() {
    super.initState();
    _loadEmailBody();
  }

  Future<void> _loadEmailBody() async {
    try {
      final account = await GoogleAuthService().ensureValidAccessToken(widget.accountId);
      final accessToken = account?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'No access token available';
          _isLoading = false;
        });
        return;
      }

      final resp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/${widget.message.id}?format=full'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (resp.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _error = 'Failed to load email: ${resp.statusCode}';
          _isLoading = false;
        });
        return;
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
        _isLoading = false;
      });
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: 'Email',
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
                        ? InAppWebView(
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
                          )
                        : const Center(child: Text('No content available')),
    );
  }
}

