import 'package:flutter/material.dart';
// import 'package:flutter/gestures.dart'; // unused
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/shared/widgets/personal_business_filter.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:actionmail/services/actions/ml_action_extractor.dart';
import 'package:actionmail/services/actions/action_extractor.dart';
import 'package:actionmail/services/sync/firebase_sync_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActionsSummaryWindow extends ConsumerStatefulWidget {
  const ActionsSummaryWindow({super.key});

  @override
  ConsumerState<ActionsSummaryWindow> createState() => _ActionsSummaryWindowState();
}

class _ActionsSummaryWindowState extends ConsumerState<ActionsSummaryWindow> {
  List<GoogleAccount> _accounts = [];
  Map<String, List<MessageIndex>> _accountMessages = {};
  Map<String, List<MessageIndex>> _allAccountMessages = {}; // Store all messages before filtering
  bool _loading = true;
  // Track completion state for each message (true = complete, false = incomplete)
  final Map<String, bool> _completionState = {};
  final FirebaseSyncService _firebaseSync = FirebaseSyncService();
  // Personal/Business filter state
  String? _selectedLocalState;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    final svc = GoogleAuthService();
    final accounts = await svc.loadAccounts();
    final repo = MessageRepository();
    
    // Get the active account ID from preferences
    final prefs = await SharedPreferences.getInstance();
    final activeAccountId = prefs.getString('lastActiveAccountId');
    
    // Sort accounts to show active account first
    final sortedAccounts = List<GoogleAccount>.from(accounts);
    if (activeAccountId != null) {
      sortedAccounts.sort((a, b) {
        if (a.id == activeAccountId) return -1;
        if (b.id == activeAccountId) return 1;
        return 0;
      });
    }
    
    final Map<String, List<MessageIndex>> messagesByAccount = {};
    
    for (final account in sortedAccounts) {
      final messages = await repo.getByFolder(account.id, 'INBOX');
      // Filter to only messages with actions, excluding completed ones
      final actions = messages.where((m) {
        // Exclude completed actions (using actionComplete field)
        if (m.actionComplete) {
          return false;
        }
        // Include if has action date or action text
        return m.actionDate != null || 
               (m.actionInsightText != null && m.actionInsightText!.isNotEmpty);
      }).toList();
      
      // Initialize completion state for each message based on actionComplete field
      for (final msg in actions) {
        _completionState[msg.id] = msg.actionComplete;
      }
      
      if (actions.isNotEmpty) {
        messagesByAccount[account.id] = actions;
      }
    }
    
    if (mounted) {
      setState(() {
        _accounts = sortedAccounts;
        _allAccountMessages = messagesByAccount;
        _accountMessages = _applyLocalStateFilter(messagesByAccount);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppWindowDialog(
      title: 'Actions Summary',
      size: AppWindowSize.large,
      bodyPadding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PersonalBusinessFilter(
            selected: _selectedLocalState,
            onChanged: (v) {
              setState(() {
                _selectedLocalState = v;
                _accountMessages = _applyLocalStateFilter(_allAccountMessages);
              });
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _accountMessages.isEmpty
                    ? const Center(child: Text('No actions found'))
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _accounts
                              .where((account) => _accountMessages.containsKey(account.id))
                              .map((account) => _buildAccountSection(account))
                              .toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Map<String, List<MessageIndex>> _applyLocalStateFilter(Map<String, List<MessageIndex>> messagesByAccount) {
    if (_selectedLocalState == null) {
      return messagesByAccount;
    }
    
    final filtered = <String, List<MessageIndex>>{};
    for (final entry in messagesByAccount.entries) {
      final filteredMessages = entry.value.where((m) => m.localTagPersonal == _selectedLocalState).toList();
      if (filteredMessages.isNotEmpty) {
        filtered[entry.key] = filteredMessages;
      }
    }
    return filtered;
  }


  Widget _buildAccountSection(GoogleAccount account) {
    final messages = _accountMessages[account.id] ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Categorize actions
    final overdue = <MessageIndex>[];
    final todayList = <MessageIndex>[];
    final upcoming = <MessageIndex>[];

    for (final msg in messages) {
      if (msg.actionDate == null) continue;
      final actionDate = DateTime(
        msg.actionDate!.year,
        msg.actionDate!.month,
        msg.actionDate!.day,
      );
      
      if (actionDate.isBefore(today)) {
        overdue.add(msg);
      } else if (actionDate == today) {
        todayList.add(msg);
      } else {
        upcoming.add(msg);
      }
    }

    // Sort by date
    overdue.sort((a, b) => (a.actionDate ?? DateTime(2000)).compareTo(b.actionDate ?? DateTime(2000)));
    todayList.sort((a, b) => (a.actionDate ?? DateTime(2000)).compareTo(b.actionDate ?? DateTime(2000)));
    upcoming.sort((a, b) => (a.actionDate ?? DateTime(2000)).compareTo(b.actionDate ?? DateTime(2000)));

    final totalActions = overdue.length + todayList.length + upcoming.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account header with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.account_circle,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.email,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$totalActions ${totalActions == 1 ? 'action' : 'actions'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
          
              // Overdue section
              if (overdue.isNotEmpty) ...[
                _buildSectionHeader(
                  'Overdue actions',
                  Icons.warning_amber_rounded,
                  Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 8),
                ...overdue.map((msg) => _buildActionItem(msg, Theme.of(context).colorScheme.errorContainer)),
                const SizedBox(height: 12),
              ],
              
              // Today section
              if (todayList.isNotEmpty) ...[
                _buildSectionHeader(
                  'Action today ${todayList.length}',
                  Icons.today,
                  Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                ...todayList.map((msg) => _buildActionItem(msg, Theme.of(context).colorScheme.primaryContainer)),
                const SizedBox(height: 12),
              ],
              
              // Upcoming section
              if (upcoming.isNotEmpty) ...[
                _buildSectionHeader(
                  'Upcoming actions',
                  Icons.upcoming,
                  Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 8),
                ...upcoming.map((msg) => _buildActionItem(msg, Theme.of(context).colorScheme.secondaryContainer)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildActionItem(MessageIndex message, Color backgroundColor) {
    final dateFmt = DateFormat('dd MMM');
    final actionDateStr = message.actionDate != null 
        ? dateFmt.format(message.actionDate!.toLocal())
        : '';
    
    final isComplete = _completionState[message.id] ?? false;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: GestureDetector(
        onTap: () => _openEditActionDialog(message),
        onDoubleTap: () => _openEmail(message),
        child: Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: backgroundColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Email subject
                    Row(
                      children: [
                        Icon(
                          Icons.email_outlined,
                          size: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            message.subject,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Action text (Edit text removed)
                    Row(
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            [
                              if (message.actionInsightText != null && message.actionInsightText!.isNotEmpty)
                                message.actionInsightText!,
                              if (actionDateStr.isNotEmpty)
                                actionDateStr,
                            ].where((s) => s.isNotEmpty).join(' • '),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Complete button - minus icon changes to tick when complete
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _toggleComplete(message),
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    child: Icon(
                      isComplete ? Icons.check : Icons.remove,
                      size: 20,
                      color: isComplete 
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEmail(MessageIndex message) async {
    await showDialog(
      context: context,
      builder: (ctx) => EmailViewerDialog(
        message: message,
        accountId: message.accountId,
      ),
    );
  }

  Future<void> _toggleComplete(MessageIndex message) async {
    final newComplete = !message.actionComplete;
    
    // Update local state and message object in both _allAccountMessages and _accountMessages
    setState(() {
      _completionState[message.id] = newComplete;
      // Update the message object in _allAccountMessages (source of truth)
      for (final accountId in _allAccountMessages.keys) {
        final messages = _allAccountMessages[accountId];
        final index = messages?.indexWhere((m) => m.id == message.id);
        if (index != null && index >= 0 && messages != null) {
          _allAccountMessages[accountId] = List.from(messages);
          _allAccountMessages[accountId]![index] = messages[index].copyWith(
            actionComplete: newComplete,
          );
        }
      }
      // Reapply filter to update _accountMessages
      _accountMessages = _applyLocalStateFilter(_allAccountMessages);
    });
    
    // Persist to database
    await MessageRepository().updateAction(message.id, message.actionDate, message.actionInsightText, null, newComplete);
    
    // Update provider state
    ref.read(emailListProvider.notifier).setAction(
      message.id,
      message.actionDate,
      message.actionInsightText,
      actionComplete: newComplete,
    );
    
    // Sync to Firebase if enabled
    final syncEnabled = await _firebaseSync.isSyncEnabled();
    if (syncEnabled) {
      // Check if actionComplete actually changed
      final currentComplete = message.actionComplete;
      if (currentComplete != newComplete) {
        await _firebaseSync.syncEmailMeta(
          message.id,
          actionDate: message.actionDate,
          actionInsightText: message.actionInsightText,
          actionComplete: newComplete,
        );
      }
    }
  }

  Future<void> _openEditActionDialog(MessageIndex message) async {
    DateTime? tempDate = message.actionDate ?? DateTime.now();
    // Use action text as-is (no need to remove "(Complete)" since we use boolean field now)
    final existingText = message.actionInsightText ?? '';
    final textController = TextEditingController(text: existingText);

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sbSet) {
            return AlertDialog(
              title: const Text('Edit Action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        sbSet(() {
                          tempDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(tempDate != null
                        ? DateFormat('dd-MMM, y').format(tempDate!)
                        : 'Pick date'),
                  ),
                ],
              ),
              actions: [
                // Remove button (only show if action exists)
                if (message.actionDate != null || message.actionInsightText != null)
                  TextButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remove Action'),
                          content: const Text('Are you sure you want to remove this action?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(ctx).colorScheme.error,
                                foregroundColor: Theme.of(ctx).colorScheme.onError,
                              ),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        if (!context.mounted) return;
                        Navigator.of(context).pop({
                          'actionDate': null,
                          'actionText': null,
                        });
                      }
                    },
                    icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                    label: Text(
                      'Remove',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'actionDate': tempDate,
                      'actionText': textController.text.trim().isEmpty ? null : textController.text.trim(),
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final actionDate = result['actionDate'] as DateTime?;
      final actionText = result['actionText'] as String?;
      
      // Capture original detected action for feedback
      final originalAction = message.actionDate != null || message.actionInsightText != null
          ? ActionResult(
              actionDate: message.actionDate ?? DateTime.now(),
              confidence: message.actionConfidence ?? 0.0,
              insightText: message.actionInsightText ?? '',
            )
          : null;
      
      // Preserve actionComplete when editing (don't reset it)
      final currentComplete = message.actionComplete;
      
      // Persist to database
      await MessageRepository().updateAction(message.id, actionDate, actionText, null, currentComplete);
      // Update in-memory state
      ref.read(emailListProvider.notifier).setAction(
        message.id,
        actionDate,
        actionText,
        actionComplete: currentComplete,
      );
      
      // Sync to Firebase if enabled
      final syncEnabled = await _firebaseSync.isSyncEnabled();
      if (syncEnabled) {
        // Get current message to check if action actually changed
        final currentDate = message.actionDate;
        final currentText = message.actionInsightText;
        if (currentDate != actionDate || currentText != actionText || currentComplete != message.actionComplete) {
          await _firebaseSync.syncEmailMeta(
            message.id,
            actionDate: actionDate,
            actionInsightText: actionText,
            actionComplete: currentComplete,
          );
        }
      }
      
      // Record feedback for ML training
      final userAction = actionDate != null || actionText != null
          ? ActionResult(
              actionDate: actionDate ?? DateTime.now(),
              confidence: 1.0, // User-provided actions have max confidence
              insightText: actionText ?? '',
            )
          : null;
      
      // Determine feedback type
      FeedbackType? feedbackType = _determineFeedbackType(originalAction, userAction);
      
      if (feedbackType != null) {
        await MLActionExtractor.recordFeedback(
          messageId: message.id,
          subject: message.subject,
          snippet: message.snippet ?? '',
          detectedResult: originalAction,
          userCorrectedResult: userAction,
          feedbackType: feedbackType,
        );
      }
      
      // Update message in _allAccountMessages and reapply filter
      for (final accountId in _allAccountMessages.keys) {
        final messages = _allAccountMessages[accountId];
        final index = messages?.indexWhere((m) => m.id == message.id);
        if (index != null && index >= 0 && messages != null) {
          _allAccountMessages[accountId] = List.from(messages);
          _allAccountMessages[accountId]![index] = messages[index].copyWith(
            actionDate: actionDate,
            actionInsightText: actionText,
            actionComplete: currentComplete, // Preserve completion state
          );
        }
      }
      // Preserve completion state when editing
      setState(() {
        _completionState[message.id] = currentComplete;
        // Reapply filter to update _accountMessages
        _accountMessages = _applyLocalStateFilter(_allAccountMessages);
      });
    }
  }
  
  /// Determine feedback type based on original and user actions
  FeedbackType? _determineFeedbackType(ActionResult? original, ActionResult? user) {
    if (original == null && user == null) return null; // No change
    if (original == null && user != null) return FeedbackType.falseNegative; // User added action
    if (original != null && user == null) return FeedbackType.falsePositive; // User removed action
    
    // Both exist - check if they're different
    final originalStr = '${original!.actionDate.toIso8601String()}_${original.insightText}';
    final userStr = '${user!.actionDate.toIso8601String()}_${user.insightText}';
    
    if (originalStr == userStr) {
      return FeedbackType.confirmation; // User confirmed
    } else {
      return FeedbackType.correction; // User corrected
    }
  }
}

