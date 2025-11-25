import 'package:flutter_test/flutter_test.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/services/sms/pushbullet_message_parser.dart';
import 'package:domail/data/models/message_index.dart';

void main() {
  group('SmsMessageConverter', () {
    test('toMessageIndex - converts SMS event correctly', () {
      final smsEvent = PushbulletSmsEvent(
        phoneNumber: '+1234567890',
        message: 'Hello, this is a test SMS',
        timestamp: DateTime(2024, 1, 15, 10, 30),
        notificationId: 'notif_123',
        title: 'John Doe',
      );

      final message = SmsMessageConverter.toMessageIndex(
        smsEvent,
        accountId: 'test_account',
        accountEmail: 'test@example.com',
      );

      expect(message.id, 'notif_123');
      expect(message.threadId, startsWith('sms_thread_'));
      expect(message.accountId, 'test_account');
      expect(message.from, contains('+1234567890'));
      expect(message.subject, 'Hello, this is a test SMS');
      expect(message.folderLabel, 'INBOX');
      expect(message.isRead, false);
    });

    test('toMessageIndex - includes contact name in from field', () {
      final smsEvent = PushbulletSmsEvent(
        phoneNumber: '+1234567890',
        message: 'Test message',
        title: 'John Doe',
      );

      final message = SmsMessageConverter.toMessageIndex(
        smsEvent,
        accountId: 'test_account',
        accountEmail: 'test@example.com',
      );

      expect(message.from, 'John Doe <+1234567890>');
    });

    test('isSmsMessage - identifies SMS messages correctly', () {
      final smsMessage = MessageIndex(
        id: 'sms_123',
        threadId: 'sms_thread_1234567890',
        accountId: 'test',
        internalDate: DateTime.now(),
        from: '+1234567890',
        to: 'Me',
        subject: 'Test SMS',
        folderLabel: 'INBOX',
      );

      final emailMessage = MessageIndex(
        id: 'email_123',
        threadId: 'thread_123',
        accountId: 'test',
        internalDate: DateTime.now(),
        from: 'sender@example.com',
        to: 'recipient@example.com',
        subject: 'Test Email',
        folderLabel: 'INBOX',
      );

      expect(SmsMessageConverter.isSmsMessage(smsMessage), isTrue);
      expect(SmsMessageConverter.isSmsMessage(emailMessage), isFalse);
    });
  });
}

