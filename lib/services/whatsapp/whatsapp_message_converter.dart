import 'package:domail/data/models/message_index.dart';
import 'package:uuid/uuid.dart';

/// WhatsApp message event data structure
class WhatsAppMessageEvent {
  final String? phoneNumber; // Sender's phone number (with country code)
  final String? messageId;
  final String? messageText;
  final DateTime? timestamp;
  final String? contactName;
  final String? conversationId;
  final bool isFromMe;

  WhatsAppMessageEvent({
    this.phoneNumber,
    this.messageId,
    this.messageText,
    this.timestamp,
    this.contactName,
    this.conversationId,
    this.isFromMe = false,
  });

  bool get isValid => phoneNumber != null && messageText != null && messageId != null;
}

/// Converts WhatsApp Business API events to MessageIndex format
/// Creates a consistent message structure for WhatsApp messages in the inbox
class WhatsAppMessageConverter {
  static const Uuid _uuid = Uuid();

  /// Convert a WhatsApp message event to MessageIndex
  /// Requires the account context the message should belong to
  static MessageIndex toMessageIndex(
    WhatsAppMessageEvent whatsappEvent, {
    required String accountId,
    required String accountEmail,
  }) {
    if (!whatsappEvent.isValid) {
      throw ArgumentError('WhatsApp event is not valid');
    }

    final phoneNumber = whatsappEvent.phoneNumber!;

    // Generate a unique ID for this WhatsApp message
    final messageId = whatsappEvent.messageId ?? 'whatsapp_${_uuid.v4()}';
    
    // Use phone number as thread ID (group messages by sender)
    final threadId = 'whatsapp_thread_${_normalizePhoneNumber(phoneNumber)}';
    
    // Use phone number as sender (from field) while keeping contact name (if available)
    final contactName = whatsappEvent.contactName;
    final from = contactName != null && contactName.trim().isNotEmpty
        ? '$contactName <$phoneNumber>'
        : phoneNumber;
    
    // For received messages, "to" is the user's phone number
    // For sent messages, "from" should be "Me" and "to" is the recipient
    final to = whatsappEvent.isFromMe ? phoneNumber : 'Me';
    final finalFrom = whatsappEvent.isFromMe ? 'Me' : from;

    // WhatsApp message body becomes the subject (since WhatsApp doesn't have subjects)
    final subject = whatsappEvent.messageText!;
    
    // Use first part of message as snippet (truncate if too long)
    final snippet = whatsappEvent.messageText!.length > 100
        ? '${whatsappEvent.messageText!.substring(0, 100)}...'
        : whatsappEvent.messageText!;

    // Use timestamp from event, or current time
    final internalDate = whatsappEvent.timestamp ?? DateTime.now();

    return MessageIndex(
      id: messageId,
      threadId: threadId,
      accountId: accountId,
      accountEmail: accountEmail,
      internalDate: internalDate,
      from: finalFrom,
      to: to,
      subject: subject,
      snippet: snippet,
      hasAttachments: false,
      gmailCategories: [],
      gmailSmartLabels: [],
      isRead: whatsappEvent.isFromMe, // Sent messages are read, received messages are unread by default
      isStarred: false,
      isImportant: false,
      folderLabel: whatsappEvent.isFromMe ? 'SENT' : 'INBOX',
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

  /// Check if a MessageIndex is a WhatsApp message
  static bool isWhatsAppMessage(MessageIndex message) {
    return message.threadId.startsWith('whatsapp_thread_') || message.id.startsWith('whatsapp_');
  }

  /// Extract phone number from a MessageIndex WhatsApp message
  static String? extractPhoneNumber(MessageIndex message) {
    if (!isWhatsAppMessage(message)) return null;
    
    // Extract from thread ID (format: whatsapp_thread_<normalized_number>)
    if (message.threadId.startsWith('whatsapp_thread_')) {
      return message.threadId.substring('whatsapp_thread_'.length);
    }
    
    // Fallback: extract from from/to field
    final from = message.from;
    if (from.contains('<') && from.contains('>')) {
      final match = RegExp(r'<([^>]+)>').firstMatch(from);
      if (match != null) {
        return match.group(1);
      }
    }
    
    // If no < > format, use the from field directly if it looks like a phone number
    if (RegExp(r'[\d\+]').hasMatch(from)) {
      return from;
    }
    
    return null;
  }
}

