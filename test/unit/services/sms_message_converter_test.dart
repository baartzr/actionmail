import 'package:flutter_test/flutter_test.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/data/models/message_index.dart';

void main() {
  group('SmsMessageConverter', () {
    test('isSmsMessage - identifies SMS messages correctly', () {
      final smsMessage = MessageIndex(
        id: 'sms_123',
        threadId: 'sms_thread_1234567890',
        accountId: 'test',
        accountEmail: 'test@example.com',
        internalDate: DateTime.now(),
        from: '+1234567890',
        to: 'Me',
        subject: 'Test SMS',
        snippet: 'Test SMS',
        folderLabel: 'INBOX',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        isRead: false,
        isStarred: false,
        isImportant: false,
      );

      final emailMessage = MessageIndex(
        id: 'email_123',
        threadId: 'thread_123',
        accountId: 'test',
        accountEmail: 'test@example.com',
        internalDate: DateTime.now(),
        from: 'sender@example.com',
        to: 'recipient@example.com',
        subject: 'Test Email',
        snippet: 'Test Email',
        folderLabel: 'INBOX',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        isRead: false,
        isStarred: false,
        isImportant: false,
      );

      expect(SmsMessageConverter.isSmsMessage(smsMessage), isTrue);
      expect(SmsMessageConverter.isSmsMessage(emailMessage), isFalse);
    });

    test('isSmsMessage - identifies SMS by thread ID prefix', () {
      final smsMessage = MessageIndex(
        id: 'email_123', // Not SMS ID
        threadId: 'sms_thread_1234567890', // But has SMS thread prefix
        accountId: 'test',
        accountEmail: 'test@example.com',
        internalDate: DateTime.now(),
        from: '+1234567890',
        to: 'Me',
        subject: 'Test SMS',
        snippet: 'Test SMS',
        folderLabel: 'INBOX',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        isRead: false,
        isStarred: false,
        isImportant: false,
      );

      expect(SmsMessageConverter.isSmsMessage(smsMessage), isTrue);
    });

    test('isSmsMessage - identifies SMS by ID prefix', () {
      final smsMessage = MessageIndex(
        id: 'sms_123', // Has SMS ID prefix
        threadId: 'thread_123', // Not SMS thread
        accountId: 'test',
        accountEmail: 'test@example.com',
        internalDate: DateTime.now(),
        from: '+1234567890',
        to: 'Me',
        subject: 'Test SMS',
        snippet: 'Test SMS',
        folderLabel: 'INBOX',
        hasAttachments: false,
        gmailCategories: [],
        gmailSmartLabels: [],
        isRead: false,
        isStarred: false,
        isImportant: false,
      );

      expect(SmsMessageConverter.isSmsMessage(smsMessage), isTrue);
    });
  });
}
