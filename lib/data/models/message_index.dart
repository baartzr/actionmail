import 'package:domail/constants/app_constants.dart';

/// Lightweight message index for ActionMail
/// Stores only essential data for list display and filtering
class MessageIndex {
  final String id;
  final String threadId;
  final String accountId;
  final String? accountEmail;
  final String? historyId;
  final DateTime internalDate;
  final String from;
  final String to;
  final String subject;
  final String? snippet;
  final bool hasAttachments;
  final List<String> gmailCategories; // CATEGORY_PERSONAL, etc.
  final List<String> gmailSmartLabels; // Purchase labels, etc.
  final String? localTagPersonal; // 'Personal', 'Business', resolves 'None'
  final bool subsLocal; // locally detected subscription
  final bool shoppingLocal; // locally detected shopping
  final bool unsubscribedLocal; // user confirmed unsubscribed
  final DateTime? actionDate;
  final double? actionConfidence;
  final String? actionInsightText;
  final bool actionComplete; // Whether the action is marked as complete
  final bool hasAction; // Whether this message has an action (date or text)
  final bool isRead;
  final bool isStarred;
  final bool isImportant;
  final String folderLabel; // INBOX, SENT, TRASH, SPAM, ARCHIVE
  final String? prevFolderLabel;

  MessageIndex({
    required this.id,
    required this.threadId,
    required this.accountId,
    this.accountEmail,
    this.historyId,
    required this.internalDate,
    required this.from,
    required this.to,
    required this.subject,
    this.snippet,
    this.hasAttachments = false,
    this.gmailCategories = const [],
    this.gmailSmartLabels = const [],
    this.localTagPersonal,
    this.subsLocal = false,
    this.shoppingLocal = false,
    this.unsubscribedLocal = false,
    this.actionDate,
    this.actionConfidence,
    this.actionInsightText,
    this.actionComplete = false,
    this.hasAction = false,
    this.isRead = false,
    this.isStarred = false,
    this.isImportant = false,
    this.folderLabel = 'INBOX',
    this.prevFolderLabel,
  });

  /// Get local tags (computed from message properties)
  List<String> get localTags {
    final tags = <String>[];
    if (hasAttachments) {
      tags.add(AppConstants.tagHasAttachment);
    }
    if (subsLocal) tags.add('Subscription');
    if (shoppingLocal) tags.add('Shopping');
    return tags;
  }

  MessageIndex copyWith({
    String? id,
    String? threadId,
    String? accountId,
    String? accountEmail,
    String? historyId,
    DateTime? internalDate,
    String? from,
    String? to,
    String? subject,
    String? snippet,
    bool? hasAttachments,
    List<String>? gmailCategories,
    List<String>? gmailSmartLabels,
    String? localTagPersonal,
    bool? subsLocal,
    bool? shoppingLocal,
    bool? unsubscribedLocal,
    DateTime? actionDate,
    double? actionConfidence,
    String? actionInsightText,
    bool? actionComplete,
    bool? hasAction,
    bool? isRead,
    bool? isStarred,
    bool? isImportant,
    String? folderLabel,
    String? prevFolderLabel,
  }) {
    return MessageIndex(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      accountId: accountId ?? this.accountId,
      accountEmail: accountEmail ?? this.accountEmail,
      historyId: historyId ?? this.historyId,
      internalDate: internalDate ?? this.internalDate,
      from: from ?? this.from,
      to: to ?? this.to,
      subject: subject ?? this.subject,
      snippet: snippet ?? this.snippet,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      gmailCategories: gmailCategories ?? this.gmailCategories,
      gmailSmartLabels: gmailSmartLabels ?? this.gmailSmartLabels,
      localTagPersonal: localTagPersonal ?? this.localTagPersonal,
      subsLocal: subsLocal ?? this.subsLocal,
      shoppingLocal: shoppingLocal ?? this.shoppingLocal,
      unsubscribedLocal: unsubscribedLocal ?? this.unsubscribedLocal,
      actionDate: actionDate ?? this.actionDate,
      actionConfidence: actionConfidence ?? this.actionConfidence,
      actionInsightText: actionInsightText ?? this.actionInsightText,
      actionComplete: actionComplete ?? this.actionComplete,
      hasAction: hasAction ?? this.hasAction,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      isImportant: isImportant ?? this.isImportant,
      folderLabel: folderLabel ?? this.folderLabel,
      prevFolderLabel: prevFolderLabel ?? this.prevFolderLabel,
    );
  }
}

