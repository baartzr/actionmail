import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/sms/pushbullet_message_parser.dart';
import 'package:uuid/uuid.dart';

/// Converts Pushbullet SMS events to MessageIndex format
/// Creates a consistent message structure for SMS messages in the inbox
class SmsMessageConverter {
  static const String _smsAccountId = 'sms_pushbullet';
  static const String _smsAccountEmail = 'SMS';
  static const Uuid _uuid = Uuid();

  /// Convert a Pushbullet SMS event to MessageIndex
  static MessageIndex toMessageIndex(PushbulletSmsEvent smsEvent) {
    if (!smsEvent.isValid) {
      throw ArgumentError('SMS event is not valid');
    }

    // Generate a unique ID for this SMS message
    // Use notification ID if available, otherwise generate UUID
    final messageId = smsEvent.notificationId ?? 
        'sms_${_uuid.v4()}';
    
    // Use phone number as thread ID (group messages by sender)
    final threadId = 'sms_thread_${_normalizePhoneNumber(smsEvent.phoneNumber!)}';

    // Use phone number as sender (from field)
    final from = smsEvent.phoneNumber!;
    
    // For SMS, "to" is typically the user's phone number
    // We'll use a placeholder or extract from device info if available
    final to = 'Me'; // Could be enhanced to get actual phone number

    // SMS message body becomes the subject (since SMS doesn't have subjects)
    final subject = smsEvent.message!;
    
    // Use first part of message as snippet (truncate if too long)
    final snippet = smsEvent.message!.length > 100
        ? '${smsEvent.message!.substring(0, 100)}...'
        : smsEvent.message!;

    // Use timestamp from event, or current time
    final internalDate = smsEvent.timestamp ?? DateTime.now();

    return MessageIndex(
      id: messageId,
      threadId: threadId,
      accountId: _smsAccountId,
      accountEmail: _smsAccountEmail,
      internalDate: internalDate,
      from: from,
      to: to,
      subject: subject,
      snippet: snippet,
      hasAttachments: false,
      gmailCategories: [],
      gmailSmartLabels: [],
      isRead: false, // New SMS messages are unread by default
      isStarred: false,
      isImportant: false,
      folderLabel: 'INBOX',
    );
  }

  /// Normalize phone number for consistent thread grouping
  /// Removes formatting characters to group messages from same number
  static String _normalizePhoneNumber(String phoneNumber) {
    // Remove common formatting characters
    return phoneNumber
        .replaceAll(RegExp(r'[\s\-\(\)\.]'), '')
        .replaceAll(RegExp(r'^\+'), '')
        .toLowerCase();
  }

  /// Check if a MessageIndex is an SMS message
  static bool isSmsMessage(MessageIndex message) {
    return message.accountId == _smsAccountId;
  }

  /// Get the SMS account ID
  static String get smsAccountId => _smsAccountId;

  /// Get the SMS account email/display name
  static String get smsAccountEmail => _smsAccountEmail;
}

