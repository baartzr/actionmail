import 'package:flutter/material.dart';
import 'package:domail/features/home/presentation/widgets/grid_email_list_mockup.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/data/test_data/sample_emails.dart';

/// Demo screen showcasing the grid-style email list mockup
/// 
/// This demonstrates what a grid-style desktop email list could look like.
/// To use this, navigate to this screen from your app.
class GridEmailListDemo extends StatefulWidget {
  const GridEmailListDemo({super.key});

  @override
  State<GridEmailListDemo> createState() => _GridEmailListDemoState();
}

class _GridEmailListDemoState extends State<GridEmailListDemo> {
  String _selectedFolder = 'INBOX';
  Set<String> _activeFilters = {};
  List<MessageIndex> _allEmails = [];
  List<MessageIndex> _filteredEmails = [];
  bool _isLocalFolder = false;
  final List<String> _localFolders = ['Finance', 'Projects', 'Personal'];

  @override
  void initState() {
    super.initState();
    _loadSampleEmails();
  }

  void _loadSampleEmails() {
    // Generate sample emails
    final sampleEmails = SampleEmails.generateSampleEmails('demo-account');
    
    // Add some variety to the sample emails
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Add more sample emails with different properties
    final additionalEmails = [
      MessageIndex(
        id: 'msg-011',
        threadId: 'thread-011',
        accountId: 'demo-account',
        internalDate: today.subtract(const Duration(hours: 2)),
        from: 'Sarah Johnson <sarah@company.com>',
        to: 'user@example.com',
        subject: 'Meeting tomorrow at 2pm',
        snippet: 'Just a reminder about our meeting tomorrow afternoon.',
        localTagPersonal: 'Business',
        hasAction: true,
        actionDate: DateTime(now.year, now.month, now.day + 1),
        actionInsightText: 'Meeting scheduled for tomorrow at 2pm',
        isRead: false,
        isStarred: true,
      ),
      MessageIndex(
        id: 'msg-012',
        threadId: 'thread-012',
        accountId: 'demo-account',
        internalDate: today.subtract(const Duration(days: 1)),
        from: 'mom@family.com',
        to: 'user@example.com',
        subject: 'Family dinner this weekend',
        snippet: 'Don\'t forget about dinner on Saturday!',
        localTagPersonal: 'Personal',
        isRead: true,
        isStarred: false,
      ),
      MessageIndex(
        id: 'msg-013',
        threadId: 'thread-013',
        accountId: 'demo-account',
        internalDate: today.subtract(const Duration(days: 4)),
        from: 'support@software.com',
        to: 'user@example.com',
        subject: 'Your subscription expires soon',
        snippet: 'Your annual subscription will expire on May 1st.',
        hasAction: true,
        actionDate: DateTime(now.year, 5, 1),
        actionInsightText: 'Subscription expires on May 1st',
        isRead: false,
        hasAttachments: true,
      ),
      MessageIndex(
        id: 'msg-014',
        threadId: 'thread-014',
        accountId: 'demo-account',
        internalDate: today.subtract(const Duration(hours: 6)),
        from: 'team@project.com',
        to: 'user@example.com',
        subject: 'Project update - Q2 goals',
        snippet: 'Here\'s the latest update on our Q2 project goals and milestones.',
        localTagPersonal: 'Business',
        isRead: false,
        hasAttachments: true,
        isStarred: true,
      ),
      MessageIndex(
        id: 'msg-015',
        threadId: 'thread-015',
        accountId: 'demo-account',
        internalDate: today.subtract(const Duration(days: 2)),
        from: 'friend@email.com',
        to: 'user@example.com',
        subject: 'Weekend plans?',
        snippet: 'Want to grab coffee this weekend?',
        localTagPersonal: 'Personal',
        isRead: true,
      ),
    ];
    
    setState(() {
      _allEmails = [...sampleEmails, ...additionalEmails];
      _applyFilter();
    });
  }

  void _applyFilter() {
    List<MessageIndex> filtered = List.from(_allEmails);
    
    // Apply folder filter
    filtered = filtered.where((email) => email.folderLabel == _selectedFolder).toList();
    
    // Apply active filters
    if (_activeFilters.isNotEmpty) {
      if (_activeFilters.contains('unread')) {
        filtered = filtered.where((email) => !email.isRead).toList();
      }
      if (_activeFilters.contains('starred')) {
        filtered = filtered.where((email) => email.isStarred).toList();
      }
      if (_activeFilters.contains('action')) {
        filtered = filtered.where((email) => email.hasAction).toList();
      }
      if (_activeFilters.contains('personal')) {
        filtered = filtered.where((email) => email.localTagPersonal == 'Personal').toList();
      }
      if (_activeFilters.contains('business')) {
        filtered = filtered.where((email) => email.localTagPersonal == 'Business').toList();
      }
      if (_activeFilters.contains('attachments')) {
        filtered = filtered.where((email) => email.hasAttachments).toList();
      }
      if (_activeFilters.contains('subscriptions')) {
        filtered = filtered.where((email) => email.subsLocal).toList();
      }
      if (_activeFilters.contains('shopping')) {
        filtered = filtered.where((email) => email.shoppingLocal).toList();
      }
      if (_activeFilters.contains('action_today')) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        filtered = filtered.where((email) {
          return email.actionDate != null && 
                 email.actionDate!.year == todayDate.year &&
                 email.actionDate!.month == todayDate.month &&
                 email.actionDate!.day == todayDate.day;
        }).toList();
      }
      if (_activeFilters.contains('action_upcoming')) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        filtered = filtered.where((email) {
          return email.actionDate != null && email.actionDate!.isAfter(todayDate);
        }).toList();
      }
      if (_activeFilters.contains('action_overdue')) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        filtered = filtered.where((email) {
          return email.actionDate != null && email.actionDate!.isBefore(todayDate);
        }).toList();
      }
      if (_activeFilters.contains('action_possible')) {
        filtered = filtered.where((email) {
          return email.hasAction && email.actionDate == null;
        }).toList();
      }
    }
    
    setState(() {
      _filteredEmails = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GridEmailListMockup(
      emails: _filteredEmails,
      selectedFolder: _selectedFolder,
      selectedAccountEmail: 'user@example.com',
      availableAccounts: ['user@example.com', 'work@example.com', 'personal@example.com'],
      localFolders: _localFolders,
      isLocalFolder: _isLocalFolder,
      activeFilters: _activeFilters,
      onFolderChanged: (folder) {
        if (folder != null) {
          setState(() {
            _selectedFolder = folder;
          });
          _applyFilter();
        }
      },
      onAccountChanged: (account) {
        // Handle account change
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Switched to: $account')),
        );
      },
      onToggleLocalFolderView: () {
        setState(() {
          _isLocalFolder = !_isLocalFolder;
          if (_isLocalFolder && _localFolders.isNotEmpty) {
            _selectedFolder = _localFolders.first;
          } else {
            _selectedFolder = 'INBOX';
          }
        });
        _applyFilter();
      },
      onEmailTap: (email) {
        // Show email details
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(email.subject),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('From: ${email.from}'),
                  const SizedBox(height: 8),
                  Text('To: ${email.to}'),
                  const SizedBox(height: 8),
                  Text('Date: ${email.internalDate}'),
                  if (email.snippet != null) ...[
                    const SizedBox(height: 8),
                    Text('Snippet: ${email.snippet}'),
                  ],
                  if (email.hasAction) ...[
                    const SizedBox(height: 8),
                    Text('Action: ${email.actionInsightText ?? "No text"}'),
                    if (email.actionDate != null)
                      Text('Action Date: ${email.actionDate}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
      onEmailAction: (email) {
        // Handle action button tap
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action for: ${email.subject}'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      onPersonalBusinessToggle: (email) {
        // Toggle between Personal, Business, and None
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Toggle Personal/Business for: ${email.subject}'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      onStarToggle: (email) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Toggle star for: ${email.subject}'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      onTrash: (email) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trash: ${email.subject}'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      onArchive: (email) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive: ${email.subject}'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      onMoveToLocalFolder: (email) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Move to local folder: ${email.subject}'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      onFiltersChanged: (filters) {
        setState(() {
          _activeFilters = filters;
        });
        _applyFilter();
      },
    );
  }
}

