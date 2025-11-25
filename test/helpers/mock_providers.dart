import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/services/gmail/gmail_sync_service.dart';

/// Mock providers for testing
/// Use these to override real providers with test data

/// Mock GoogleAuthService provider
final mockGoogleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  // Return a mock implementation
  throw UnimplementedError('Provide a mock GoogleAuthService in test overrides');
});

/// Mock email list provider override
final mockEmailListProvider = StateProvider<List<MessageIndex>>((ref) => []);

/// Simple mock EmailListNotifier for testing
class MockEmailListNotifier extends EmailListNotifier {
  MockEmailListNotifier(super.ref, super.syncService, AsyncValue<List<MessageIndex>> initialState) {
    state = initialState;
  }
}

/// Helper to create provider overrides for common test scenarios
class TestProviderOverrides {
  /// Create overrides with a list of mock messages
  static List<Override> withMockMessages({
    required List<MessageIndex> messages,
    String? accountId,
    GmailSyncService? syncService,
  }) {
    return [
      emailListProvider.overrideWith((ref) {
        final service = syncService ?? GmailSyncService();
        return MockEmailListNotifier(ref, service, AsyncValue.data(messages));
      }),
    ];
  }

  /// Create overrides with a mock account
  static List<Override> withMockAccount(GoogleAccount account) {
    return [
      // Add account-related provider overrides here
      // For example, if you have an accountProvider
    ];
  }

  /// Create overrides with empty/default state
  static List<Override> empty({GmailSyncService? syncService}) {
    return [
      emailListProvider.overrideWith((ref) {
        final service = syncService ?? GmailSyncService();
        return MockEmailListNotifier(ref, service, const AsyncValue.loading());
      }),
      networkErrorProvider.overrideWith((ref) => false),
      authFailureProvider.overrideWith((ref) => null),
    ];
  }
}

