import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/constants/app_constants.dart';

/// Sample Gmail email data for testing
/// Contains only Gmail label IDs - flags are derived from labels
class SampleEmails {
  // Gmail system label IDs
  static const String labelInbox = 'INBOX';
  static const String labelStarred = 'STARRED';
  static const String labelUnread = 'UNREAD';
  static const String labelImportant = 'IMPORTANT';
  static const String labelSent = 'SENT';
  static const String labelTrash = 'TRASH';
  static const String labelArchive = 'ARCHIVE';
  
  /// Generate sample emails with Gmail label IDs
  /// In real Gmail API, messages only have labelIds, not direct flags
  static List<MessageIndex> generateSampleEmails(String accountId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Generate base messages
    final baseMessages = _generateBaseMessages(accountId, now, today);
    
    // Apply label IDs and derive flags
    return baseMessages.map((msg) {
      final labelIds = getLabelIdsForMessage(msg.id);
      return _applyLabelsFromGmail(msg, labelIds);
    }).toList();
  }
  
  /// Generate base message data (without derived flags)
  static List<MessageIndex> _generateBaseMessages(String accountId, DateTime now, DateTime today) {
    return [
      // Email with action date - bill due
      MessageIndex(
        id: 'msg-001',
        threadId: 'thread-001',
        accountId: accountId,
        historyId: 'hist-001',
        internalDate: today.subtract(const Duration(days: 2)),
        from: 'billing@utilityco.com',
        to: 'user@example.com',
        subject: 'October Bill Available - Due 30 Apr',
        snippet: 'Please pay your bill by 30 April. Your amount due is 150.00.',
        hasAttachments: false,
        gmailCategories: [], // Will be populated from label IDs
        gmailSmartLabels: [],
        actionDate: DateTime(now.year, 4, 30),
        actionConfidence: 0.85,
        actionInsightText: 'It looks like this bill is due on 30 Apr.',
        // Flags derived from labelIds
      ),
      
      // Shopping email with delivery date
      MessageIndex(
        id: 'msg-002',
        threadId: 'thread-002',
        accountId: accountId,
        historyId: 'hist-002',
        internalDate: today.subtract(const Duration(days: 1)),
        from: 'orders@amazon.com',
        to: 'user@example.com',
        subject: 'Your order has shipped',
        snippet: 'Expected delivery on Tuesday, 5 November. Track your package.',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: DateTime(now.year, 11, 5),
        actionConfidence: 0.90,
        actionInsightText: 'It looks like your package arrives on Tue 5 Nov.',
        // Flags derived from labelIds
      ),
      
      // Email with attachment
      MessageIndex(
        id: 'msg-003',
        threadId: 'thread-003',
        accountId: accountId,
        historyId: 'hist-003',
        internalDate: today.subtract(const Duration(days: 3)),
        from: 'team@company.com',
        to: 'user@example.com',
        subject: 'Q4 Report - Please Review',
        snippet: 'Please review the attached Q4 report and provide feedback by Friday.',
        hasAttachments: true,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: DateTime(now.year, now.month, now.day + 3), // Friday
        actionConfidence: 0.75,
        actionInsightText: 'It looks like you need to review this by Friday.',
        // Flags derived from labelIds
      ),
      
      // Email without detected action
      MessageIndex(
        id: 'msg-004',
        threadId: 'thread-004',
        accountId: accountId,
        historyId: 'hist-004',
        internalDate: today.subtract(const Duration(hours: 5)),
        from: 'newsletter@daily.com',
        to: 'user@example.com',
        subject: 'Your weekly digest',
        snippet: 'Here are the top stories from this week...',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: null,
        actionConfidence: null,
        actionInsightText: null,
        // Flags derived from labelIds
      ),
      
      // Overdue action email
      MessageIndex(
        id: 'msg-005',
        threadId: 'thread-005',
        accountId: accountId,
        historyId: 'hist-005',
        internalDate: today.subtract(const Duration(days: 10)),
        from: 'hr@company.com',
        to: 'user@example.com',
        subject: 'Please update your emergency contact',
        snippet: 'Please update your emergency contact information by 25 October.',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: DateTime(now.year, 10, 25), // In the past = overdue
        actionConfidence: 0.80,
        actionInsightText: 'It looks like this was due on 25 Oct.',
        // Flags derived from labelIds
      ),
      
      // Finance email
      MessageIndex(
        id: 'msg-006',
        threadId: 'thread-006',
        accountId: accountId,
        historyId: 'hist-006',
        internalDate: today.subtract(const Duration(hours: 12)),
        from: 'alerts@bank.com',
        to: 'user@example.com',
        subject: 'Transaction Alert',
        snippet: 'A transaction of 45.00 was made at Coffee Shop.',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: null,
        actionConfidence: null,
        actionInsightText: null,
        // Flags derived from labelIds
      ),
      
      // Social email
      MessageIndex(
        id: 'msg-007',
        threadId: 'thread-007',
        accountId: accountId,
        historyId: 'hist-007',
        internalDate: today.subtract(const Duration(hours: 1)),
        from: 'noreply@socialmedia.com',
        to: 'user@example.com',
        subject: 'John commented on your post',
        snippet: 'John Smith commented on your recent post about...',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: null,
        actionConfidence: null,
        actionInsightText: null,
        // Flags derived from labelIds
      ),
      
      // Promotion email
      MessageIndex(
        id: 'msg-008',
        threadId: 'thread-008',
        accountId: accountId,
        historyId: 'hist-008',
        internalDate: today.subtract(const Duration(days: 3)),
        from: 'deals@store.com',
        to: 'user@example.com',
        subject: '50% Off Sale This Weekend!',
        snippet: 'Don\'t miss our biggest sale of the year. Use code SAVE50.',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: null,
        actionConfidence: null,
        actionInsightText: null,
        isRead: false,
        isStarred: false,
        isImportant: false,
      ),
      
      // Travel email
      MessageIndex(
        id: 'msg-009',
        threadId: 'thread-009',
        accountId: accountId,
        historyId: 'hist-009',
        internalDate: today.subtract(const Duration(days: 5)),
        from: 'confirmation@airline.com',
        to: 'user@example.com',
        subject: 'Your flight confirmation',
        snippet: 'Flight AA1234 on December 15, 2024. Check-in opens 24 hours before departure.',
        hasAttachments: true,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: DateTime(now.year, 12, 15),
        actionConfidence: 0.70,
        actionInsightText: 'It looks like your flight is on 15 Dec.',
        isRead: false,
        isStarred: false,
        isImportant: false,
      ),
      
      // Receipt email
      MessageIndex(
        id: 'msg-010',
        threadId: 'thread-010',
        accountId: accountId,
        historyId: 'hist-010',
        internalDate: today.subtract(const Duration(hours: 3)),
        from: 'receipts@store.com',
        to: 'user@example.com',
        subject: 'Receipt for your purchase',
        snippet: 'Thank you for your purchase. Your receipt is attached.',
        hasAttachments: true,
        gmailCategories: [],
        gmailSmartLabels: [],
        actionDate: null,
        actionConfidence: null,
        actionInsightText: null,
        isRead: false,
        isStarred: false,
        isImportant: false,
      ),
    ];
  }
  
  /// Convert Gmail label IDs to MessageIndex flags and categories
  /// In real implementation, this would process label IDs from Gmail API
  static MessageIndex _applyLabelsFromGmail(MessageIndex message, List<String> labelIds) {
    // Derive flags from label IDs
    final isRead = !labelIds.contains('UNREAD');
    final isStarred = labelIds.contains('STARRED');
    final isImportant = labelIds.contains('IMPORTANT');
    
    // Extract Gmail categories from label IDs
    final gmailCategories = labelIds.where((label) => 
      AppConstants.allGmailCategories.contains(label)
    ).toList();
    
    return message.copyWith(
      isRead: isRead,
      isStarred: isStarred,
      isImportant: isImportant,
      gmailCategories: gmailCategories,
    );
  }
  
  /// Get Gmail label IDs for a message (simulated)
  /// In real implementation, this comes from Gmail API message.labelIds
  static List<String> getLabelIdsForMessage(String messageId) {
    // Simulate different label combinations based on message ID
    final labelMap = {
      'msg-001': ['INBOX', 'UNREAD', 'CATEGORY_BILLS'],
      'msg-002': ['INBOX', 'UNREAD', 'CATEGORY_PURCHASES'],
      'msg-003': ['INBOX', 'STARRED', 'IMPORTANT', 'CATEGORY_PERSONAL'],
      'msg-004': ['INBOX', 'UNREAD', 'CATEGORY_UPDATES'],
      'msg-005': ['INBOX', 'IMPORTANT', 'CATEGORY_PERSONAL'],
      'msg-006': ['INBOX', 'CATEGORY_FINANCE'],
      'msg-007': ['INBOX', 'UNREAD', 'CATEGORY_SOCIAL'],
      'msg-008': ['INBOX', 'UNREAD', 'CATEGORY_PROMOTIONS'],
      'msg-009': ['INBOX', 'STARRED', 'CATEGORY_TRAVEL'],
      'msg-010': ['INBOX', 'CATEGORY_RECEIPTS'],
    };
    
    return labelMap[messageId] ?? [labelInbox];
  }
}
