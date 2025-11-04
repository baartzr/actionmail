import 'package:flutter/material.dart';
import 'package:actionmail/constants/app_constants.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/data/repositories/message_repository.dart';

/// Gmail folder navigation tree for desktop left panel
class GmailFolderTree extends StatefulWidget {
  final String selectedFolder;
  final ValueChanged<String> onFolderSelected;
  final void Function(String folderId, MessageIndex message)? onEmailDropped;
  final bool isViewingLocalFolder; // Whether we're currently viewing local folder emails
  final String? accountId; // Account ID for fetching unread counts

  const GmailFolderTree({
    super.key,
    required this.selectedFolder,
    required this.onFolderSelected,
    this.onEmailDropped,
    this.isViewingLocalFolder = false,
    this.accountId,
  });

  @override
  State<GmailFolderTree> createState() => _GmailFolderTreeState();
}

class _GmailFolderTreeState extends State<GmailFolderTree> {
  MessageIndex? _draggedMessage;
  final MessageRepository _messageRepo = MessageRepository();
  Map<String, int> _unreadCounts = {};
  bool _isLoadingCounts = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadCounts();
  }

  @override
  void didUpdateWidget(GmailFolderTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload counts if account changed
    if (oldWidget.accountId != widget.accountId) {
      _loadUnreadCounts();
    }
  }

  Future<void> _loadUnreadCounts() async {
    if (widget.accountId == null) return;
    setState(() => _isLoadingCounts = true);
    try {
      final counts = <String, int>{};
      final folders = ['INBOX', 'SENT', 'ARCHIVE', 'TRASH', 'SPAM'];
      for (final folder in folders) {
        final count = await _messageRepo.getUnreadCountByFolder(widget.accountId!, folder);
        counts[folder] = count;
      }
      if (mounted) {
        setState(() {
          _unreadCounts = counts;
          _isLoadingCounts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCounts = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          right: BorderSide(
            color: cs.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.email, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gmail Folders',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Folder list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _buildFolderItem(
                  context: context,
                  icon: Icons.inbox,
                  label: AppConstants.folderDisplayNames[AppConstants.folderInbox] ?? AppConstants.folderInbox,
                  folderId: AppConstants.folderInbox,
                  unreadCount: _unreadCounts[AppConstants.folderInbox] ?? 0,
                  draggedMessage: _draggedMessage,
                  onDragStart: (message) => setState(() => _draggedMessage = message),
                  onDragEnd: () => setState(() => _draggedMessage = null),
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.send,
                  label: AppConstants.folderDisplayNames[AppConstants.folderSent] ?? AppConstants.folderSent,
                  folderId: AppConstants.folderSent,
                  unreadCount: _unreadCounts[AppConstants.folderSent] ?? 0,
                  draggedMessage: _draggedMessage,
                  onDragStart: (message) => setState(() => _draggedMessage = message),
                  onDragEnd: () => setState(() => _draggedMessage = null),
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.archive,
                  label: AppConstants.folderDisplayNames[AppConstants.folderArchive] ?? AppConstants.folderArchive,
                  folderId: AppConstants.folderArchive,
                  unreadCount: _unreadCounts[AppConstants.folderArchive] ?? 0,
                  draggedMessage: _draggedMessage,
                  onDragStart: (message) => setState(() => _draggedMessage = message),
                  onDragEnd: () => setState(() => _draggedMessage = null),
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.delete,
                  label: AppConstants.folderDisplayNames[AppConstants.folderTrash] ?? AppConstants.folderTrash,
                  folderId: AppConstants.folderTrash,
                  unreadCount: _unreadCounts[AppConstants.folderTrash] ?? 0,
                  draggedMessage: _draggedMessage,
                  onDragStart: (message) => setState(() => _draggedMessage = message),
                  onDragEnd: () => setState(() => _draggedMessage = null),
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.block,
                  label: AppConstants.folderDisplayNames[AppConstants.folderSpam] ?? AppConstants.folderSpam,
                  folderId: AppConstants.folderSpam,
                  unreadCount: _unreadCounts[AppConstants.folderSpam] ?? 0,
                  draggedMessage: _draggedMessage,
                  onDragStart: (message) => setState(() => _draggedMessage = message),
                  onDragEnd: () => setState(() => _draggedMessage = null),
                ),
                // Add helper text when dragging - below folders
                if (_draggedMessage != null)
                  Builder(
                    builder: (context) {
                      // If viewing local folders, all emails are local
                      if (widget.isViewingLocalFolder) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: cs.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Local emails can only be moved to local folders',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        // We're viewing Gmail folders, show allowed folders for Gmail emails
                        final sourceFolder = _draggedMessage!.folderLabel.toUpperCase();
                        final gmailFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];
                        final isGmailEmail = gmailFolders.contains(sourceFolder);
                        
                        if (isGmailEmail) {
                          // Show which folders ARE allowed for Gmail emails
                          final allowedFolders = _getAllowedFoldersForSource(sourceFolder, _draggedMessage!.prevFolderLabel);
                          
                          if (allowedFolders.isNotEmpty) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 16, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Can move to: ${allowedFolders.map((f) => AppConstants.folderDisplayNames[f] ?? f).join(', ')}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String folderId,
    required int unreadCount,
    MessageIndex? draggedMessage,
    void Function(MessageIndex)? onDragStart,
    void Function()? onDragEnd,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSelected = widget.selectedFolder == folderId;
    // Use the same dark teal as the appbar for selected folder
    const selectedFolderColor = Color(0xFF00695C); // darkTeal from theme
    // Nice contrasting green for allowed drag folders (color set directly in builder)
    
    // Get folder-specific icon color
    Color getFolderIconColor() {
      if (isSelected) return selectedFolderColor;
      
      // Default colors for each folder type when not selected
      switch (folderId.toUpperCase()) {
        case 'INBOX':
          return const Color(0xFF1976D2); // Blue for Inbox
        case 'SENT':
          return const Color(0xFF388E3C); // Green for Sent
        case 'ARCHIVE':
          return const Color(0xFFF57C00); // Orange for Archive
        case 'TRASH':
          return const Color(0xFFD32F2F); // Red for Trash
        case 'SPAM':
          return const Color(0xFFE64A19); // Deep Orange for Spam
        default:
          return cs.onSurfaceVariant;
      }
    }

    Widget folderContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onFolderSelected(folderId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? selectedFolderColor.withValues(alpha: 0.3)
                : Colors.transparent,
            border: isSelected
                ? Border(
                    left: BorderSide(
                      color: selectedFolderColor,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: getFolderIconColor(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSelected ? selectedFolderColor : cs.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unreadCount > 0)
                Text(
                  '($unreadCount)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSelected ? selectedFolderColor : cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Wrap in DragTarget if onEmailDropped is provided
    if (widget.onEmailDropped == null) {
      return folderContent;
    }

    return DragTarget<MessageIndex>(
      onWillAcceptWithDetails: (details) {
        onDragStart?.call(details.data);
        return _onWillAccept(details.data, folderId);
      },
      onLeave: (data) {
        onDragEnd?.call();
      },
      onAcceptWithDetails: (details) {
        onDragEnd?.call();
        // Check if this folder is allowed for the source email
        // For local folder emails, reject all Gmail folders
        // For Gmail emails, check allowed folders based on swipe actions
        final sourceFolder = details.data.folderLabel.toUpperCase();
        final targetFolder = folderId.toUpperCase();
        
        // Local folder emails cannot be dragged to Gmail folders
        // We'll determine this by checking if the folderLabel is a Gmail folder
        final gmailFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];
        final isGmailFolder = gmailFolders.contains(sourceFolder);
        
        if (!isGmailFolder) {
          // This is a local folder email - reject Gmail folder drops
          return;
        }
        
        // For Gmail emails, check allowed folders
        final allowedFolders = _getAllowedFoldersForSource(sourceFolder, details.data.prevFolderLabel);
        if (!allowedFolders.contains(targetFolder)) {
          // This folder is not allowed for this source email
          return;
        }
        
        // Valid drop - handle it
        widget.onEmailDropped!(folderId, details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final isAccepted = candidateData.isNotEmpty;
        
        // Determine if this folder should be shown as allowed based on dragged message
        bool showAsAllowed = false;
        if (draggedMessage != null) {
          // If we're viewing local folders, all emails are local and cannot be dragged to Gmail
          if (widget.isViewingLocalFolder) {
            showAsAllowed = false; // No Gmail folders allowed for local emails
          } else {
            // We're viewing Gmail folders, so check if this email can be dragged to this folder
            final sourceFolder = draggedMessage.folderLabel.toUpperCase();
            final targetFolder = folderId.toUpperCase();
            
            // Check if this is a Gmail email by verifying folderLabel is a Gmail folder
            final gmailFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];
            final isGmailEmail = gmailFolders.contains(sourceFolder);
            
            if (isGmailEmail) {
              // Gmail email: check if this folder IS allowed
              final allowedFolders = _getAllowedFoldersForSource(sourceFolder, draggedMessage.prevFolderLabel);
              showAsAllowed = allowedFolders.contains(targetFolder);
            }
            // Non-Gmail emails (shouldn't happen when viewing Gmail folders, but just in case)
          }
        }
        
        // Use teal for selected, green for allowed drag, or transparent
        Color? backgroundColor;
        if (isSelected) {
          // Selected folder uses dark teal
          backgroundColor = const Color(0xFF00695C).withValues(alpha: 0.3);
        } else if (isAccepted) {
          // Currently being dragged over - use slightly brighter green
          backgroundColor = const Color(0xFF66BB6A).withValues(alpha: 0.4);
        } else if (showAsAllowed) {
          // Allowed drag folder - use contrasting green
          backgroundColor = const Color(0xFF66BB6A).withValues(alpha: 0.3);
        }
        
        return Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: folderContent,
        );
      },
    );
  }

  bool _onWillAccept(MessageIndex? data, String folderId) {
    if (data == null) return false;
    
    // If we're viewing local folders, all emails are local and cannot be dragged to Gmail
    if (widget.isViewingLocalFolder) {
      return false; // Reject all local folder emails
    }
    
    final sourceFolder = data.folderLabel.toUpperCase();
    final targetFolder = folderId.toUpperCase();
    
    // Check if this is a Gmail email by verifying folderLabel is a Gmail folder
    final gmailFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];
    final isGmailFolder = gmailFolders.contains(sourceFolder);
    
    if (!isGmailFolder) {
      return false; // Reject non-Gmail emails (shouldn't happen when viewing Gmail folders)
    }
    
    // Check if this folder is allowed for the source
    final allowedFolders = _getAllowedFoldersForSource(sourceFolder, data.prevFolderLabel);
    return allowedFolders.contains(targetFolder);
  }

  /// Get allowed Gmail folders based on swipe actions for a source folder
  List<String> _getAllowedFoldersForSource(String sourceFolder, String? prevFolderLabel) {
    final allowed = <String>[];
    
    // Right swipe (left actions): Restore, Move to Inbox
    if (sourceFolder == 'TRASH' || sourceFolder == 'ARCHIVE') {
      // Restore goes to prevFolderLabel
      if (prevFolderLabel != null) {
        allowed.add(prevFolderLabel.toUpperCase());
      }
    }
    if (sourceFolder == 'SPAM') {
      allowed.add('INBOX'); // Move to Inbox
    }
    
    // Left swipe (right actions): Trash, Archive
    // Archive only applies to INBOX and SPAM (not SENT)
    if (sourceFolder == 'INBOX') {
      allowed.add('TRASH');
      allowed.add('ARCHIVE');
    }
    if (sourceFolder == 'SENT') {
      allowed.add('TRASH'); // SENT can only be trashed, not archived
    }
    if (sourceFolder == 'SPAM') {
      allowed.add('TRASH');
      allowed.add('ARCHIVE');
    }
    if (sourceFolder == 'ARCHIVE') {
      allowed.add('TRASH');
    }
    
    return allowed;
  }
}

