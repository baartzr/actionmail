import 'package:flutter/material.dart';
// import 'package:flutter/gestures.dart'; // unused
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:domail/shared/widgets/personal_business_filter.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:domail/services/actions/ml_action_extractor.dart';
import 'package:domail/services/actions/action_extractor.dart';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domail/features/home/presentation/widgets/action_edit_dialog.dart';

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

  GoogleAccount? _findAccount(String accountId) {
    for (final account in _accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

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
      // Only load messages from INBOX folder
      final messages = await repo.getByFolder(account.id, 'INBOX');
      // Filter to only messages with incomplete actions
      // Also explicitly filter by folderLabel to ensure only INBOX (case-insensitive)
      final actions = messages.where((m) {
        // Ensure message is actually in INBOX folder (case-insensitive check)
        if (m.folderLabel.toUpperCase() != 'INBOX') {
          return false;
        }
        // Only include messages that have an action
        if (!m.hasAction) {
          return false;
        }
        // Exclude completed actions (using actionComplete field)
        if (m.actionComplete) {
          return false;
        }
        return true;
      }).toList();
      
      // Initialize completion state for each message based on actionComplete field
      for (final msg in actions) {
        _completionState[msg.id] = msg.actionComplete;
      }
      
      messagesByAccount[account.id] = actions;
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
      if (msg.actionDate == null) {
        continue;
      }
      
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
              if (totalActions == 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No pending actions for this account.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
          
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
      barrierDismissible: false,
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
    final accountEmail = _findAccount(message.accountId)?.email;
    if (syncEnabled && accountEmail != null) {
      // Check if actionComplete actually changed
      final currentComplete = message.actionComplete;
      if (currentComplete != newComplete) {
        await _firebaseSync.syncEmailMeta(
          message.id,
          actionDate: message.actionDate,
          actionInsightText: message.actionInsightText,
          actionComplete: newComplete,
          accountEmail: accountEmail,
        );
      }
    }
  }

  Future<void> _openEditActionDialog(MessageIndex message) async {
    final result = await ActionEditDialog.show(
      context,
      initialDate: message.actionDate,
      initialText: message.actionInsightText,
      initialComplete: message.actionComplete,
      allowRemove: message.hasAction,
    );

    if (result != null) {
      final removed = result.removed;
      final actionDate = removed ? null : result.actionDate;
      final actionText = removed
          ? null
          : (result.actionText != null && result.actionText!.isNotEmpty ? result.actionText : null);
      // Use actionInsightText only as source of truth
      final hasActionNow = !removed && (actionText != null && actionText.isNotEmpty);
      final bool? markedComplete = result.actionComplete;
 
      // Capture original detected action for feedback
      final originalAction = message.hasAction
          ? ActionResult(
              actionDate: message.actionDate ?? DateTime.now(),
              confidence: message.actionConfidence ?? 0.0,
              insightText: message.actionInsightText ?? '',
            )
          : null;
       
      // Preserve actionComplete when editing (don't reset it)
      final currentComplete = hasActionNow
          ? (markedComplete ?? message.actionComplete)
          : false;
 
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
      final accountEmail = _findAccount(message.accountId)?.email;
      if (syncEnabled && accountEmail != null) {
        // Get current message to check if action actually changed
        final currentDate = message.actionDate;
        final currentText = message.actionInsightText;
        if (currentDate != actionDate || currentText != actionText || currentComplete != message.actionComplete || !hasActionNow) {
          await _firebaseSync.syncEmailMeta(
            message.id,
            actionDate: hasActionNow ? actionDate : null,
            actionInsightText: hasActionNow ? actionText : null,
            actionComplete: hasActionNow ? currentComplete : null,
            accountEmail: accountEmail,
            clearAction: !hasActionNow,
          );
        }
      }
       
      // Record feedback for ML training
      final userAction = (actionDate != null || (actionText != null && actionText.isNotEmpty)) && !removed
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
      
      if (removed || !hasActionNow) {
        setState(() {
          _completionState.remove(message.id);
          final updatedAll = <String, List<MessageIndex>>{};
          _allAccountMessages.forEach((accountId, messages) {
            final updatedList = messages.where((m) => m.id != message.id).toList();
            if (updatedList.isNotEmpty) {
              updatedAll[accountId] = updatedList;
            }
          });
          _allAccountMessages = updatedAll;
          _accountMessages = _applyLocalStateFilter(_allAccountMessages);
        });
        return;
      }

      // Update message in _allAccountMessages and reapply filter
      final updatedAll = <String, List<MessageIndex>>{};
      _allAccountMessages.forEach((accountId, messages) {
        final index = messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          final updatedList = List<MessageIndex>.from(messages);
          updatedList[index] = updatedList[index].copyWith(
            actionDate: actionDate,
            actionInsightText: actionText,
            actionComplete: currentComplete,
            hasAction: hasActionNow,
          );
          updatedAll[accountId] = updatedList;
        } else {
          updatedAll[accountId] = messages;
        }
      });

      setState(() {
        _allAccountMessages = updatedAll;
        _completionState[message.id] = currentComplete;
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

