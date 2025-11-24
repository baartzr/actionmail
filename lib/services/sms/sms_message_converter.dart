import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/sms/pushbullet_message_parser.dart';
import 'package:uuid/uuid.dart';

/// Converts Pushbullet SMS events to MessageIndex format
/// Creates a consistent message structure for SMS messages in the inbox
class SmsMessageConverter {
  static const Uuid _uuid = Uuid();

  /// Convert a Pushbullet SMS event to MessageIndex
  /// Requires the account context the SMS should belong to
  static MessageIndex toMessageIndex(
    PushbulletSmsEvent smsEvent, {
    required String accountId,
    required String accountEmail,
  }) {
    if (!smsEvent.isValid) {
      throw ArgumentError('SMS event is not valid');
    }

    final phoneNumber = smsEvent.phoneNumber!;

    // Generate a unique ID for this SMS message
    // Use notification ID if available, otherwise generate UUID
    final messageId = smsEvent.notificationId ?? 'sms_${_uuid.v4()}';
    
    // Use phone number as thread ID (group messages by sender)
    final threadId = 'sms_thread_${_normalizePhoneNumber(phoneNumber)}';
    
    // Use phone number as sender (from field) while keeping contact name (if available)
    final contactName = smsEvent.title;
    final from = contactName != null && contactName.trim().isNotEmpty
        ? '$contactName <$phoneNumber>'
        : phoneNumber;
    
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
      accountId: accountId,
      accountEmail: accountEmail,
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
    return message.threadId.startsWith('sms_thread_') || message.id.startsWith('sms_');
  }
}

