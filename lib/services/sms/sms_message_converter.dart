import 'package:domail/data/models/message_index.dart';

/// Utility class for SMS message identification
/// Companion app converts SMS directly to MessageIndex, so this only provides identification helpers
class SmsMessageConverter {

  /// Check if a MessageIndex is an SMS message
  static bool isSmsMessage(MessageIndex message) {
    return message.threadId.startsWith('sms_thread_') || message.id.startsWith('sms_');
  }
}

