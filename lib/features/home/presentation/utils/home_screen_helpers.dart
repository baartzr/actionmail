import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';

/// Helper utilities for home screen operations
class HomeScreenHelpers {
  /// Get account email for a message, with fallback logic
  /// Tries message.accountEmail, then account from accounts list, then message.to/from
  static String getAccountEmail({
    required MessageIndex message,
    String? accountId,
    required List<GoogleAccount> accounts,
  }) {
    // First try message's account email
    if (message.accountEmail != null && message.accountEmail!.isNotEmpty) {
      return message.accountEmail!;
    }

    // Try to get from account ID (either provided or from message)
    final idToUse = accountId ?? message.accountId;
    if (idToUse.isNotEmpty && accounts.isNotEmpty) {
      try {
        final account = accounts.firstWhere(
          (a) => a.id == idToUse,
          orElse: () => const GoogleAccount(
            id: '',
            email: '',
            displayName: '',
            photoUrl: null,
            accessToken: '',
            refreshToken: null,
            tokenExpiryMs: null,
            idToken: '',
          ),
        );
        if (account.email.isNotEmpty) {
          return account.email;
        }
      } catch (_) {
        // Fall through to message fallback
      }
    }

    // Fallback to message.to or message.from
    if (message.to.isNotEmpty) {
      return message.to;
    }
    if (message.from.isNotEmpty) {
      return message.from;
    }

    return '';
  }

  /// Apply optimistic UI update for folder change (remove or set folder)
  /// This pattern is repeated throughout the code - extracted for consistency
  static void updateFolderOptimistic({
    required WidgetRef ref,
    required String messageId,
    required String currentFolder,
    required String targetFolder,
  }) {
    if (currentFolder.toUpperCase() != targetFolder.toUpperCase()) {
      ref.read(emailListProvider.notifier).removeMessage(messageId);
    } else {
      ref.read(emailListProvider.notifier).setFolder(messageId, targetFolder);
    }
  }
}

