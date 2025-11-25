import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:uuid/uuid.dart';

/// Factory for creating test data
class MockFactory {
  static const Uuid _uuid = Uuid();

  /// Create a mock GoogleAccount for testing
  static GoogleAccount createMockAccount({
    String? id,
    String? email,
    String? displayName,
    String? accessToken,
    String? refreshToken,
  }) {
    return GoogleAccount(
      id: id ?? _uuid.v4(),
      email: email ?? 'test@example.com',
      displayName: displayName ?? 'Test User',
      photoUrl: null,
      accessToken: accessToken ?? 'mock_access_token_${_uuid.v4()}',
      refreshToken: refreshToken ?? 'mock_refresh_token_${_uuid.v4()}',
      tokenExpiryMs: DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      idToken: 'mock_id_token',
    );
  }

  /// Create a mock MessageIndex for testing
  static MessageIndex createMockMessage({
    String? id,
    String? threadId,
    String? accountId,
    String? accountEmail,
    String? from,
    String? to,
    String? subject,
    String? snippet,
    DateTime? internalDate,
    bool? isRead,
    bool? hasAction,
    DateTime? actionDate,
    String? actionInsightText,
    String? folderLabel,
    String? localTagPersonal,
    bool? actionComplete,
  }) {
    return MessageIndex(
      id: id ?? 'msg_${_uuid.v4()}',
      threadId: threadId ?? 'thread_${_uuid.v4()}',
      accountId: accountId ?? 'account_${_uuid.v4()}',
      accountEmail: accountEmail ?? 'test@example.com',
      internalDate: internalDate ?? DateTime.now(),
      from: from ?? 'sender@example.com',
      to: to ?? 'recipient@example.com',
      subject: subject ?? 'Test Email Subject',
      snippet: snippet ?? 'Test email snippet',
      hasAttachments: false,
      gmailCategories: [],
      gmailSmartLabels: [],
      isRead: isRead ?? false,
      isStarred: false,
      isImportant: false,
      folderLabel: folderLabel ?? 'INBOX',
      hasAction: hasAction ?? false,
      actionDate: actionDate,
      actionInsightText: actionInsightText,
      actionConfidence: hasAction == true ? 0.8 : null,
      localTagPersonal: localTagPersonal,
      actionComplete: actionComplete ?? false,
    );
  }

  /// Create a mock SMS MessageIndex
  static MessageIndex createMockSmsMessage({
    String? phoneNumber,
    String? messageText,
    DateTime? timestamp,
    String? accountId,
    String? accountEmail,
  }) {
    final phone = phoneNumber ?? '+1234567890';
    final text = messageText ?? 'Test SMS message';
    return MessageIndex(
      id: 'sms_${_uuid.v4()}',
      threadId: 'sms_thread_${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
      accountId: accountId ?? 'account_${_uuid.v4()}',
      accountEmail: accountEmail ?? 'test@example.com',
      internalDate: timestamp ?? DateTime.now(),
      from: phone,
      to: 'Me',
      subject: text,
      snippet: text.length > 100 ? '${text.substring(0, 100)}...' : text,
      hasAttachments: false,
      gmailCategories: [],
      gmailSmartLabels: [],
      isRead: false,
      isStarred: false,
      isImportant: false,
      folderLabel: 'INBOX',
    );
  }

  /// Create a mock WhatsApp MessageIndex
  static MessageIndex createMockWhatsAppMessage({
    String? phoneNumber,
    String? messageText,
    DateTime? timestamp,
    String? accountId,
    String? accountEmail,
  }) {
    final phone = phoneNumber ?? '+1234567890';
    final text = messageText ?? 'Test WhatsApp message';
    return MessageIndex(
      id: 'whatsapp_${_uuid.v4()}',
      threadId: 'whatsapp_thread_${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
      accountId: accountId ?? 'account_${_uuid.v4()}',
      accountEmail: accountEmail ?? 'test@example.com',
      internalDate: timestamp ?? DateTime.now(),
      from: phone,
      to: 'Me',
      subject: text,
      snippet: text.length > 100 ? '${text.substring(0, 100)}...' : text,
      hasAttachments: false,
      gmailCategories: [],
      gmailSmartLabels: [],
      isRead: false,
      isStarred: false,
      isImportant: false,
      folderLabel: 'INBOX',
    );
  }

  /// Create a list of mock messages
  static List<MessageIndex> createMockMessages({
    required int count,
    String? accountId,
    String? accountEmail,
  }) {
    return List.generate(
      count,
      (index) => createMockMessage(
        accountId: accountId,
        accountEmail: accountEmail,
        subject: 'Test Email ${index + 1}',
        internalDate: DateTime.now().subtract(Duration(hours: count - index)),
      ),
    );
  }
}

