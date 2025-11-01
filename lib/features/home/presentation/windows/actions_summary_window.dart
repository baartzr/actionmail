import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:intl/intl.dart';

class ActionsSummaryWindow extends ConsumerStatefulWidget {
  const ActionsSummaryWindow({super.key});

  @override
  ConsumerState<ActionsSummaryWindow> createState() => _ActionsSummaryWindowState();
}

class _ActionsSummaryWindowState extends ConsumerState<ActionsSummaryWindow> {
  List<GoogleAccount> _accounts = [];
  Map<String, List<MessageIndex>> _accountMessages = {};
  bool _loading = true;

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
    
    final Map<String, List<MessageIndex>> messagesByAccount = {};
    
    for (final account in accounts) {
      final messages = await repo.getByFolder(account.id, 'INBOX');
      // Filter to only messages with actions
      final actions = messages.where((m) => 
        m.actionDate != null || (m.actionInsightText != null && m.actionInsightText!.isNotEmpty)
      ).toList();
      if (actions.isNotEmpty) {
        messagesByAccount[account.id] = actions;
      }
    }
    
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _accountMessages = messagesByAccount;
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
    );
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
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
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
                  // Action text with Edit link
                  Row(
                    children: [
                      Icon(
                        Icons.event_note,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            children: [
                              if (message.actionInsightText != null && message.actionInsightText!.isNotEmpty)
                                TextSpan(text: '${message.actionInsightText} '),
                              if (actionDateStr.isNotEmpty)
                                TextSpan(
                                  text: actionDateStr,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              const TextSpan(text: ' '),
                              TextSpan(
                                text: 'Edit',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.secondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = () => _openEditActionDialog(message),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditActionDialog(MessageIndex message) async {
    DateTime? tempDate = message.actionDate ?? DateTime.now();
    final textController = TextEditingController(text: message.actionInsightText ?? '');

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
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'actionDate': tempDate,
                      'actionText': textController.text.trim(),
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
      // Persist to database
      await MessageRepository().updateAction(message.id, actionDate, actionText);
      // Update in-memory state
      ref.read(emailListProvider.notifier).setAction(
        message.id,
        actionDate,
        actionText,
      );
      // Reload data to reflect changes
      await _loadData();
    }
  }
}

