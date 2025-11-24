import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:flutter/material.dart';
import 'package:domail/shared/widgets/app_dropdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/constants/app_constants.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/features/home/presentation/widgets/email_tile.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/features/home/presentation/windows/actions_summary_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domail/features/home/presentation/widgets/account_selector_dialog.dart';
import 'package:domail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:domail/shared/widgets/reauth_prompt_dialog.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:domail/services/actions/ml_action_extractor.dart';
import 'package:domail/services/actions/action_extractor.dart';
import 'package:domail/services/gmail/gmail_sync_service.dart';
import 'package:domail/services/local_folders/local_folder_service.dart';
// duplicate import removed: gmail_sync_service.dart
import 'package:domail/data/models/message_index.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ensemble_app_badger/ensemble_app_badger.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:domail/features/home/domain/providers/view_mode_provider.dart';
import 'package:domail/features/home/presentation/widgets/grid_email_list.dart';
import 'package:domail/features/home/presentation/widgets/action_edit_dialog.dart';
import 'package:domail/features/home/presentation/widgets/home_right_panel.dart';
import 'package:domail/features/home/presentation/widgets/home_filter_bar.dart';
import 'package:domail/features/home/presentation/widgets/home_bulk_actions_appbar.dart';
import 'package:domail/features/home/presentation/widgets/home_appbar_state_switch.dart';
import 'package:domail/features/home/presentation/widgets/home_left_panel.dart';
import 'package:domail/features/home/presentation/widgets/home_provider_listeners.dart';
import 'package:domail/shared/widgets/processing_dialog.dart';
import 'package:domail/features/home/presentation/widgets/home_saved_list_indicator.dart';
import 'package:domail/features/home/presentation/widgets/home_filter_banner.dart';
import 'package:domail/features/home/presentation/widgets/home_email_list_filter.dart';
import 'package:domail/features/home/presentation/widgets/home_menu_button.dart';
import 'package:domail/features/home/presentation/widgets/move_to_folder_dialog.dart';
import 'package:domail/features/home/presentation/utils/home_screen_helpers.dart';
import 'package:domail/features/home/presentation/widgets/local_folder_tree.dart';
import 'package:domail/features/home/presentation/widgets/floating_account_widget.dart';

/// Main home screen for ActionMail
/// Displays email list with filters and action management
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Configuration for status buttons based on folder
// _StatusButtonConfig moved to HomeBulkActionsAppBar widget

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  // Selected folder (default to Inbox)
  String _selectedFolder = AppConstants.folderInbox;
  // Whether viewing a local backup folder (vs Gmail folder)
  bool _isLocalFolder = false;
  // Accounts
  String? _selectedAccountId;
  List<GoogleAccount> _accounts = [];
  bool _initializedFromRoute = false;
  bool _isOpeningAccountDialog = false;
  bool _isAccountsRefreshing = false;
  DateTime? _lastAccountTap;

  // Account unread counts (for left panel display)
  Map<String, int> _accountUnreadCounts = {};
  final Set<String> _pendingLocalUnreadAccounts = {};
  Timer? _unreadCountRefreshTimer;

  // Selected local state filter: null (show all), 'Personal', or 'Business'
  String? _selectedLocalState;

  // Cached service instances to avoid repeated instantiation
  late final MessageRepository _messageRepository = MessageRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadCountRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app resumes, check if re-auth completed successfully
    // Only check if we're actually expecting a re-auth (oauth_reauth_account_id exists)
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      // Check if re-auth is in progress before checking completion
      SharedPreferences.getInstance().then((prefs) async {
        final reauthAccountId = prefs.getString('oauth_reauth_account_id');
        if (reauthAccountId != null && reauthAccountId == _selectedAccountId) {
          // ignore: avoid_print
          print('[home] app resumed, re-auth in progress, checking if re-auth completed successfully...');
          _checkReauthCompletion();
        }
      });
    }
  }

  /// Check if re-authentication completed successfully after app resume
  Future<void> _checkReauthCompletion() async {
    if (!mounted || _selectedAccountId == null) return;

    // ignore: avoid_print
    print('[home] _checkReauthCompletion: starting check for account $_selectedAccountId');

    // First, check if there's an App Link that needs to be processed (Android re-auth)
    // Only check if we're actually expecting a re-auth (oauth_reauth_account_id exists)
    if (Platform.isAndroid) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final reauthAccountId = prefs.getString('oauth_reauth_account_id');
        
        // Only process App Links if we're expecting a re-auth for the selected account
        if (reauthAccountId != null && reauthAccountId == _selectedAccountId) {
          final methodChannel = MethodChannel('com.seagreen.domail/bringToFront');
          // ignore: avoid_print
          print('[home] _checkReauthCompletion: checking for App Link (re-auth in progress)...');
          final appLink = await methodChannel.invokeMethod<String>('getInitialAppLink');
          // ignore: avoid_print
          print('[home] _checkReauthCompletion: getInitialAppLink returned: $appLink');
          
          if (appLink != null && appLink.isNotEmpty && appLink.contains('code=')) {
          // App Link found - need to complete OAuth flow
          // ignore: avoid_print
          print('[home] _checkReauthCompletion: detected OAuth App Link, completing OAuth flow...');
          
          final uri = Uri.parse(appLink);
          final code = uri.queryParameters['code'];
          final error = uri.queryParameters['error'];
          
          if (error != null) {
            // ignore: avoid_print
            print('[home] _checkReauthCompletion: OAuth error in App Link: $error');
            // Clear the App Link
            try {
              await methodChannel.invokeMethod('clearAppLink');
            } catch (_) {}
            return;
          }
          
          if (code != null) {
            final prefs = await SharedPreferences.getInstance();
            final verifier = prefs.getString('oauth_pkce_verifier');
            final redirectUri = prefs.getString('oauth_redirect_uri');
            final clientId = prefs.getString('oauth_client_id');
            final clientSecret = prefs.getString('oauth_client_secret');
            final reauthAccountId = prefs.getString('oauth_reauth_account_id');
            
            if (verifier != null && redirectUri != null && clientId != null && clientSecret != null) {
              // Check if this is a re-auth for the selected account
              if (reauthAccountId != null && reauthAccountId == _selectedAccountId) {
                // ignore: avoid_print
                print('[home] _checkReauthCompletion: completing OAuth re-auth for account $reauthAccountId');
                
                final auth = GoogleAuthService();
                final account = await auth.completeOAuthFlow(code, verifier, redirectUri, clientId, clientSecret);
                
                if (account != null) {
                  // ignore: avoid_print
                  print('[home] _checkReauthCompletion: OAuth completed, updating account tokens');
                  
                  // Update existing account with new tokens
                  final existingAccounts = await auth.loadAccounts();
                  final idx = existingAccounts.indexWhere((a) => a.id == reauthAccountId);
                  if (idx != -1) {
                    final updated = existingAccounts[idx].copyWith(
                      accessToken: account.accessToken,
                      refreshToken: account.refreshToken ?? existingAccounts[idx].refreshToken,
                      tokenExpiryMs: account.tokenExpiryMs,
                    );
                    existingAccounts[idx] = updated;
                    await auth.saveAccounts(existingAccounts);
                    
                    // Clear token check cache since tokens were updated
                    auth.clearTokenCheckCache(reauthAccountId);
                    // ignore: avoid_print
                    print('[home] _checkReauthCompletion: tokens updated and cache cleared');
                    
                    // Clear error state
                    auth.clearLastError(reauthAccountId);
                    
                    // Clear stored OAuth state
                    await prefs.remove('oauth_pkce_verifier');
                    await prefs.remove('oauth_redirect_uri');
                    await prefs.remove('oauth_client_id');
                    await prefs.remove('oauth_client_secret');
                    await prefs.remove('oauth_reauth_account_id');
                    
                    // Clear the App Link
                    try {
                      await methodChannel.invokeMethod('clearAppLink');
                    } catch (_) {}
                    
                    // OAuth completed successfully, now validate tokens below
                  } else {
                    // ignore: avoid_print
                    print('[home] _checkReauthCompletion: ERROR - account not found after OAuth completion');
                    return;
                  }
                } else {
                  // ignore: avoid_print
                  print('[home] _checkReauthCompletion: OAuth completion failed');
                  // Clear stored OAuth state on failure
                  await prefs.remove('oauth_pkce_verifier');
                  await prefs.remove('oauth_redirect_uri');
                  await prefs.remove('oauth_client_id');
                  await prefs.remove('oauth_client_secret');
                  await prefs.remove('oauth_reauth_account_id');
                  return;
                }
              } else {
                // ignore: avoid_print
                print('[home] _checkReauthCompletion: App Link is for different account (reauthAccountId=$reauthAccountId, selected=$_selectedAccountId)');
              }
            } else {
              // ignore: avoid_print
              print('[home] _checkReauthCompletion: OAuth state missing in SharedPreferences');
            }
          }
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[home] _checkReauthCompletion: error checking App Link: $e');
        // Continue with normal validation flow
      }
    }

    // Reload accounts first to ensure we have the latest tokens
    await _loadAccounts();
    if (!mounted) return;

    // Debug: Check what tokens are in the account before validation
    final auth = GoogleAuthService();
    final rawAccount = await auth.getAccountById(_selectedAccountId!);
    if (rawAccount != null) {
      // ignore: avoid_print
      print('[home] _checkReauthCompletion: loaded account from storage - accessToken=${rawAccount.accessToken.isNotEmpty ? '${rawAccount.accessToken.substring(0, 20)}...' : 'EMPTY'} refreshToken=${rawAccount.refreshToken != null && rawAccount.refreshToken!.isNotEmpty ? '${rawAccount.refreshToken!.substring(0, 20)}...' : 'null/empty'} tokenExpiryMs=${rawAccount.tokenExpiryMs}');
    } else {
      // ignore: avoid_print
      print('[home] _checkReauthCompletion: ERROR - account not found in storage! accountId=$_selectedAccountId');
    }

    // Check if the selected account now has valid tokens
    // ignore: avoid_print
    print('[home] _checkReauthCompletion: calling ensureValidAccessToken...');
    final account = await auth.ensureValidAccessToken(_selectedAccountId!);
    
    if (account != null && account.accessToken.isNotEmpty) {
      // ignore: avoid_print
      print('[home] _checkReauthCompletion: ensureValidAccessToken returned valid account - accessToken=${account.accessToken.substring(0, 20)}...');
      // Re-auth succeeded - clear error state
      // ignore: avoid_print
      print('[home] Re-auth completed successfully for account $_selectedAccountId');
      auth.clearLastError(_selectedAccountId!);
      
      // Clear auth failure provider
      ref.read(authFailureProvider.notifier).state = null;
      
      if (mounted) {
        // Dismiss any open dialogs by popping navigator
        final navigator = Navigator.of(context, rootNavigator: true);
        while (navigator.canPop()) {
          navigator.pop();
        }
        
        // Reload emails for the selected account now that tokens are valid
        if (_selectedAccountId != null) {
          ref.read(emailListProvider.notifier)
              .loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
        }
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Re-authentication successful')),
        );
      }
    } else {
      // Re-auth failed or tokens are still invalid
      // ignore: avoid_print
      print('[home] _checkReauthCompletion: ensureValidAccessToken returned null or empty token');
      if (account != null) {
        // ignore: avoid_print
        print('[home] _checkReauthCompletion: account exists but accessToken is empty - accessToken=${account.accessToken.isEmpty} refreshToken=${account.refreshToken != null && account.refreshToken!.isNotEmpty}');
      } else {
        // ignore: avoid_print
        print('[home] _checkReauthCompletion: account is null');
      }
      // ignore: avoid_print
      print('[home] Re-auth check: tokens still invalid for account $_selectedAccountId');
      // Clear provider first, then set it again to trigger ref.listen
      ref.read(authFailureProvider.notifier).state = null;
      // Use post-frame callback to set it again, ensuring ref.listen fires
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedAccountId != null) {
          ref.read(authFailureProvider.notifier).state = _selectedAccountId;
        }
      });
    }
  }

  /// Handle re-auth needed notification - show dialog and wait for user action
  /// Dialog shows automatically when token refresh fails or internet is down
  /// Dialog stays open (modal) until user takes action: retry, reauth, or cancel
  /// Only called for the active/selected account
  /// Since there's only one active account, there will only ever be one dialog
  Future<void> _handleReauthNeeded(String accountId) async {
    if (!mounted) return;

    final account = _accounts.firstWhere(
      (acc) => acc.id == accountId,
      orElse: () => GoogleAccount(
        id: accountId,
        email: 'Unknown',
        displayName: '',
        photoUrl: null,
        accessToken: '',
        refreshToken: null,
        tokenExpiryMs: null,
        idToken: '',
      ),
    );
    final email = account.email;

    final auth = GoogleAuthService();
    final isConnectionError = auth.isLastErrorNetworkError(accountId) == true;

    try {
      // Show dialog - it stays open until user takes action (modal, barrierDismissible: false)
      final action = await ReauthPromptDialog.show(
        context: context,
        accountId: accountId,
        accountEmail: email,
        isConnectionError: isConnectionError,
      );

      if (!mounted || action == null || action == 'cancel') {
        // User cancelled - clear auth failure provider
        if (ref.read(authFailureProvider) == accountId) {
          ref.read(authFailureProvider.notifier).state = null;
        }
        return; // User cancelled
      }

      if (action == 'retry') {
        // User chose to retry - attempt token refresh again
        final refreshed = await auth.ensureValidAccessToken(accountId);
        if (refreshed != null && refreshed.accessToken.isNotEmpty) {
          // Success - clear error
          auth.clearLastError(accountId);
          // Clear auth failure provider
          if (ref.read(authFailureProvider) == accountId) {
            ref.read(authFailureProvider.notifier).state = null;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Connection restored')),
            );
          }
        } else {
          // Retry failed - re-trigger dialog
          // Clear and re-set provider to ensure ref.listen fires
          if (ref.read(authFailureProvider) == accountId) {
            ref.read(authFailureProvider.notifier).state = null;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(authFailureProvider.notifier).state = accountId;
            }
          });
        }
        return;
      }

      // User chose to re-authenticate/reconnect
      final reauthAccount = await auth.reauthenticateAccount(accountId);
      if (!mounted) return;

      // reauthenticateAccount returns null when browser was launched (completion handled on app resume)
      // or null when re-auth failed/cancelled (desktop/iOS)
      // or the updated account when re-auth completed successfully (desktop/iOS)
      if (reauthAccount == null) {
        // Browser was launched - app will handle completion on resume via _checkReauthCompletion
        // Clear auth failure provider temporarily - _checkReauthCompletion will handle it
        // ignore: avoid_print
        print('[home] Re-auth: browser launched or failed, app will handle completion on resume');
        ref.read(authFailureProvider.notifier).state = null;
        return;
      }

      // Re-authentication completed successfully (returned account)
      if (reauthAccount.accessToken.isEmpty) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(isConnectionError 
                ? 'Reconnection failed. Please check your internet connection.'
                : 'Re-authentication failed or cancelled'),
          ),
        );
        // Re-trigger dialog
        ref.read(authFailureProvider.notifier).state = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(authFailureProvider.notifier).state = accountId;
          }
        });
        return;
      }

      // Success - clear error and provider
      auth.clearLastError(accountId);
      if (ref.read(authFailureProvider) == accountId) {
        ref.read(authFailureProvider.notifier).state = null;
      }
      
      // Reload accounts to get updated tokens
      await _loadAccounts();
      if (!mounted) return;
      
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(isConnectionError 
              ? 'Reconnected successfully'
              : 'Re-authentication successful'),
        ),
      );
      
      // Reload emails with new tokens
      if (_selectedAccountId == accountId) {
        ref.read(emailListProvider.notifier)
            .loadEmails(accountId, folderLabel: _selectedFolder);
      }
    } catch (e, stackTrace) {
      // Log any errors that occur during re-auth handling
      // ignore: avoid_print
      print('[home] Error handling re-auth for account=$accountId: $e');
      // ignore: avoid_print
      print('[home] Stack trace: $stackTrace');
      // Re-trigger dialog if needed (only if provider is not already set to this account)
      if (mounted) {
        final current = ref.read(authFailureProvider);
        if (current != accountId) {
          ref.read(authFailureProvider.notifier).state = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(authFailureProvider.notifier).state = accountId;
            }
          });
        }
      }
    }
  }

  // Selected action summary filter (null = no filter / show all)
  String? _selectedActionFilter;

  // Email state filter (single-select or none)
  String? _stateFilter; // 'Unread' | 'Starred' | 'Important' | null
  final Set<String> _selectedCategories = {};
  bool _showFilterBar = false;

  // Search filter
  bool _showSearch = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final FirebaseSyncService _firebaseSync = FirebaseSyncService();
  final LocalFolderService _localFolderService = LocalFolderService();

  // Table view selected emails
  int _tableSelectedCount = 0;
  Set<String> _tableSelectedEmailIds = {};

  // Panel collapse state
  bool _leftPanelCollapsed = false;
  bool _rightPanelCollapsed = false;

  // Lightweight accounts load that does NOT touch Firebase sync
  Future<void> _loadAccountsLight() async {
    final svc = GoogleAuthService();
    final list = await svc.loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = list;
    });
  }

  Future<void> _loadAccounts() async {
    if (_isAccountsRefreshing) return;
    _isAccountsRefreshing = true;
    try {
      final svc = GoogleAuthService();
      final list = await svc.loadAccounts();
      if (!mounted) return;

      // Check if selected account is still valid
      bool needsAccountSelection = false;
      if (_selectedAccountId == null) {
        needsAccountSelection = list.isNotEmpty;
      } else if (list.isNotEmpty &&
          !list.any((acc) => acc.id == _selectedAccountId)) {
        // Selected account no longer exists in list
        needsAccountSelection = true;
        setState(() {
          _selectedAccountId = null;
        });
      }

      setState(() {
        _accounts = list;
      });

      // If accounts list is empty, clear selected account and emails
      if (list.isEmpty) {
        if (_selectedAccountId != null) {
          setState(() {
            _selectedAccountId = null;
          });
          ref.read(emailListProvider.notifier).clearEmails();
        }
      }
      // If no account is selected but accounts exist, select one
      else if (needsAccountSelection && list.isNotEmpty) {
        // Try to load last active account from preferences
        final lastAccount = await _loadLastActiveAccount();
        if (lastAccount != null && list.any((acc) => acc.id == lastAccount)) {
          _selectedAccountId = lastAccount;
        } else {
          _selectedAccountId = list.first.id;
        }
        // Save the selected account as last active
        if (_selectedAccountId != null) {
          await _saveLastActiveAccount(_selectedAccountId!);
        }
        // Load emails for the selected account
        if (_selectedAccountId != null) {
          await ref
              .read(emailListProvider.notifier)
              .loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
        }
      }

      // Refresh unread counts in background (non-blocking)
      // Use local DB first for instant display, then refresh from API
      unawaited(_refreshAccountUnreadCounts());

      // Initialize Firebase sync if enabled and an account is selected
      final syncEnabled = await _firebaseSync.isSyncEnabled();
      if (syncEnabled && _selectedAccountId != null && list.isNotEmpty) {
        // Set callback to update provider state when Firebase updates are applied
        try {
          _firebaseSync.onUpdateApplied =
              (messageId, localTag, actionDate, actionText, actionComplete, {bool preserveExisting = true}) {
            // Update provider state to reflect Firebase changes in UI
            ref
                .read(emailListProvider.notifier)
                .setLocalTag(messageId, localTag);
            ref.read(emailListProvider.notifier).setAction(
                  messageId,
                  actionDate,
                  actionText,
                  actionComplete: actionComplete,
                  preserveExisting: preserveExisting,
                );
          };

          // Firebase sync will be initialized after local emails are loaded (via email_list_provider)
          // Load sender preferences from Firebase on startup (after Firebase sync is ready)
          unawaited(_loadSenderPrefsFromFirebase());
        } catch (e) {
          // Selected account not found in list - stop Firebase sync
          debugPrint(
              '[HomeScreen] Selected account $_selectedAccountId not found, stopping Firebase sync');
          await _firebaseSync.initializeUser(null);
        }
      } else if (syncEnabled && _selectedAccountId == null) {
        // No account selected - stop Firebase sync
        await _firebaseSync.initializeUser(null);
      }
    } finally {
      _isAccountsRefreshing = false;
    }
  }

  /// Ensure account is authenticated for user-initiated actions.
  /// Shows dialog if needed. Returns true if authenticated.
  Future<bool> _ensureAccountAuthenticated(
    String accountId, {
    String? accountEmail,
  }) async {
    final auth = GoogleAuthService();
    final account = await auth.ensureValidAccessToken(accountId);
    if (account != null && account.accessToken.isNotEmpty) {
      return true;
    }

    // Account needs authentication
    // Dialog will be shown automatically when incremental sync fails for this account
    // For now, just return false - user can try manual refresh which will trigger sync and show dialog if needed
    return false;
  }

  /// Determine feedback type based on original and user actions
  FeedbackType? _determineFeedbackType(
      ActionResult? original, ActionResult? user) {
    if (original == null && user == null) return null; // No change
    if (original == null && user != null) {
      return FeedbackType.falseNegative; // User added action
    }
    if (original != null && user == null) {
      return FeedbackType.falsePositive; // User removed action
    }

    // Both exist - check if they're different
    final originalStr =
        '${original!.actionDate.toIso8601String()}_${original.insightText}';
    final userStr = '${user!.actionDate.toIso8601String()}_${user.insightText}';

    if (originalStr == userStr) {
      return FeedbackType.confirmation; // User confirmed
    } else {
      return FeedbackType.correction; // User corrected
    }
  }

  Future<void> _handleActionUpdate(
    MessageIndex message,
    DateTime? date,
    String? text, {
    bool? actionComplete,
  }) async {
    final originalAction = message.hasAction
        ? ActionResult(
            actionDate: message.actionDate ?? DateTime.now(),
            confidence: message.actionConfidence ?? 0.0,
            insightText: message.actionInsightText ?? '',
          )
        : null;

    await _messageRepository.updateAction(
      message.id,
      date,
      text,
      null,
      actionComplete,
    );
    ref.read(emailListProvider.notifier).setAction(
          message.id,
          date,
          text,
          actionComplete: actionComplete,
        );

    final hasActionNow = text != null && text.isNotEmpty;
    final userAction = hasActionNow
        ? ActionResult(
            actionDate: date ?? DateTime.now(),
            confidence: 1.0,
            insightText: text!,
          )
        : null;

    final feedbackType = _determineFeedbackType(originalAction, userAction);
    if (feedbackType != null) {
      await MLActionExtractor.recordFeedback(
        messageId: message.id,
        subject: message.subject,
        snippet: message.snippet ?? '',
        detectedResult: originalAction,
        userCorrectedResult: userAction,
        feedbackType: feedbackType,
      );
    }

    final syncEnabled = await _firebaseSync.isSyncEnabled();
    if (syncEnabled) {
      final currentDate = message.actionDate;
      final currentText = message.actionInsightText;
      final currentComplete = message.actionComplete;
      if (currentDate != date ||
          currentText != text ||
          currentComplete != actionComplete ||
          !hasActionNow) {
        await _firebaseSync.syncEmailMeta(
          message.id,
          actionDate: hasActionNow ? date : null,
          actionInsightText: hasActionNow ? text : null,
          actionComplete: hasActionNow ? actionComplete : null,
          clearAction: !hasActionNow,
        );
      }
    }
  }

  Future<void> _loadSenderPrefsFromFirebase() async {
    if (!await _firebaseSync.isSyncEnabled()) return;

    try {
      // This will be handled by the Firebase listener in the sync service
      // We just need to ensure it's initialized
      debugPrint(
          '[HomeScreen] Firebase sync initialized, sender prefs will sync automatically');
    } catch (e) {
      debugPrint('[HomeScreen] Error loading sender prefs from Firebase: $e');
    }
  }

  Future<String?> _loadLastActiveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastActiveAccountId');
  }

  Future<void> _saveLastActiveAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastActiveAccountId', accountId);
  }

  Future<void> _showAccountSelectorDialog() async {
    final now = DateTime.now();
    if (_lastAccountTap != null &&
        now.difference(_lastAccountTap!).inMilliseconds < 200) {
      return;
    }
    _lastAccountTap = now;
    if (_isOpeningAccountDialog) return;
    setState(() {
      _isOpeningAccountDialog = true;
    });
    try {
      // Ensure we have an account list, but don't block dialog on Firebase sync
      if (_accounts.isEmpty) {
        await _loadAccountsLight();
      }
      if (!mounted) return;
      final selectedAccount = await showDialog<String>(
        context: context,
        builder: (context) => AccountSelectorDialog(
          accounts: _accounts,
          selectedAccountId: _selectedAccountId,
        ),
      );
      // Reload accounts to ensure new account is in the list
      // Set the selected account BEFORE calling _loadAccounts() so it doesn't get reset
      if (selectedAccount != null) {
        setState(() {
          _selectedAccountId = selectedAccount;
          _isLocalFolder = false; // Ensure we're viewing Gmail folders, not local folders
        });
      }
      await _loadAccounts();
      if (!mounted) return;
      if (selectedAccount != null) {
        // Verify the account still exists in the list (should be there after reload)
        if (_accounts.any((acc) => acc.id == selectedAccount)) {
          // Allow account selection even if token is invalid
          // Dialog will be shown automatically when incremental sync fails
          _pendingLocalUnreadAccounts.add(selectedAccount);
          // Ensure _selectedAccountId is still set (in case _loadAccounts() reset it)
          if (_selectedAccountId != selectedAccount) {
            setState(() {
              _selectedAccountId = selectedAccount;
              _isLocalFolder = false; // Ensure we're not viewing a local folder
            });
          } else {
            // Also ensure _isLocalFolder is false if it wasn't already set
            if (_isLocalFolder) {
              setState(() {
                _isLocalFolder = false;
              });
            }
          }
          await _saveLastActiveAccount(selectedAccount);
          if (kDebugMode) {
            debugPrint('[HomeScreen] Account selected: $selectedAccount');
          }

          // Re-initialize Firebase sync with the new account's email
          final syncEnabled = await _firebaseSync.isSyncEnabled();
          if (syncEnabled) {
            // Set callback to update provider state when Firebase updates are applied
            _firebaseSync.onUpdateApplied =
                (messageId, localTag, actionDate, actionText, actionComplete, {bool preserveExisting = true}) {
              // Update provider state to reflect Firebase changes in UI
              ref
                  .read(emailListProvider.notifier)
                  .setLocalTag(messageId, localTag);
              ref.read(emailListProvider.notifier).setAction(
                    messageId,
                    actionDate,
                    actionText,
                    actionComplete: actionComplete,
                    preserveExisting: preserveExisting,
                  );
            };

            // Firebase sync will be initialized after local emails are loaded (via email_list_provider)
          }

          // Load emails immediately (non-blocking UI update)
          // Then run sync in background (incremental if history exists, initial if not)
          // Firebase sync will start after local load completes
          if (_selectedAccountId != null) {
            // Load emails from local DB immediately (fast UI update)
            await ref
                .read(emailListProvider.notifier)
                .loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);

            // Run sync in background (non-blocking)
            unawaited(Future(() async {
              try {
                final syncService = GmailSyncService();
                await syncService.processPendingOps();
                final hasHistory =
                    await syncService.hasHistoryId(_selectedAccountId!);
                if (hasHistory) {
                  // Account already has history - run incremental sync
                  await syncService.incrementalSync(_selectedAccountId!);
                }
                // If no history, loadEmails already triggered initial sync in background

                // Switch unread count to local after sync
                await _switchUnreadCountToLocal(_selectedAccountId!);
              } catch (e) {
                debugPrint(
                    '[HomeScreen] Error during background sync on account tap: $e');
                await _switchUnreadCountToLocal(_selectedAccountId!);
              }
            }));
          }
        }
      } else {
        // Account selector returned null (e.g., all accounts removed or dialog dismissed)
        // Clear the selected account if no accounts remain
        if (_accounts.isEmpty) {
          setState(() {
            _selectedAccountId = null;
          });
          ref.read(emailListProvider.notifier).clearEmails();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAccountDialog = false;
        });
      } else {
        _isOpeningAccountDialog = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize selected account from route args if provided (e.g., new account sign-in)
    if (!_initializedFromRoute) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final accountIdFromRoute =
          args is String && args.isNotEmpty ? args : null;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Check view mode on startup and set panel state accordingly
        final viewMode = ref.read(viewModeProvider);
        if (mounted) {
          setState(() {
            if (viewMode == ViewMode.table) {
              // Collapse panels for table view
              _leftPanelCollapsed = true;
              _rightPanelCollapsed = true;
            } else {
              // Expand panels for tile view
              _leftPanelCollapsed = false;
              _rightPanelCollapsed = false;
            }
          });
        }
        
        await _loadAccounts();

        // If account ID was provided in route args (new sign-in), always use it and make it active
        if (accountIdFromRoute != null) {
          // Reload accounts again to ensure new account is in the list (in case it was just added)
          await _loadAccounts();
          if (_accounts.any((acc) => acc.id == accountIdFromRoute)) {
            setState(() {
              _selectedAccountId = accountIdFromRoute;
            });
            await _saveLastActiveAccount(accountIdFromRoute);
          }
        } else if (_selectedAccountId == null && _accounts.isNotEmpty) {
          // No route args: try to load last active account from preferences
          final lastAccount = await _loadLastActiveAccount();
          if (lastAccount != null &&
              _accounts.any((acc) => acc.id == lastAccount)) {
            _selectedAccountId = lastAccount;
          } else {
            _selectedAccountId = _accounts.first.id;
          }
          // Save the selected account as last active
          if (_selectedAccountId != null) {
            await _saveLastActiveAccount(_selectedAccountId!);
          }
        }

        if (_selectedAccountId != null) {
          // Load emails - this will trigger initial sync if no history, or incremental sync if history exists
          await ref
              .read(emailListProvider.notifier)
              .loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
        }
        // Load initial unread counts in background (non-blocking) and start periodic refresh
        unawaited(_refreshAccountUnreadCounts());
        _startUnreadCountRefreshTimer();
      });
      _initializedFromRoute = true;
    }

    // Provider listeners extracted to HomeProviderListeners widget
    // Must be called in build method so ref.listen can be used
    // Wrap the scaffold with the listeners widget
    return HomeProviderListeners(
      selectedAccountId: _selectedAccountId,
      pendingLocalUnreadAccounts: _pendingLocalUnreadAccounts,
      onPanelCollapseChanged: (leftCollapsed, rightCollapsed) {
        setState(() {
          _leftPanelCollapsed = leftCollapsed;
          _rightPanelCollapsed = rightCollapsed;
        });
      },
      onHandleReauthNeeded: _handleReauthNeeded,
      onRefreshAccountUnreadCountLocal: _refreshAccountUnreadCountLocal,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          _buildScaffold(context),
          // Floating account widget - above everything including AppBar
          FloatingAccountWidget(
            accounts: _accounts,
            selectedAccountId: _selectedAccountId,
            accountUnreadCounts: _accountUnreadCounts,
            onAccountSelected: (accountId) async {
              await _handleAccountSelected(accountId);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight * 2 + 8.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).appBarTheme.backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                // ------------------------------------
                // TOP ROW: Title + Account selector (centered)
                // ------------------------------------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => ActionsSummaryWindow(),
                        ),
                        child: Text(
                          AppConstants.appName,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: ActionMailTheme.alertColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // ACCOUNT SELECTOR
                      TextButton.icon(
                        onPressed: _isOpeningAccountDialog
                            ? null
                            : _showAccountSelectorDialog,
                        icon: _isOpeningAccountDialog
                            ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).appBarTheme.foregroundColor,
                          ),
                        )
                            : Icon(
                          Icons.account_circle,
                          size: 18,
                          color: Theme.of(context).appBarTheme.foregroundColor,
                        ),
                        label: Text(
                          _selectedAccountId != null && _accounts.isNotEmpty
                              ? _accounts
                                  .firstWhere(
                                      (acc) => acc.id == _selectedAccountId,
                                  orElse: () => _accounts.first)
                                  .email
                              : '',
                          style: TextStyle(
                            color: Theme.of(context).appBarTheme.foregroundColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Small gap between rows
                const SizedBox(height: 0),

                // ------------------------------------
                // BOTTOM ROW: Folder selector + actions
                // ------------------------------------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0),
                  child: Row(
                    children: [
                      // FOLDER DROPDOWN
                      if (!_isLocalFolder)
                        AppDropdown<String>(
                          value: _selectedFolder,
                          items: const ['INBOX', 'SENT', 'TRASH', 'SPAM', 'ARCHIVE'],
                          itemBuilder: (folder) =>
                          AppConstants.folderDisplayNames[folder] ?? folder,
                          textColor: Theme.of(context).appBarTheme.foregroundColor,
                          onChanged: (value) async {
                            if (value != null) {
                              setState(() {
                                _selectedFolder = value;
                                _isLocalFolder = false;
                              });
                              if (_selectedAccountId != null) {
                                await ref.read(emailListProvider.notifier).loadFolder(
                                  _selectedAccountId!,
                                  folderLabel: _selectedFolder,
                                );
                              }
                            }
                          },
                        )
                      else
                        Text(
                          _selectedFolder,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).appBarTheme.foregroundColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                      const SizedBox(width: 8),
                      
                      // Local Folders button (Table View only)
                      Consumer(
                        builder: (context, ref, child) {
                          final viewMode = ref.watch(viewModeProvider);
                          final isDesktop = MediaQuery.of(context).size.width >= 900;
                          if (isDesktop && viewMode == ViewMode.table) {
                            return TextButton.icon(
                              onPressed: () => _showLocalFoldersDialog(context),
                              icon: const Icon(Icons.folder, size: 18),
                              label: Text(
                                'Local Folders',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).appBarTheme.foregroundColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      const Spacer(),

                    // Bulk actions (table view only, when emails are selected)
                      Consumer(
                            builder: (context, ref, child) {
                              final viewMode = ref.watch(viewModeProvider);
                              if (viewMode == ViewMode.table && _tableSelectedCount > 0) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                HomeBulkActionsAppBar(
                                  selectedEmailIds: _tableSelectedEmailIds,
                                  selectedCount: _tableSelectedCount,
                                  selectedFolder: _selectedFolder,
                                  isLocalFolder: _isLocalFolder,
                                  onApplyPersonal: (emails) => _applyBulkPersonalBusiness(emails, 'Personal', ref),
                                  onApplyBusiness: (emails) => _applyBulkPersonalBusiness(emails, 'Business', ref),
                                  onApplyStar: (emails) => _applyBulkStar(emails, ref),
                                  onApplyMove: (emails) => _applyBulkMove(emails, ref),
                                  onApplyArchive: (emails) => _applyBulkArchive(emails, ref),
                                  onApplyTrash: (emails) => _applyBulkTrash(emails, ref),
                                ),
                                    const SizedBox(width: 8),
                                  ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    // View mode toggle (desktop only)
                    Builder(
                      builder: (context) {
                        final isDesktop = MediaQuery.of(context).size.width >= 900;
                        if (isDesktop) {
                          return Consumer(
                            builder: (context, ref, child) {
                              final viewMode = ref.watch(viewModeProvider);
                              return IconButton(
                                icon: Icon(
                                  viewMode == ViewMode.table ? Icons.view_list : Icons.table_chart,
                                  size: 18,
                                  color: Theme.of(context).appBarTheme.foregroundColor,
                                ),
                                onPressed: () {
                                  final newMode = viewMode == ViewMode.table 
                                      ? ViewMode.tile 
                                      : ViewMode.table;
                                  ref.read(viewModeProvider.notifier).setViewMode(newMode);
                                },
                                tooltip: viewMode == ViewMode.table 
                                    ? 'Switch to Tile View' 
                                    : 'Switch to Table View',
                              );
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),
                      // PERSONAL/BUSINESS SWITCH
                      HomeAppBarStateSwitch(
                        selectedLocalState: _selectedLocalState,
                        onStateChanged: (state) {
                          setState(() {
                            _selectedLocalState = state;
                          });
                        },
                      ),
                    const SizedBox(width: 8),

                      // MENU BUTTON
                      HomeMenuButton(
                        selectedAccountId: _selectedAccountId,
                        selectedFolder: _selectedFolder,
                        accounts: _accounts,
                        ensureAccountAuthenticated: _ensureAccountAuthenticated,
                        onRefresh: (accountId, folderLabel) async {
                          await ref
                              .read(emailListProvider.notifier)
                              .refresh(accountId, folderLabel: folderLabel);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    body: Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final viewMode = ref.watch(viewModeProvider);
          final leftWidth = (constraints.maxWidth * 0.20).clamp(200.0, 360.0);
          final rightWidth = (constraints.maxWidth * 0.20).clamp(200.0, 360.0);
          final collapsedWidth = 40.0;
          
          // Temporarily hide left and right panels in TableView
          final showPanels = isDesktop && viewMode != ViewMode.table;
          
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showPanels)
                SizedBox(
                  width: _leftPanelCollapsed ? collapsedWidth : leftWidth,
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: _leftPanelCollapsed ? collapsedWidth : leftWidth,
                  child: ClipRect(
                      clipBehavior: Clip.hardEdge,
                      child: HomeLeftPanel(
                        isCollapsed: _leftPanelCollapsed,
                        accounts: _accounts,
                        selectedAccountId: _selectedAccountId,
                        selectedFolder: _selectedFolder,
                        isLocalFolder: _isLocalFolder,
                        accountUnreadCounts: _accountUnreadCounts,
                        pendingLocalUnreadAccounts: _pendingLocalUnreadAccounts,
                        onToggleCollapse: (collapsed) {
                          setState(() {
                            _leftPanelCollapsed = collapsed;
                          });
                        },
                        onAccountSelected: _handleAccountSelected,
                        onFolderSelected: _handleFolderSelected,
                        onEmailDropped: _handleEmailDroppedToFolder,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: ClipRect(child: _buildMainColumn()),
              ),
              if (showPanels)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: _rightPanelCollapsed ? collapsedWidth : rightWidth,
                  child: ClipRect(
                    child: HomeRightPanel(
                      isCollapsed: _rightPanelCollapsed,
                      isLocalFolder: _isLocalFolder,
                      selectedFolder: _selectedFolder,
                      onToggleCollapse: () {
              setState(() {
                          _rightPanelCollapsed = !_rightPanelCollapsed;
              });
            },
                      onFolderSelected: (folderPath) async {
                        // This is a local folder selection from right panel
                  setState(() {
                          _selectedFolder = folderPath;
                          _isLocalFolder = true;
                        });
                        await _loadFolderEmails(folderPath, true);
                      },
                      onEmailDropped: (folderPath, message) async {
                        await _handleEmailDroppedToFolder(folderPath, message);
                      },
                          ),
                        ),
                      ),
                    ],
          );
          },
        ),
      ],
    ),
  );
  }

  // Left panel widget moved to HomeLeftPanel

  // Handler methods for left panel callbacks
  Future<void> _handleAccountSelected(String accountId) async {
    if (accountId != _selectedAccountId) {
                          // Allow account selection even if token is invalid
                          // Dialog will be shown automatically when incremental sync fails
      _pendingLocalUnreadAccounts.add(accountId);
                          setState(() {
        _selectedAccountId = accountId;
                            _isLocalFolder = false;
                            _selectedFolder = AppConstants.folderInbox;
                          });
      await _saveLastActiveAccount(accountId);
                          if (_selectedAccountId != null) {
                            // Load emails from local DB immediately (fast UI update)
                            await ref
                                .read(emailListProvider.notifier)
            .loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);

                            // Run sync in background (non-blocking)
        unawaited(() async {
                              try {
                                final syncService = GmailSyncService();
                                await syncService.processPendingOps();
            final hasHistory =
                await syncService.hasHistoryId(_selectedAccountId!);
                                if (hasHistory) {
                                  // Account already has history - run incremental sync
              await syncService.incrementalSync(_selectedAccountId!);
                                }
                                // If no history, loadEmails already triggered initial sync in background

                                // Switch unread count to local after sync
            await _switchUnreadCountToLocal(_selectedAccountId!);
                              } catch (e) {
                                debugPrint(
                                    '[HomeScreen] Error during background sync on account tap: $e');
            await _switchUnreadCountToLocal(_selectedAccountId!);
                              }
        }());
                          }
                        } else if (_isLocalFolder) {
                          setState(() {
                            _isLocalFolder = false;
                            _selectedFolder = AppConstants.folderInbox;
                          });
                          if (_selectedAccountId != null) {
        await _loadFolderEmails(AppConstants.folderInbox, false);
      }
      await _saveLastActiveAccount(accountId);
    }
  }

  Future<void> _handleFolderSelected(String folderId) async {
                  setState(() {
                    _selectedFolder = folderId;
                    _isLocalFolder = false; // Reset to Gmail folder
                  });
                  if (_selectedAccountId != null) {
                    await ref.read(emailListProvider.notifier).loadFolder(
                        _selectedAccountId!,
            folderLabel: _selectedFolder,
          );
                  }
  }

  Future<void> _handleEmailDroppedToFolder(String folderId, MessageIndex message) async {
                  if (_isLocalFolder) {
                    if (folderId.toUpperCase() != 'INBOX') {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Local emails can only be restored to Inbox')),
                        );
                      }
                      return;
                    }
                    await _restoreLocalEmailToInbox(message);
                    return;
                  }

                  if (_selectedAccountId == null) return;
                  try {
                    // Optimistic UI update first
                    if (folderId == 'TRASH') {
                      HomeScreenHelpers.updateFolderOptimistic(
                        ref: ref,
                        messageId: message.id,
                        currentFolder: _selectedFolder,
                        targetFolder: 'TRASH',
                      );
                      final prev = message.folderLabel;
                      if (prev.toUpperCase() == 'ARCHIVE') {
                        // ARCHIVE -> TRASH: do not change prevFolderLabel
                        unawaited(_messageRepository
                            .updateFolderNoPrev(message.id, 'TRASH'));
                      } else {
                        unawaited(_messageRepository.updateFolderWithPrev(
                          message.id,
                          'TRASH',
                          prevFolderLabel: prev,
                        ));
                      }
        _enqueueGmailUpdate('trash:${prev.toUpperCase()}', message.id);
                    } else if (folderId == 'ARCHIVE') {
                      HomeScreenHelpers.updateFolderOptimistic(
                        ref: ref,
                        messageId: message.id,
                        currentFolder: _selectedFolder,
                        targetFolder: 'ARCHIVE',
                      );
                      final prev = message.folderLabel;
                      if (prev.toUpperCase() == 'TRASH') {
                        // TRASH -> ARCHIVE: do not change prevFolderLabel
                        unawaited(_messageRepository
                            .updateFolderNoPrev(message.id, 'ARCHIVE'));
                      } else {
                        unawaited(_messageRepository.updateFolderWithPrev(
                          message.id,
                          'ARCHIVE',
                          prevFolderLabel: prev,
                        ));
                      }
        _enqueueGmailUpdate('archive:${prev.toUpperCase()}', message.id);
                    } else if (folderId == 'INBOX') {
                      HomeScreenHelpers.updateFolderOptimistic(
                        ref: ref,
                        messageId: message.id,
                        currentFolder: _selectedFolder,
                        targetFolder: 'INBOX',
                      );
                      final prev = message.folderLabel;
                      unawaited(_messageRepository.updateFolderWithPrev(
                        message.id,
                        'INBOX',
                        prevFolderLabel: prev,
                      ));
                      _enqueueGmailUpdate('moveToInbox', message.id);
                    } else {
                      // Restore to previous folder (if prevFolderLabel matches target)
                      final prevFolder = message.prevFolderLabel;
                      if (prevFolder != null &&
                          prevFolder.toUpperCase() == folderId.toUpperCase()) {
                        // Optimistic: assume restore succeeded; we'll adjust based on refreshed value
                        // Remove from current view if destination differs, else update folder
                        unawaited(() async {
                          await MessageRepository().restoreToPrev(message.id);
                          if (_selectedAccountId != null) {
                            final updated = await MessageRepository()
                                .getByIds(_selectedAccountId!, [message.id]);
                            final restored = updated[message.id];
                            if (restored != null) {
                              final dest = restored.folderLabel;
                              if (_selectedFolder != dest) {
                                ref
                                    .read(emailListProvider.notifier)
                                    .removeMessage(message.id);
                              } else {
                                ref
                                    .read(emailListProvider.notifier)
                                    .setFolder(message.id, dest);
                              }
                _enqueueGmailUpdate('restore:${dest.toUpperCase()}', message.id);
                            }
                          }
                        }());
                      }
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Email moved to ${AppConstants.folderDisplayNames[folderId] ?? folderId}')),
                    );
                  } catch (e) {
      debugPrint('[HomeScreen] Error moving email to Gmail folder: $e');
                    if (!context.mounted) return;
                    {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
  }

  // Left panel widget moved to HomeLeftPanel

  // Right panel widget moved to HomeRightPanel

  /// Load emails for the selected folder (Gmail or local)
  Future<void> _loadFolderEmails(String folderLabel, bool isLocal) async {
    if (isLocal) {
      // Load from local folder service
      final emails = await _localFolderService.loadFolderEmails(folderLabel);
      if (mounted) {
        ref.read(emailListProvider.notifier).setEmails(emails);
      }
    } else {
      // Load from Gmail
      if (_selectedAccountId != null) {
        await ref
            .read(emailListProvider.notifier)
            .loadFolder(_selectedAccountId!, folderLabel: folderLabel);
      }
    }
  }

  // Main content column extracted from previous body
  Widget _buildMainColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Saved List indicator when viewing local folder
        if (_isLocalFolder)
          HomeSavedListIndicator(
            selectedFolder: _selectedFolder,
            onBackToGmail: () {
              if (_selectedAccountId == null) return;
              setState(() {
                _isLocalFolder = false;
                _selectedFolder = AppConstants.folderInbox;
              });
              unawaited(_loadFolderEmails(AppConstants.folderInbox, false));
            },
          ),

        // Filter bar: Top row, state filters, category filter, and search
        HomeFilterBar(
          stateFilter: _stateFilter,
          selectedCategories: _selectedCategories,
          showFilterBar: _showFilterBar,
          showSearch: _showSearch,
          searchQuery: _searchQuery,
          searchController: _searchController,
          selectedActionFilter: _selectedActionFilter,
          selectedLocalState: _selectedLocalState,
          isLocalFolder: _isLocalFolder,
          onStateFilterChanged: (filter) {
                  setState(() {
              _stateFilter = filter;
                  });
                },
          onCategoriesChanged: (categories) {
              setState(() {
              _selectedCategories.clear();
              _selectedCategories.addAll(categories);
              });
            },
          onFilterBarToggled: (show) {
              setState(() {
              if (!show) {
                // Closing FilterBar - reset all filters
                _stateFilter = null;
                _selectedCategories.clear();
                _searchQuery = '';
                _searchController.clear();
                _showSearch = false;
              }
              _showFilterBar = show;
              });
            },
          onSearchToggled: (show) {
              setState(() {
              _showSearch = show;
              if (!show) {
                _searchQuery = '';
                _searchController.clear();
              }
              });
            },
          onSearchQueryChanged: (query) {
              setState(() {
              _searchQuery = query;
              });
            },
          onActionFilterChanged: (filter) {
            setState(() {
              _selectedActionFilter = filter;
            });
          },
          onMarkAllAsRead: _markAllUnreadAsRead,
        ),

        // Email list
        Expanded(
          child: _buildEmailList(),
        ),
      ],
    );
  }

  /// Indicator showing we're viewing a saved list
  // Saved list indicator widget moved to HomeSavedListIndicator

  // Filter bar methods moved to HomeFilterBar widget

  /// Save email to local folder and move to Archive
  Future<void> _saveEmailToFolder(
      String folderName, MessageIndex message) async {
    // Disallow saving to local from Gmail TRASH/ARCHIVE
    final src = (message.folderLabel).toUpperCase();
    if (src == 'TRASH' || src == 'ARCHIVE') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Cannot save from Trash/Archive to local. Move to Inbox/Sent/Spam first.')),
        );
      }
      return;
    }
    // Optimistic UI: reflect archive intent immediately
    if (_selectedAccountId == null) return;
    final wasArchive = message.folderLabel.toUpperCase() == 'ARCHIVE';
    if (!wasArchive) {
      // Remove from current view if not ARCHIVE; otherwise set folder to ARCHIVE
      HomeScreenHelpers.updateFolderOptimistic(
        ref: ref,
        messageId: message.id,
        currentFolder: _selectedFolder,
        targetFolder: 'ARCHIVE',
      );
    }

    // Defer heavy work (token check, body fetch, file IO, DB, Gmail) until after UI paints
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Get access token for downloading email body and attachments
        final account = await GoogleAuthService()
            .ensureValidAccessToken(_selectedAccountId!);
        final accessToken = account?.accessToken;
        if (accessToken == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to save: No access token')),
            );
          }
          return;
        }

        // Fetch full email body
        final gmailService = GmailSyncService();
        final emailBody =
            await gmailService.getEmailBody(message.id, accessToken);
        if (emailBody == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Unable to save: Could not fetch email body')),
            );
          }
          return;
        }

        final accountEmail = HomeScreenHelpers.getAccountEmail(
          message: message,
          accountId: _selectedAccountId,
          accounts: _accounts,
        );

        // Save to local folder
        final saved = await _localFolderService.saveEmailToFolder(
          folderName: folderName,
          message: message,
          emailBodyHtml: emailBody,
          accountId: _selectedAccountId!,
          accountEmail: accountEmail,
          accessToken: accessToken,
        );

        if (saved) {
          if (!wasArchive) {
            // Persist archive intent and enqueue Gmail modify
            await _messageRepository.updateFolderWithPrev(
              message.id,
              'ARCHIVE',
              prevFolderLabel: message.folderLabel,
            );
            final src = message.folderLabel.toUpperCase();
            _enqueueGmailUpdate('archive:$src', message.id);
          }
          if (mounted && _isLocalFolder && _selectedFolder == folderName) {
            final refreshed =
                await _localFolderService.loadFolderEmails(folderName);
            ref.read(emailListProvider.notifier).setEmails(refreshed);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(wasArchive
                      ? 'Email copied to "$folderName"'
                      : 'Email saved to "$folderName" and moved to Archive')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to save email')),
            );
            // Best-effort: refresh current folder to reconcile UI if save failed
            if (_selectedAccountId != null) {
              unawaited(ref
                  .read(emailListProvider.notifier)
                  .refresh(_selectedAccountId!, folderLabel: _selectedFolder));
            }
          }
        }
      } catch (e) {
        debugPrint('[HomeScreen] Error saving email to folder: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
          // Best-effort reconcile
          if (_selectedAccountId != null) {
            unawaited(ref
                .read(emailListProvider.notifier)
                .refresh(_selectedAccountId!, folderLabel: _selectedFolder));
          }
        }
      }
    });
  }

  /// Move email between local folders
  Future<void> _moveLocalEmailToFolder(
      String targetFolderPath, MessageIndex message) async {
    if (_selectedAccountId == null) return;

    try {
      // Get the source folder path (from current selection)
      final sourceFolderPath = _isLocalFolder ? _selectedFolder : null;

      if (sourceFolderPath == null || sourceFolderPath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Unable to move: Source folder not found')),
          );
        }
        return;
      }

      // Load email body from source folder
      final emailBody =
          await _localFolderService.loadEmailBody(sourceFolderPath, message.id);

      if (emailBody == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Unable to move: Could not load email body')),
          );
        }
        return;
      }

      // Get access token for downloading attachments if needed
      final account =
          await GoogleAuthService().ensureValidAccessToken(_selectedAccountId!);
      final accessToken = account?.accessToken;

      if (accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to move: No access token')),
          );
        }
        return;
      }

      final accountEmail = HomeScreenHelpers.getAccountEmail(
        message: message,
        accountId: _selectedAccountId,
        accounts: _accounts,
      );

      // Save to target folder
      final saved = await _localFolderService.saveEmailToFolder(
        folderName: targetFolderPath,
        message: message,
        emailBodyHtml: emailBody,
        accountId: _selectedAccountId!,
        accountEmail: accountEmail,
        accessToken: accessToken,
      );

      if (saved) {
        // Remove from source folder
        await _localFolderService.removeEmailFromFolder(
            sourceFolderPath, message.id);

        // Update provider state if viewing source folder
        if (_isLocalFolder && _selectedFolder == sourceFolderPath) {
          ref.read(emailListProvider.notifier).removeMessage(message.id);
        }

        // If viewing target folder, reload
        if (_isLocalFolder && _selectedFolder == targetFolderPath) {
          await _loadFolderEmails(targetFolderPath, true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Email moved to "$targetFolderPath"')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to move email')),
          );
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error moving local email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _restoreLocalEmailToInbox(MessageIndex message) async {
    var accountId = message.accountId;
    final storedAccountEmail = HomeScreenHelpers.getAccountEmail(
      message: message,
      accountId: message.accountId,
      accounts: _accounts,
    );
    
    if (accountId.isEmpty && storedAccountEmail.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to restore: missing account information')),
        );
      }
      return;
    }

    final sourceFolderPath = _selectedFolder;
    if (sourceFolderPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to restore: source folder unavailable')),
        );
      }
      return;
    }

    debugPrint(
        '[Restore] requested accountId=$accountId local message account=${message.accountId} email=$storedAccountEmail');
    debugPrint(
        '[Restore] Signed-in accounts: ${_accounts.map((a) => '${a.id}:${a.email}').join(', ')}');

    final auth = GoogleAuthService();
    var signedInAccount = _accounts.firstWhere(
      (a) => a.id == accountId,
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

    if (signedInAccount.id.isEmpty && storedAccountEmail.isNotEmpty) {
      signedInAccount = _accounts.firstWhere(
        (a) => a.email.toLowerCase() == storedAccountEmail.toLowerCase(),
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
      if (signedInAccount.id.isNotEmpty) {
        debugPrint(
            '[Restore] Resolved account via email match: ${signedInAccount.email} -> id ${signedInAccount.id}');
        accountId = signedInAccount.id;
      }
    }

    if (signedInAccount.id.isEmpty) {
      debugPrint(
          '[Restore] No matching signed-in account found (wanted id=$accountId email=$storedAccountEmail); aborting restore.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Account not signed in. Add the account in Accounts before restoring.'),
          ),
        );
      }
      return;
    }

    final account = await auth.ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    debugPrint(
        '[Restore] ensureValidAccessToken -> accountId=$accountId email=${account?.email ?? 'unknown'} hasAccount=${account != null} '
        'accessToken=${accessToken != null && accessToken.isNotEmpty} '
        'refreshToken=${(account?.refreshToken ?? '').isNotEmpty} '
        'expiryMs=${account?.tokenExpiryMs}');

    if (accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Google session expired. Re-authenticate via the Accounts menu before restoring.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        Future<void>(() async {
          try {
            debugPrint(
                '[Restore] Calling Gmail restoreMessageToInbox for message=${message.id} account=$accountId email=${account?.email ?? 'unknown'}');
            await GmailSyncService()
                .restoreMessageToInbox(accountId, message.id);
            debugPrint(
                '[Restore] Gmail modify succeeded for message=${message.id} account=$accountId');
            await _messageRepository.updateFolderNoPrev(message.id, 'INBOX');

            await _localFolderService.removeEmailFromFolder(
                sourceFolderPath, message.id);
            debugPrint(
                '[Restore] Removed local copy for message=${message.id}');
            if (mounted) {
              ref.read(emailListProvider.notifier).removeMessage(message.id);
            }

            if (mounted) {
              setState(() {
                _selectedAccountId = accountId;
                _selectedFolder = 'INBOX';
                _isLocalFolder = false;
              });
            }

            if (mounted) {
              await _saveLastActiveAccount(accountId);
              await ref
                  .read(emailListProvider.notifier)
                  .loadFolder(accountId, folderLabel: 'INBOX');
              messenger.showSnackBar(
                const SnackBar(content: Text('Email restored to Inbox')),
              );
            }
          } catch (e) {
            debugPrint('[HomeScreen] Error restoring local email: $e');
            if (mounted) {
              final messageText = e.toString().contains('No access token')
                  ? 'Cannot restore: account session expired. Re-authenticate via Accounts.'
                  : 'Failed to restore email: $e';
              messenger.showSnackBar(SnackBar(content: Text(messageText)));
            }
          } finally {
            if (mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
          }
        });

        return const ProcessingDialog(message: 'Restoring to Inbox...');
      },
    );
  }

  // Placeholder for background Gmail update scheduling
  void _enqueueGmailUpdate(String action, String messageId) {
    if (_selectedAccountId == null) return;
    // Enqueue to DB; processing is triggered by refresh/incremental sync
    MessageRepository()
        .enqueuePendingOp(_selectedAccountId!, messageId, action);
    // Trigger background processing after current frame to allow optimistic UI to paint first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(GmailSyncService().processPendingOps());
    });
  }

  // _buildTopFilterRow and _buildActionFilterTextButton moved to HomeFilterBar widget

  // AppBar state switch widget moved to HomeAppBarStateSwitch
  // _buildActionFilterTextButton moved to HomeFilterBar widget

  Widget _buildEmailList() {
    final emailListAsync = ref.watch(emailListProvider);
    final isSyncing = ref.watch(emailSyncingProvider);
    final isLoadingLocal = ref.watch(emailLoadingLocalProvider);
    final viewMode = ref.watch(viewModeProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    // Check if we should show table view
    if (isDesktop && viewMode == ViewMode.table) {
      return emailListAsync.when(
        data: (emails) {
          // Apply filters using helper function
          final filtered = HomeEmailListFilter.filterEmails(
            emails: emails,
            selectedLocalState: _selectedLocalState,
            stateFilter: _stateFilter,
            selectedCategories: _selectedCategories,
            selectedActionFilter: _selectedActionFilter,
            searchQuery: _searchQuery,
          );

          // Build active filters set for GridEmailList
          final activeFilters = HomeEmailListFilter.buildActiveFilters(
            stateFilter: _stateFilter,
            selectedLocalState: _selectedLocalState,
            selectedActionFilter: _selectedActionFilter,
          );

          // Get account emails for dropdown
          final accountEmails = _accounts.map((a) => a.email).toList();

          // Get local folders
          final localFolders = _localFolderService.listFolders();

          return FutureBuilder<List<String>>(
            future: localFolders,
            builder: (context, snapshot) {
              final localFoldersList = snapshot.data ?? [];

              return GridEmailList(
                emails: filtered,
                selectedFolder: _selectedFolder,
                selectedAccountEmail: _selectedAccountId != null && _accounts.isNotEmpty
                    ? _accounts.firstWhere(
                        (acc) => acc.id == _selectedAccountId,
                        orElse: () => _accounts.first,
                      ).email
                    : null,
                availableAccounts: accountEmails,
                localFolders: localFoldersList,
                isLocalFolder: _isLocalFolder,
                activeFilters: activeFilters,
                selectedEmailIds: _tableSelectedEmailIds,
                onActionUpdated: (email, date, text, {bool? actionComplete}) async {
                  await _handleActionUpdate(
                    email,
                    date,
                    text,
                    actionComplete: actionComplete,
                  );
                },
                onSelectionChanged: (count) {
                  setState(() {
                    _tableSelectedCount = count;
                  });
                },
                onSelectedIdsChanged: (ids) {
                  setState(() {
                    _tableSelectedEmailIds = ids;
                  });
                },
                onFolderChanged: (folder) async {
                  if (folder != null) {
                    setState(() {
                      _selectedFolder = folder;
                      _isLocalFolder = false;
                    });
                    await _loadFolderEmails(folder, false);
                  }
                },
                onAccountChanged: (account) async {
                  if (account != null) {
                    final accountId = _accounts.firstWhere(
                      (a) => a.email == account,
                      orElse: () => _accounts.first,
                    ).id;
                    setState(() {
                      _selectedAccountId = accountId;
                    });
                    await _saveLastActiveAccount(accountId);
                    await _loadAccounts();
                  }
                },
                onToggleLocalFolderView: () async {
                  setState(() {
                    _isLocalFolder = !_isLocalFolder;
                    if (_isLocalFolder && localFoldersList.isNotEmpty) {
                      _selectedFolder = localFoldersList.first;
                    } else {
                      _selectedFolder = AppConstants.folderInbox;
                    }
                  });
                  await _loadFolderEmails(_selectedFolder, _isLocalFolder);
                },
                onLocalFolderSelected: (folderPath) async {
                  // Handle local folder selection from dialog (same as right panel)
                  setState(() {
                    _selectedFolder = folderPath;
                    _isLocalFolder = true;
                  });
                  await _loadFolderEmails(folderPath, true);
                },
                onEmailTap: (email) {
                  if (_selectedAccountId != null) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => EmailViewerDialog(
                        message: email,
                        accountId: _selectedAccountId!,
                        localFolderName: _isLocalFolder ? _selectedFolder : null,
                        onMarkRead: () async {
                          if (!email.isRead && !_isLocalFolder) {
                            await _messageRepository.updateRead(email.id, true);
                            ref.read(emailListProvider.notifier).setRead(email.id, true);
                            _enqueueGmailUpdate('markRead', email.id);
                          }
                        },
                      ),
                    );
                  }
                },
                onPersonalBusinessToggle: (email) async {
                  final newState = email.localTagPersonal;
                  await _messageRepository.updateLocalTag(email.id, newState);
                  ref.read(emailListProvider.notifier).setLocalTag(email.id, newState);
                  
                  final syncEnabled = await _firebaseSync.isSyncEnabled();
                  if (syncEnabled) {
                    try {
                      await _firebaseSync.syncEmailMeta(email.id, localTagPersonal: newState);
                    } catch (e) {
                      debugPrint('[HomeScreen] ERROR in syncEmailMeta: $e');
                    }
                  }
                  
                  final senderEmail = _extractEmail(email.from);
                  if (senderEmail.isNotEmpty) {
                    await MessageRepository().setSenderDefaultLocalTag(senderEmail, newState);
                  }
                },
                onStarToggle: (email) async {
                  await _messageRepository.updateStarred(email.id, !email.isStarred);
                  ref.read(emailListProvider.notifier).setStarred(email.id, !email.isStarred);
                  _enqueueGmailUpdate(!email.isStarred ? 'star' : 'unstar', email.id);
                },
                onTrash: (email) async {
                  if (!_isLocalFolder && _selectedAccountId != null) {
                    final prev = email.folderLabel;
                    // Optimistic UI update first
                    HomeScreenHelpers.updateFolderOptimistic(
                      ref: ref,
                      messageId: email.id,
                      currentFolder: _selectedFolder,
                      targetFolder: 'TRASH',
                    );
                    // Database update in background
                    unawaited(_messageRepository.updateFolderNoPrev(email.id, 'TRASH'));
                    _enqueueGmailUpdate('trash:${prev.toUpperCase()}', email.id);
                  }
                },
                onArchive: (email) async {
                  if (!_isLocalFolder && _selectedAccountId != null) {
                    final prev = email.folderLabel;
                    // Optimistic UI update first
                    HomeScreenHelpers.updateFolderOptimistic(
                      ref: ref,
                      messageId: email.id,
                      currentFolder: _selectedFolder,
                      targetFolder: 'ARCHIVE',
                    );
                    // Database update in background
                    unawaited(_messageRepository.updateFolderNoPrev(email.id, 'ARCHIVE'));
                    _enqueueGmailUpdate('archive:${prev.toUpperCase()}', email.id);
                  }
                },
                onMoveToLocalFolder: (email) async {
                  final folder = await MoveToFolderDialog.show(context);
                  if (folder != null) {
                    if (_isLocalFolder) {
                      // Moving between local folders
                      await _moveLocalEmailToFolder(folder, email);
                    } else {
                      // Saving from Gmail to local folder
                      await _saveEmailToFolder(folder, email);
                    }
                  }
                },
                onRestoreToInbox: _isLocalFolder
                    ? (email) => _restoreLocalEmailToInbox(email)
                    : null,
                onRestore: (email) async {
                  if (!_isLocalFolder && _selectedAccountId != null) {
                    // Optimistic: remove from current view immediately; background restore will adjust
                    ref.read(emailListProvider.notifier).removeMessage(email.id);
                    unawaited(() async {
            await _messageRepository.restoreToPrev(email.id);
                      if (_selectedAccountId != null) {
              final updated = await _messageRepository
                            .getByIds(_selectedAccountId!, [email.id]);
                        final restored = updated[email.id];
                        if (restored != null) {
                          final dest = restored.folderLabel;
                          _enqueueGmailUpdate('restore:${dest.toUpperCase()}', email.id);
                        }
                      }
                    }());
                  }
                },
                onMoveToInbox: (email) async {
                  if (!_isLocalFolder && _selectedAccountId != null) {
                    // Optimistic UI update first
                    HomeScreenHelpers.updateFolderOptimistic(
                      ref: ref,
                      messageId: email.id,
                      currentFolder: _selectedFolder,
                      targetFolder: 'INBOX',
                    );
                    unawaited(_messageRepository.updateFolderWithPrev(
                      email.id,
                      'INBOX',
                      prevFolderLabel: email.folderLabel,
                    ));
                    _enqueueGmailUpdate('moveToInbox', email.id);
                  }
                },
                onFiltersChanged: (filters) {
                  setState(() {
                    _stateFilter = filters.contains('unread') ? 'Unread' 
                        : filters.contains('starred') ? 'Starred' 
                        : null;
                    _selectedLocalState = filters.contains('personal') ? 'Personal'
                        : filters.contains('business') ? 'Business'
                        : null;
                    _selectedActionFilter = filters.contains('action_today') ? AppConstants.filterToday
                        : filters.contains('action_upcoming') ? AppConstants.filterUpcoming
                        : filters.contains('action_overdue') ? AppConstants.filterOverdue
                        : filters.contains('action_possible') ? AppConstants.filterPossible
                        : null;
                  });
                },
                onEmailAction: (email) async {
                  // Read directly from database FIRST - this is the source of truth
                  // Don't trust provider state as it may be stale
                  var currentEmail = email;
                  try {
                    final dbEmail = await _messageRepository.getById(email.id);
                    if (dbEmail != null) {
                      // Use database value as source of truth for action data
                      if (kDebugMode) {
                        debugPrint('[USER_ACTION] READ_BEFORE_DIALOG messageId=${email.id}');
                        debugPrint('[USER_ACTION] Provider actionText=${email.actionInsightText}, hasAction=${email.hasAction}');
                        debugPrint('[USER_ACTION] DB actionText=${dbEmail.actionInsightText}, hasAction=${dbEmail.hasAction}');
                      }
                      // Use DB values for action fields - DB is source of truth
                      currentEmail = currentEmail.copyWith(
                        actionDate: dbEmail.actionDate,
                        actionInsightText: dbEmail.actionInsightText,
                        actionComplete: dbEmail.actionComplete,
                        hasAction: dbEmail.hasAction,
                      );
                    }
                  } catch (e) {
                    debugPrint('[HomeScreen] Error reading email from DB: $e');
                    // Fallback to provider state if DB read fails
                    final emailList = ref.read(emailListProvider);
                    currentEmail = emailList.maybeWhen(
                      data: (emails) => emails.firstWhere(
                        (e) => e.id == email.id,
                        orElse: () => email,
                      ),
                      orElse: () => email,
                    );
                  }
                  
                  if (!context.mounted) return;
                  
                  final result = await ActionEditDialog.show(
                    context,
                    initialDate: currentEmail.actionDate,
                    initialText: currentEmail.actionInsightText,
                    initialComplete: currentEmail.actionComplete,
                    allowRemove: currentEmail.hasAction,
                  );

                    if (result != null) {
                    final removed = result.removed;
                    final actionDate = removed ? null : result.actionDate;
                    final actionText = removed
                        ? null
                        : (result.actionText != null && result.actionText!.isNotEmpty ? result.actionText : null);
                    // Source of truth: actionInsightText determines if action exists
                    final hasActionNow = !removed && (actionText != null && actionText.isNotEmpty);
                    final bool? markedComplete = result.actionComplete;

                    final currentComplete = hasActionNow
                        ? (markedComplete ?? currentEmail.actionComplete)
                        : false;

                    // Debug: Print email enum actionText before update
                    if (kDebugMode) {
                      debugPrint('[USER_ACTION] EDIT messageId=${currentEmail.id}');
                      debugPrint('[USER_ACTION] Email enum actionText=${currentEmail.actionInsightText}, hasAction=${currentEmail.hasAction}');
                    }

                    await _messageRepository.updateAction(currentEmail.id, actionDate, actionText, null, currentComplete);
                    ref.read(emailListProvider.notifier).setAction(
                      currentEmail.id,
                      actionDate,
                      actionText,
                      actionComplete: currentComplete,
                    );

                    // Debug: Read back from DB to verify
                    if (kDebugMode) {
                      try {
                        final dbEmail = await _messageRepository.getById(currentEmail.id);
                        debugPrint('[USER_ACTION] DB actionText=${dbEmail?.actionInsightText}, hasAction=${dbEmail?.hasAction}');
                      } catch (e) {
                        debugPrint('[USER_ACTION] Error reading from DB: $e');
                      }
                    }

                    final syncEnabled = await _firebaseSync.isSyncEnabled();
                    if (syncEnabled && _selectedAccountId != null) {
                      try {
                        if (kDebugMode) {
                          debugPrint('[USER_ACTION] SYNC_TO_FIREBASE messageId=${currentEmail.id}, actionText=$actionText, hasAction=$hasActionNow');
                        }
                        await _firebaseSync.syncEmailMeta(
                          currentEmail.id,
                          actionDate: actionDate,
                          actionInsightText: actionText,
                          actionComplete: currentComplete,
                          clearAction: !hasActionNow,
                        );
                      } catch (e) {
                        debugPrint('[HomeScreen] ERROR in syncEmailMeta: $e');
                      }
                    }
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error: $error'),
        ),
      );
    }

    // Tile view (original implementation)
    return emailListAsync.when(
      data: (emails) {
        // Apply filters using helper function
        final filtered = HomeEmailListFilter.filterEmails(
          emails: emails,
          selectedLocalState: _selectedLocalState,
          stateFilter: _stateFilter,
          selectedCategories: _selectedCategories,
          selectedActionFilter: _selectedActionFilter,
          searchQuery: _searchQuery,
        );

        final filterBanner = HomeFilterBanner(
          selectedLocalState: _selectedLocalState,
          selectedActionFilter: _selectedActionFilter,
          stateFilter: _stateFilter,
          selectedCategories: _selectedCategories,
          searchQuery: _searchQuery,
          searchController: _searchController,
          onClearFilters: _clearAllFilters,
        );

        final content = Column(
          children: [
            if (isLoadingLocal || isSyncing)
              const LinearProgressIndicator(minHeight: 2),
            filterBanner,
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (_selectedAccountId != null) {
                    await ref.read(emailListProvider.notifier).refresh(
                        _selectedAccountId!,
                        folderLabel: _selectedFolder);
                  }
                },
                child: filtered.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: 200,
                            child: Center(
                              child: Text(
                                AppConstants.emptyStateNoEmails,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final message = filtered[index];
                          return EmailTile(
                            message: message,
                            isLocalFolder: _isLocalFolder,
                            onRestoreToInbox: _isLocalFolder
                                ? () => _restoreLocalEmailToInbox(message)
                                : null,
                            onTap: () {
                              if (_selectedAccountId != null) {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) => EmailViewerDialog(
                                    message: message,
                                    accountId: _selectedAccountId!,
                                    localFolderName:
                                        _isLocalFolder ? _selectedFolder : null,
                                    onMarkRead: () async {
                                      if (!message.isRead && !_isLocalFolder) {
                                        await _messageRepository
                                            .updateRead(message.id, true);
                                        ref
                                            .read(emailListProvider.notifier)
                                            .setRead(message.id, true);
                                        _enqueueGmailUpdate(
                                            'markRead', message.id);
                                      }
                                    },
                                  ),
                                );
                              }
                            },
                            onMarkRead: () async {
                              if (!message.isRead) {
                                await _messageRepository
                                    .updateRead(message.id, true);
                                ref
                                    .read(emailListProvider.notifier)
                                    .setRead(message.id, true);
                                _enqueueGmailUpdate('markRead', message.id);
                              }
                            },
                            onStarToggle: (newValue) async {
                              await _messageRepository
                                  .updateStarred(message.id, newValue);
                              ref
                                  .read(emailListProvider.notifier)
                                  .setStarred(message.id, newValue);
                              _enqueueGmailUpdate(
                                  newValue ? 'star' : 'unstar', message.id);
                            },
                            onLocalStateChanged: (state) async {
                              // Persist local tag for this message
                              await _messageRepository
                                  .updateLocalTag(message.id, state);

                              // Sync to Firebase if enabled (only if changed from initial value)
                              final syncEnabled =
                                  await _firebaseSync.isSyncEnabled();
                              if (syncEnabled) {
                                // Always sync the localTagPersonal value (even if null, it represents a change)
                                try {
                                  await _firebaseSync.syncEmailMeta(message.id,
                                      localTagPersonal: state);
                                } catch (e) {
                                  // Log errors but don't crash the UI
                                  debugPrint(
                                      '[HomeScreen] ERROR in syncEmailMeta: $e');
                                  if (kReleaseMode) {
                                    debugPrint(
                                        '[HomeScreen] ERROR in syncEmailMeta (release): $e');
                                  }
                                }
                              }

                              // Persist a sender preference (future emails rule)
                              // Note: Sender preferences are NOT synced to Firebase - they are derived
                              // locally from emailMeta changes on other devices
                              final senderEmail = _extractEmail(message.from);
                              if (senderEmail.isNotEmpty) {
                                await _messageRepository
                                    .setSenderDefaultLocalTag(
                                        senderEmail, state);
                              }

                              // Silent update: do not trigger a provider loading state
                              ref
                                  .read(emailListProvider.notifier)
                                  .setLocalTag(message.id, state);
                            },
                            onTrash: () async {
                              // Optimistic UI update first
                              HomeScreenHelpers.updateFolderOptimistic(
                                ref: ref,
                                messageId: message.id,
                                currentFolder: _selectedFolder,
                                targetFolder: 'TRASH',
                              );
                              final src = message.folderLabel.toUpperCase();
                              if (src == 'ARCHIVE') {
                                unawaited(_messageRepository
                                    .updateFolderNoPrev(message.id, 'TRASH'));
                              } else {
                                unawaited(
                                    _messageRepository.updateFolderWithPrev(
                                  message.id,
                                  'TRASH',
                                  prevFolderLabel: message.folderLabel,
                                ));
                              }
                              _enqueueGmailUpdate('trash:$src', message.id);

                              // If viewing a local folder, also remove the saved local copy (additional process)
                              if (_isLocalFolder) {
                                final localPath = _selectedFolder;
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  unawaited(
                                      _localFolderService.removeEmailFromFolder(
                                          localPath, message.id));
                                });
                              }
                            },
                            onArchive: () async {
                              // Optimistic UI update first
                              HomeScreenHelpers.updateFolderOptimistic(
                                ref: ref,
                                messageId: message.id,
                                currentFolder: _selectedFolder,
                                targetFolder: 'ARCHIVE',
                              );
                              final src = message.folderLabel.toUpperCase();
                              if (src == 'TRASH') {
                                unawaited(_messageRepository
                                    .updateFolderNoPrev(message.id, 'ARCHIVE'));
                              } else {
                                unawaited(
                                    _messageRepository.updateFolderWithPrev(
                                  message.id,
                                  'ARCHIVE',
                                  prevFolderLabel: message.folderLabel,
                                ));
                              }
                              _enqueueGmailUpdate('archive:$src', message.id);
                            },
                            onSaveToFolder: (folderName) async {
                              if (_isLocalFolder) {
                                // Moving between local folders
                                await _moveLocalEmailToFolder(folderName, message);
                              } else {
                                // Saving from Gmail to local folder
                                await _saveEmailToFolder(folderName, message);
                              }
                            },
                            onMoveToLocalFolder: () async {
                              // Show folder selection dialog
                              final folder = await MoveToFolderDialog.show(context);
                              if (folder != null) {
                                if (_isLocalFolder) {
                                  // Moving between local folders
                                  await _moveLocalEmailToFolder(folder, message);
                                } else {
                                  // Saving from Gmail to local folder
                                  await _saveEmailToFolder(folder, message);
                                }
                              }
                            },
                            onMoveToInbox: () async {
                              // Optimistic UI update first
                              HomeScreenHelpers.updateFolderOptimistic(
                                ref: ref,
                                messageId: message.id,
                                currentFolder: _selectedFolder,
                                targetFolder: 'INBOX',
                              );
                              unawaited(
                                  _messageRepository.updateFolderWithPrev(
                                message.id,
                                'INBOX',
                                prevFolderLabel: message.folderLabel,
                              ));
                              _enqueueGmailUpdate('moveToInbox', message.id);
                            },
                            onRestore: () async {
                              // Optimistic: remove from current view immediately; background restore will adjust
                              ref
                                  .read(emailListProvider.notifier)
                                  .removeMessage(message.id);
                              unawaited(() async {
                                await _messageRepository
                                    .restoreToPrev(message.id);
                                if (_selectedAccountId != null) {
                                  final updated = await _messageRepository
                                      .getByIds(
                                          _selectedAccountId!, [message.id]);
                                  final restored = updated[message.id];
                                  if (restored != null) {
                                    final dest = restored.folderLabel;
                                    if (_selectedFolder == dest) {
                                      ref
                                          .read(emailListProvider.notifier)
                                          .setFolder(message.id, dest);
                                    }
                                    _enqueueGmailUpdate(
                                        'restore:${dest.toUpperCase()}',
                                        message.id);
                                  }
                                }
                              }());
                            },
                            onActionUpdated: (date, text,
                                {bool? actionComplete}) async {
                              await _handleActionUpdate(
                                message,
                                date,
                                text,
                                actionComplete: actionComplete,
                              );
                            },
                            onActionCompleted: () async {
                              await _handleActionUpdate(
                                message,
                                null,
                                null,
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        );
        return content;
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Error loading emails: $error',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (_selectedAccountId != null) {
                  ref
                      .read(emailListProvider.notifier)
                      .refresh(_selectedAccountId!);
                }
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _extractEmail(String from) {
    final regex = RegExp(r'<([^>]+)>');
    final match = regex.firstMatch(from);
    if (match != null) return match.group(1)!.trim();
    if (from.contains('@')) return from.trim();
    return '';
  }

  /// Mark all currently visible unread emails as read
  Future<void> _markAllUnreadAsRead(List<String> messageIds) async {
    if (messageIds.isEmpty || _selectedAccountId == null || _isLocalFolder) {
      return;
    }

    try {
      // Batch update in database
      await _messageRepository.batchUpdateRead(messageIds, true);

      // Update UI state for all messages
      for (final messageId in messageIds) {
        ref.read(emailListProvider.notifier).setRead(messageId, true);
        // Enqueue Gmail API update
        _enqueueGmailUpdate('markRead', messageId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Marked ${messageIds.length} email${messageIds.length == 1 ? '' : 's'} as read'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error marking all as read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking emails as read: $e')),
        );
      }
    }
  }

  /// Start periodic refresh timer for account unread counts (15 minutes)
  void _startUnreadCountRefreshTimer() {
    _unreadCountRefreshTimer?.cancel();
    _unreadCountRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _refreshAccountUnreadCounts();
    });
  }

  /// Refresh unread counts for all accounts
  /// Active account: uses local data only (no API calls) - but switching happens AFTER incremental sync
  /// Inactive accounts: uses local data first, then refreshes from API in background
  Future<void> _refreshAccountUnreadCounts() async {
    if (_accounts.isEmpty) return;

    // Load from local DB for all accounts (instant display)
    final localCounts = <String, int>{};
    for (final account in _accounts) {
      try {
        final localCount = await MessageRepository()
            .getUnreadCountByFolder(account.id, 'INBOX');
        localCounts[account.id] = localCount;
      } catch (_) {
        localCounts[account.id] = 0;
      }
    }

    // Update UI immediately with local counts
    final updatedCounts = Map<String, int>.from(_accountUnreadCounts);
    for (final entry in localCounts.entries) {
      if (_pendingLocalUnreadAccounts.contains(entry.key)) {
        continue;
      }
      updatedCounts[entry.key] = entry.value;
    }
    if (mounted) {
      setState(() {
        _accountUnreadCounts = updatedCounts;
      });
    } else {
      _accountUnreadCounts = updatedCounts;
    }

    // Update app icon badge with total unread count (even when not mounted, since badge is system-level)
    _updateAppIconBadge();

    // Then refresh from API in background for inactive accounts only (non-blocking)
    // Active account will switch to local count AFTER incremental sync (handled in account switch)
    for (final account in _accounts) {
      // Skip API call for active account - it will use local data after incremental sync
      if (account.id == _selectedAccountId) {
        continue;
      }

      // Fire off background refresh for inactive accounts (non-blocking)
      unawaited(() async {
        try {
          final count = await _getGmailUnreadCount(account.id);
          if (mounted) {
            setState(() {
              _accountUnreadCounts[account.id] = count;
            });
            // Update app icon badge after API refresh
            _updateAppIconBadge();
          }
        } catch (_) {
          // Keep local count if API fails - counts already set from local DB above
        }
      }());
    }
  }

  /// Switch unread count to local for a specific account (called after incremental sync)
  Future<void> _switchUnreadCountToLocal(String accountId) async {
    int? localCount;
    try {
      localCount =
          await MessageRepository().getUnreadCountByFolder(accountId, 'INBOX');
    } catch (_) {
      // Keep existing count if refresh fails
    }

    if (!mounted) {
      _pendingLocalUnreadAccounts.remove(accountId);
      if (localCount != null) {
        _accountUnreadCounts[accountId] = localCount;
      }
      // Update badge even when not mounted (system-level feature)
      _updateAppIconBadge();
      return;
    }

    setState(() {
      _pendingLocalUnreadAccounts.remove(accountId);
      if (localCount != null) {
        _accountUnreadCounts[accountId] = localCount;
      }
    });
    // Update app icon badge after switching to local count
    _updateAppIconBadge();
  }

  /// Refresh unread count for a specific account from local DB
  Future<void> _refreshAccountUnreadCountLocal(String accountId) async {
    if (_pendingLocalUnreadAccounts.contains(accountId)) {
      return;
    }
    try {
      final localCount =
          await MessageRepository().getUnreadCountByFolder(accountId, 'INBOX');
      if (mounted) {
        setState(() {
          _accountUnreadCounts[accountId] = localCount;
        });
      } else {
        _accountUnreadCounts[accountId] = localCount;
      }
      // Update app icon badge after local refresh (even when not mounted, since badge is system-level)
      _updateAppIconBadge();
    } catch (_) {
      // Keep existing count if refresh fails
    }
  }

  /// Calculate total unread count across all accounts
  int _calculateTotalUnreadCount() {
    int total = 0;
    for (final count in _accountUnreadCounts.values) {
      total += count;
    }
    return total;
  }

  /// Update app icon badge with total unread count across all accounts
  /// TEMPORARILY DISABLED - re-enable by setting _badgeUpdatesEnabled = true
  static const bool _badgeUpdatesEnabled = false; // Set to true to re-enable badge updates
  
  Future<void> _updateAppIconBadge() async {
    // TEMPORARILY DISABLED - return early if badge updates are disabled
    if (!_badgeUpdatesEnabled) {
      return;
    }
    try {
      final totalUnread = _calculateTotalUnreadCount();
      debugPrint(
          '[Badge] Attempting to update badge. Platform: ${Platform.operatingSystem}, Total unread: $totalUnread, Account counts: $_accountUnreadCounts');

      // Check if app badge is supported on this platform
      // ensemble_app_badger maintains the FlutterAppBadger class name for compatibility
      final isSupported = await FlutterAppBadger.isAppBadgeSupported();
      debugPrint('[Badge] Badge supported: $isSupported');

      if (!isSupported) {
        debugPrint(
            '[Badge] App badge not supported on ${Platform.operatingSystem}. '
            'Badges are supported on iOS, macOS, and some Android devices/launchers (Samsung, HTC, etc.).');
        return;
      }

      if (totalUnread > 0) {
        // Update badge with total unread count
        await FlutterAppBadger.updateBadgeCount(totalUnread);
        debugPrint(
            '[Badge] Successfully updated app icon badge: $totalUnread unread messages');
      } else {
        // Remove badge if no unread messages
        await FlutterAppBadger.removeBadge();
        debugPrint('[Badge] Removed app icon badge (no unread messages)');
      }
    } catch (e, stackTrace) {
      // Log the error with stack trace for debugging
      debugPrint('[Badge] Failed to update app icon badge: $e');
      debugPrint('[Badge] Stack trace: $stackTrace');
    }
  }

  /// Get unread count for an account using Gmail API /users/me/labels/INBOX endpoint
  Future<int> _getGmailUnreadCount(String accountId) async {
    final authAccount =
        await GoogleAuthService().ensureValidAccessToken(accountId);
    if (authAccount == null || authAccount.accessToken.isEmpty) {
      // Fallback to local DB if no token
      return await MessageRepository()
          .getUnreadCountByFolder(accountId, 'INBOX');
    }

    final uri = Uri.parse(
        'https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${authAccount.accessToken}'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['messagesUnread'] as int? ?? 0;
    } else {
      // Fallback to local DB on API error
      return await MessageRepository()
          .getUnreadCountByFolder(accountId, 'INBOX');
    }
  }


  // Filter banner widget moved to HomeFilterBanner

  void _clearAllFilters() {
    setState(() {
      _selectedLocalState = null;
      _selectedActionFilter = null;
      _stateFilter = null;
      _selectedCategories.clear();
      _searchQuery = '';
      _searchController.clear();
      _showSearch = false;
    });
    FocusScope.of(context).unfocus();
  }

  // Menu button widget moved to HomeMenuButton

  /// Configuration for status buttons based on folder (same as GridEmailList)
  // _getStatusButtonConfig moved to HomeBulkActionsAppBar widget

  // Bulk action buttons widget moved to HomeBulkActionsAppBar

  Future<void> _applyBulkPersonalBusiness(List<MessageIndex> emails, String tag, WidgetRef ref) async {
    // Check Firebase sync once before the loop (performance optimization)
    final syncEnabled = await _firebaseSync.isSyncEnabled();
    
    // Batch UI updates first for better perceived performance
    for (final email in emails) {
      ref.read(emailListProvider.notifier).setLocalTag(email.id, tag);
    }
    
    // Process database updates and sync in background
    final syncFutures = <Future<void>>[];
    final senderTags = <String, String>{}; // Deduplicate sender tag updates
    
    for (final email in emails) {
      // Database update
      unawaited(_messageRepository.updateLocalTag(email.id, tag));
      
      // Collect Firebase sync operations
      if (syncEnabled) {
        syncFutures.add(
          _firebaseSync.syncEmailMeta(email.id, localTagPersonal: tag)
              .catchError((e) => debugPrint('[HomeScreen] ERROR in syncEmailMeta: $e')),
        );
      }
      
      // Collect sender tags for batch update (deduplicated)
      final senderEmail = _extractEmail(email.from);
      if (senderEmail.isNotEmpty) {
        senderTags[senderEmail] = tag;
      }
    }
    
    // Batch sender tag updates (one per unique sender)
    for (final entry in senderTags.entries) {
      unawaited(_messageRepository.setSenderDefaultLocalTag(entry.key, entry.value));
    }
    
    // Wait for all Firebase syncs to complete
    await Future.wait(syncFutures);
    
    // Clear selection after bulk action
    _clearBulkSelection();
  }

  Future<void> _applyBulkStar(List<MessageIndex> emails, WidgetRef ref) async {
    // Batch UI updates first for better perceived performance
    for (final email in emails) {
      ref.read(emailListProvider.notifier).setStarred(email.id, !email.isStarred);
      _enqueueGmailUpdate(!email.isStarred ? 'star' : 'unstar', email.id);
    }
    
    // Batch database updates in background
    for (final email in emails) {
      unawaited(_messageRepository.updateStarred(email.id, !email.isStarred));
    }
    
    // Clear selection after bulk action
    _clearBulkSelection();
  }

  Future<void> _applyBulkMove(List<MessageIndex> emails, WidgetRef ref) async {
    final upperFolder = _selectedFolder.toUpperCase();
    
    // Handle folder-specific move actions
    if (upperFolder == 'SPAM') {
      // Spam: Move to Inbox
      for (final email in emails) {
        if (_selectedAccountId != null) {
          // Optimistic UI update first
          HomeScreenHelpers.updateFolderOptimistic(
            ref: ref,
            messageId: email.id,
            currentFolder: _selectedFolder,
            targetFolder: 'INBOX',
          );
          unawaited(_messageRepository.updateFolderWithPrev(
            email.id,
            'INBOX',
            prevFolderLabel: email.folderLabel,
          ));
          _enqueueGmailUpdate('moveToInbox', email.id);
        }
      }
      _clearBulkSelection();
      return;
    } else if (upperFolder == 'TRASH' || upperFolder == 'ARCHIVE') {
      // Trash/Archive: Restore to previous folder
      for (final email in emails) {
        if (!_isLocalFolder && _selectedAccountId != null) {
          // Optimistic: remove from current view immediately; background restore will adjust
          ref.read(emailListProvider.notifier).removeMessage(email.id);
          unawaited(() async {
            await _messageRepository.restoreToPrev(email.id);
            if (_selectedAccountId != null) {
              final updated = await _messageRepository
                  .getByIds(_selectedAccountId!, [email.id]);
              final restored = updated[email.id];
              if (restored != null) {
                final dest = restored.folderLabel;
                _enqueueGmailUpdate('restore:${dest.toUpperCase()}', email.id);
              }
            }
          }());
        }
      }
      _clearBulkSelection();
      return;
    }
    
    // Default: Move to local folder (show folder selection dialog)
    final folder = await MoveToFolderDialog.show(context);
    
    if (folder != null) {
      for (final email in emails) {
        if (_isLocalFolder) {
          // Moving between local folders
          await _moveLocalEmailToFolder(folder, email);
        } else {
          // Saving from Gmail to local folder
          await _saveEmailToFolder(folder, email);
        }
      }
    }
    setState(() {
      _tableSelectedEmailIds.clear();
      _tableSelectedCount = 0;
    });
  }

  Future<void> _applyBulkArchive(List<MessageIndex> emails, WidgetRef ref) async {
    if (_isLocalFolder || _selectedAccountId == null) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Emails'),
        content: Text('Are you sure you want to archive ${emails.length} email${emails.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    // Optimistic UI updates first
    for (final email in emails) {
      HomeScreenHelpers.updateFolderOptimistic(
        ref: ref,
        messageId: email.id,
        currentFolder: _selectedFolder,
        targetFolder: 'ARCHIVE',
      );
    }
    // Clear selection immediately after optimistic update
    _clearBulkSelection();
    
    // Database updates in background
    for (final email in emails) {
      final prev = email.folderLabel;
      unawaited(_messageRepository.updateFolderNoPrev(email.id, 'ARCHIVE'));
      _enqueueGmailUpdate('archive:${prev.toUpperCase()}', email.id);
    }
  }

  Future<void> _applyBulkTrash(List<MessageIndex> emails, WidgetRef ref) async {
    if (_isLocalFolder || _selectedAccountId == null) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trash Emails'),
        content: Text('Are you sure you want to move ${emails.length} email${emails.length == 1 ? '' : 's'} to trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Trash'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    // Optimistic UI updates first
    for (final email in emails) {
      HomeScreenHelpers.updateFolderOptimistic(
        ref: ref,
        messageId: email.id,
        currentFolder: _selectedFolder,
        targetFolder: 'TRASH',
      );
    }
    // Clear selection immediately after optimistic update
    _clearBulkSelection();
    
    // Database updates in background
    for (final email in emails) {
      final prev = email.folderLabel;
      unawaited(_messageRepository.updateFolderNoPrev(email.id, 'TRASH'));
      _enqueueGmailUpdate('trash:${prev.toUpperCase()}', email.id);
    }
  }

  void _clearBulkSelection() {
    setState(() {
      _tableSelectedEmailIds = {}; // Create new empty set to trigger didUpdateWidget
      _tableSelectedCount = 0;
    });
  }

  void _showLocalFoldersDialog(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    final appBarFg = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: SizedBox(
          width: 400,
          height: 600,
          child: Column(
            children: [
              // Header
              Material(
                color: appBarBg,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Local Folders',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: appBarFg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: appBarFg),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // Folder tree
              Expanded(
                child: LocalFolderTree(
                  selectedFolder: _isLocalFolder ? _selectedFolder : null,
                  onFolderSelected: (folderPath) async {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _selectedFolder = folderPath;
                      _isLocalFolder = true;
                    });
                    await _loadFolderEmails(folderPath, true);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

