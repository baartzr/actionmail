/// Application-wide constants
class AppConstants {
  // App name
  static const String appName = 'ActionMail';

  // Folder constants
  static const String folderInbox = 'INBOX';
  static const String folderSent = 'SENT';
  static const String folderTrash = 'TRASH';
  static const String folderSpam = 'SPAM';
  static const String folderArchive = 'ARCHIVE';

  // Folder display names
  static const Map<String, String> folderDisplayNames = {
    'INBOX': 'Inbox',
    'SENT': 'Sent',
    'TRASH': 'Trash',
    'SPAM': 'Spam',
    'ARCHIVE': 'Archive',
  };

  // Swipe actions
  static const String swipeActionTrash = 'Trash';
  static const String swipeActionArchive = 'Archive';

  // Email states
  static const String emailStateUnread = 'Unread';
  static const String emailStateStarred = 'Starred';
  static const String emailStateImportant = 'Important';

  // Local tags
  static const String tagHasAttachment = 'Attachment';

  // Gmail categories
  static const String categoryPersonal = 'CATEGORY_PERSONAL';
  static const String categorySocial = 'CATEGORY_SOCIAL';
  static const String categoryPromotions = 'CATEGORY_PROMOTIONS';
  static const String categoryUpdates = 'CATEGORY_UPDATES';
  static const String categoryForums = 'CATEGORY_FORUMS';

  static const List<String> allGmailCategories = [
    categoryPersonal,
    categorySocial,
    categoryPromotions,
    categoryUpdates,
    categoryForums,
  ];

  static const Map<String, String> categoryDisplayNames = {
    categoryPersonal: 'Personal',
    categorySocial: 'Social',
    categoryPromotions: 'Promotions',
    categoryUpdates: 'Updates',
    categoryForums: 'Forums',
  };

  // Function windows
  static const String windowActions = 'Actions';
  static const String windowAttachments = 'Attachments';
  static const String windowSubscriptions = 'Subscriptions';
  static const String windowShopping = 'Shopping';

  static const List<String> allFunctionWindows = [
    windowActions,
    windowAttachments,
    windowSubscriptions,
    windowShopping,
  ];

  // Action filters
  static const String filterToday = 'Today';
  static const String filterUpcoming = 'Upcoming';
  static const String filterOverdue = 'Overdue';

  // Action summary labels
  static const String actionSummaryToday = 'Today';
  static const String actionSummaryUpcoming = 'Upcoming';
  static const String actionSummaryOverdue = 'Overdue';
  static const String actionSummaryAll = 'All Actions';

  // Empty states
  static const String emptyStateNoEmails = 'No emails found';

  // OAuth configuration
  // Note: clientId and clientSecret are now in lib/config/oauth_config.dart (gitignored)
  static const String oauthRedirectUri = 'http://localhost:8400';
  static const List<String> oauthScopes = [
    'email',
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];
}

