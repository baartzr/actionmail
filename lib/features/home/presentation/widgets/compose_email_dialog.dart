import 'dart:io';
import 'package:flutter/material.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:actionmail/data/models/message_index.dart';

/// Dialog for composing new emails
class ComposeEmailDialog extends StatefulWidget {
  final String? to;
  final String? subject;
  final String? body;
  final String accountId;
  final MessageIndex? originalMessage; // Original email when replying/forwarding

  const ComposeEmailDialog({
    super.key,
    this.to,
    this.subject,
    this.body,
    required this.accountId,
    this.originalMessage,
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
  bool _showOriginalEmail = false;

  @override
  void initState() {
    super.initState();
    _toController.text = widget.to ?? '';
    _subjectController.text = widget.subject ?? '';
    _bodyController.text = widget.body ?? '';
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSending = true;
    });

    try {
      final syncService = GmailSyncService();
      
      // Convert PlatformFile to File for attachments
      final attachmentFiles = _attachments
          .where((pf) => pf.path != null)
          .map((pf) => File(pf.path!))
          .toList();
      
      final success = await syncService.sendEmail(
        widget.accountId,
        to: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
        attachments: attachmentFiles,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email sent successfully')),
        );
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: 'Compose Email',
      bodyPadding: EdgeInsets.zero,
      headerActions: [
        if (widget.originalMessage != null)
          IconButton(
            tooltip: _showOriginalEmail ? 'Hide original email' : 'Show original email',
            icon: Icon(_showOriginalEmail ? Icons.visibility_off : Icons.visibility, size: 20),
            color: theme.appBarTheme.foregroundColor,
            onPressed: () {
              setState(() {
                _showOriginalEmail = !_showOriginalEmail;
              });
            },
          ),
        IconButton(
          tooltip: 'Attachments',
          icon: const Icon(Icons.attach_file, size: 20),
          color: theme.appBarTheme.foregroundColor,
          onPressed: _handleAttachments,
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
            // To field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.2),
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
                style: TextStyle(fontSize: 14),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a recipient';
                  }
                  return null;
                },
              ),
            ),
            // Subject field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.2),
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
                style: TextStyle(fontSize: 14),
              ),
            ),
            // Attachments list
            if (_attachments.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_attachments.length, (index) {
                    final attachment = _attachments[index];
                    return Chip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.attach_file,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              attachment.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _removeAttachment(index),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    );
                  }),
                ),
              ),
            // Body field and original email (if replying/forwarding)
            Expanded(
              child: _showOriginalEmail && widget.originalMessage != null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Compose area (left)
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: TextFormField(
                              controller: _bodyController,
                              decoration: InputDecoration(
                                hintText: 'Compose your message...',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                                  fontSize: 14,
                                ),
                              ),
                              style: TextStyle(fontSize: 14),
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                            ),
                          ),
                        ),
                        // Divider
                        Container(
                          width: 1,
                          color: theme.colorScheme.outline.withOpacity(0.2),
                        ),
                        // Original email (right)
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Original Message',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'From: ${widget.originalMessage!.from}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    'Subject: ${widget.originalMessage!.subject}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (widget.originalMessage!.snippet != null)
                                    Text(
                                      widget.originalMessage!.snippet!,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _bodyController,
                        decoration: InputDecoration(
                          hintText: 'Compose your message...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                        style: TextStyle(fontSize: 14),
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

