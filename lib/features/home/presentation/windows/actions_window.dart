import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:domail/shared/widgets/personal_business_filter.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/services/actions/ml_action_extractor.dart';
import 'package:domail/services/actions/action_extractor.dart';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:intl/intl.dart';
import 'package:domail/features/home/presentation/widgets/action_edit_dialog.dart';

class ActionsWindow extends ConsumerStatefulWidget {
  const ActionsWindow({super.key});

  @override
  ConsumerState<ActionsWindow> createState() => _ActionsWindowState();
}

class _ActionsWindowState extends ConsumerState<ActionsWindow> {
  String? _filterLocal; // null=All, 'Personal', 'Business'
  final FirebaseSyncService _firebaseSync = FirebaseSyncService();
  Timer? _tapTimer;
  MessageIndex? _pendingTapMessage;

  @override
  void dispose() {
    _tapTimer?.cancel();
    _tapTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(emailListProvider);
    return AppWindowDialog(
      title: 'Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PersonalBusinessFilter(
            selected: _filterLocal,
            onChanged: (v) => setState(() => _filterLocal = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: messagesAsync.when(
              data: (list) {
                final filtered = list.where((m) {
                  // Only show INBOX emails
                  if (m.folderLabel != 'INBOX') return false;
                  // Must have an action
                  if (!m.hasAction) return false;
                  // Apply Personal/Business filter if set
                  if (_filterLocal == null) return true;
                  return m.localTagPersonal == _filterLocal;
                }).toList()
                  ..sort((a, b) => (a.actionDate ?? DateTime(2100)).compareTo(b.actionDate ?? DateTime(2100)));
                if (filtered.isEmpty) {
                  return const Center(child: Text('No actions'));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _actionTile(filtered[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(MessageIndex m) {
    final actionDateFmt = DateFormat('dd-MMM yyyy');
    final receivedDateFmt = DateFormat('dd-MMM yyyy HH:mm');
    final actionDateStr = m.actionDate != null ? actionDateFmt.format(m.actionDate!.toLocal()) : '';
    final receivedDateStr = receivedDateFmt.format(m.internalDate.toLocal());
    
    // Parse sender name and email
    final parsedSender = _parseFrom(m.from);
    final senderName = parsedSender.item1;
    final senderEmail = parsedSender.item2;
    final senderDisplay = senderName.isNotEmpty 
        ? '$senderName <$senderEmail>'
        : senderEmail;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        return GestureDetector(
          onTap: () {
            // Cancel any pending single tap
            _tapTimer?.cancel();
            _pendingTapMessage = m;
            // Wait a bit to see if this is part of a double tap
            _tapTimer = Timer(const Duration(milliseconds: 300), () {
              if (_pendingTapMessage?.id == m.id) {
                // Single tap - open action edit
                _openEditActionDialog(m);
                _pendingTapMessage = null;
              }
            });
          },
          onDoubleTap: () {
            // Cancel single tap timer
            _tapTimer?.cancel();
            _pendingTapMessage = null;
            // Double tap - open email viewer
            _openEmailViewer(m);
          },
          behavior: HitTestBehavior.opaque,
          child: ListTile(
            leading: isMobile ? null : const Icon(Icons.event_note),
            title: Text(m.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From: $senderDisplay', style: const TextStyle(fontSize: 12)),
                Text('Received: $receivedDateStr', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                if (actionDateStr.isNotEmpty || (m.actionInsightText != null && m.actionInsightText!.isNotEmpty))
                  isMobile 
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (actionDateStr.isNotEmpty)
                              Text('Action date: $actionDateStr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            if (m.actionInsightText != null && m.actionInsightText!.isNotEmpty)
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                  children: [
                                    TextSpan(text: 'Message: ${m.actionInsightText} '),
                                    TextSpan(
                                      text: 'Edit',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.secondary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()..onTap = () => _openEditActionDialog(m),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (actionDateStr.isNotEmpty)
                              Text('Action date: $actionDateStr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            if (actionDateStr.isNotEmpty && m.actionInsightText != null && m.actionInsightText!.isNotEmpty)
                              const Text('  •  ', style: TextStyle(fontSize: 12)),
                            if (m.actionInsightText != null && m.actionInsightText!.isNotEmpty)
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    children: [
                                      TextSpan(text: 'Message: ${m.actionInsightText} '),
                                      TextSpan(
                                        text: 'Edit',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.secondary,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()..onTap = () => _openEditActionDialog(m),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
              ],
            ),
            trailing: Text(m.localTagPersonal ?? '', style: const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  void _openEmailViewer(MessageIndex message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EmailViewerDialog(
        message: message,
        accountId: message.accountId,
      ),
    );
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
      final shouldClearAction = !hasActionNow;
 
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
        if (currentDate != actionDate || currentText != actionText || currentComplete != message.actionComplete || shouldClearAction) {
          await _firebaseSync.syncEmailMeta(
            message.id,
            actionDate: hasActionNow ? actionDate : null,
            actionInsightText: hasActionNow ? actionText : null,
            actionComplete: hasActionNow ? currentComplete : null,
            clearAction: shouldClearAction,
          );
        }
      }
       
      // Record feedback for ML training
      final userAction = hasActionNow
          ? ActionResult(
              actionDate: actionDate ?? DateTime.now(),
              confidence: 1.0, // User-provided actions have max confidence
              insightText: actionText, // actionText is guaranteed non-null when hasActionNow is true
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

  /// Parse sender name and email from "from" field
  Tuple2<String, String> _parseFrom(String from) {
    final emailRegex = RegExp(r'<([^>]+)>');
    final match = emailRegex.firstMatch(from);
    if (match != null) {
      final email = match.group(1)!.trim();
      final name = from.replaceAll(match.group(0)!, '').trim();
      return Tuple2(name.replaceAll('"', ''), email);
    }
    // Fallbacks
    if (from.contains('@')) {
      return Tuple2('', from.trim());
    }
    return Tuple2(from.trim(), from.trim());
  }
}

class Tuple2<A, B> {
  final A item1;
  final B item2;
  const Tuple2(this.item1, this.item2);
}


