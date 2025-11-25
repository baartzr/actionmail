import 'package:flutter_test/flutter_test.dart';
import 'package:domail/data/repositories/message_repository.dart';
import '../helpers/test_setup.dart';
import '../helpers/mock_factories.dart';

void main() {
  group('Email Sync Integration Tests', () {
    late MessageRepository repository;

    setUpAll(() {
      initializeTestEnvironment();
    });

    setUp(() async {
      repository = MessageRepository();
      // Clear repository before each test
      await repository.clearAll();
    });

    test('upsertMessages - saves messages to database', () async {
      final messages = MockFactory.createMockMessages(
        count: 3,
        accountId: 'test_account',
      );

      await repository.upsertMessages(messages);

      final saved = await repository.getAll('test_account');
      expect(saved.length, 3);
    });

    test('upsertMessages - updates existing messages', () async {
      final message = MockFactory.createMockMessage(
        id: 'test_id',
        accountId: 'test_account',
        isRead: false,
      );

      await repository.upsertMessages([message]);

      // Update the message
      final updated = message.copyWith(isRead: true);
      await repository.upsertMessages([updated]);

      final saved = await repository.getById('test_id');
      expect(saved, isNotNull);
      expect(saved!.isRead, isTrue);
    });

    test('getByFolder - filters messages by folder', () async {
      final inboxMessage = MockFactory.createMockMessage(
        accountId: 'test_account',
        folderLabel: 'INBOX',
      );
      final sentMessage = MockFactory.createMockMessage(
        accountId: 'test_account',
        folderLabel: 'SENT',
      );

      await repository.upsertMessages([inboxMessage, sentMessage]);

      final inbox = await repository.getByFolder('test_account', 'INBOX');
      expect(inbox.length, 1);
      expect(inbox.first.folderLabel, 'INBOX');

      final sent = await repository.getByFolder('test_account', 'SENT');
      expect(sent.length, 1);
      expect(sent.first.folderLabel, 'SENT');
    });

    test('getMessagesByThread - groups messages by thread', () async {
      final threadId = 'thread_123';
      final message1 = MockFactory.createMockMessage(
        id: 'msg1',
        threadId: threadId,
        accountId: 'test_account',
      );
      final message2 = MockFactory.createMockMessage(
        id: 'msg2',
        threadId: threadId,
        accountId: 'test_account',
      );
      final otherMessage = MockFactory.createMockMessage(
        id: 'msg3',
        threadId: 'thread_456',
        accountId: 'test_account',
      );

      await repository.upsertMessages([message1, message2, otherMessage]);

      final threadMessages = await repository.getMessagesByThread('test_account', threadId);
      expect(threadMessages.length, 2);
      expect(threadMessages.every((m) => m.threadId == threadId), isTrue);
    });
  });
}
