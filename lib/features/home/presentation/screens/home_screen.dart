import 'package:flutter/material.dart';
import 'package:domail/shared/widgets/app_toggle_chip.dart';
import 'package:domail/shared/widgets/app_dropdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/constants/app_constants.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/features/home/presentation/widgets/email_tile.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/features/settings/presentation/accounts_settings_dialog.dart';
import 'package:domail/features/home/presentation/windows/actions_summary_window.dart';
import 'package:domail/features/home/presentation/windows/attachments_window.dart';
import 'package:domail/features/home/presentation/windows/subscriptions_window.dart';
import 'package:domail/features/home/presentation/windows/shopping_window.dart';
// import 'package:domail/features/home/presentation/windows/actions_window.dart'; // unused
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domail/features/home/presentation/widgets/account_selector_dialog.dart';
import 'package:domail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:domail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:domail/services/actions/ml_action_extractor.dart';
import 'package:domail/services/actions/action_extractor.dart';
import 'package:domail/features/home/presentation/widgets/gmail_folder_tree.dart';
import 'package:domail/features/home/presentation/widgets/local_folder_tree.dart';
import 'package:domail/services/gmail/gmail_sync_service.dart';
import 'package:domail/services/local_folders/local_folder_service.dart';
// duplicate import removed: gmail_sync_service.dart
import 'package:domail/data/models/message_index.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:domail/app/theme/actionmail_theme.dart';

/// Main home screen for ActionMail
/// Displays email list with filters and action management
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _ProcessingDialog extends StatelessWidget {
  final String message;
  const _ProcessingDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
      } else if (list.isNotEmpty && !list.any((acc) => acc.id == _selectedAccountId)) {
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
          await ref.read(emailListProvider.notifier).loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
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
        _firebaseSync.onUpdateApplied = (messageId, localTag, actionDate, actionText, actionComplete) {
          // Update provider state to reflect Firebase changes in UI
          ref.read(emailListProvider.notifier).setLocalTag(messageId, localTag);
          ref.read(emailListProvider.notifier).setAction(
            messageId,
            actionDate,
            actionText,
            actionComplete: actionComplete,
            preserveExisting: true,
          );
        };
        
        // Firebase sync will be initialized after local emails are loaded (via email_list_provider)
        // Load sender preferences from Firebase on startup (after Firebase sync is ready)
        unawaited(_loadSenderPrefsFromFirebase());
      } catch (e) {
        // Selected account not found in list - stop Firebase sync
        debugPrint('[HomeScreen] Selected account $_selectedAccountId not found, stopping Firebase sync');
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

  /// Determine feedback type based on original and user actions
  FeedbackType? _determineFeedbackType(ActionResult? original, ActionResult? user) {
    if (original == null && user == null) return null; // No change
    if (original == null && user != null) return FeedbackType.falseNegative; // User added action
    if (original != null && user == null) return FeedbackType.falsePositive; // User removed action
    
    // Both exist - check if they're different
    final originalStr = '${original!.actionDate.toIso8601String()}_${original.insightText}';
    final userStr = '${user!.actionDate.toIso8601String()}_${user.insightText}';
    
    if (originalStr == userStr) {
      return FeedbackType.confirmation; // User confirmed
    } else {
      return FeedbackType.correction; // User corrected
    }
  }

  Future<void> _loadSenderPrefsFromFirebase() async {
    if (!await _firebaseSync.isSyncEnabled()) return;
    
    try {
      // This will be handled by the Firebase listener in the sync service
      // We just need to ensure it's initialized
      debugPrint('[HomeScreen] Firebase sync initialized, sender prefs will sync automatically');
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
    if (_lastAccountTap != null && now.difference(_lastAccountTap!).inMilliseconds < 200) {
      return;
    }
    _lastAccountTap = now;
    if (_isOpeningAccountDialog) return;
    setState(() { _isOpeningAccountDialog = true; });
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
      await _loadAccounts();
      if (!mounted) return;
      if (selectedAccount != null) {
      // Verify the account still exists in the list (should be there after reload)
      if (_accounts.any((acc) => acc.id == selectedAccount)) {
        _pendingLocalUnreadAccounts.add(selectedAccount);
        setState(() {
          _selectedAccountId = selectedAccount;
        });
        await _saveLastActiveAccount(selectedAccount);
          if (kDebugMode) {
            debugPrint('[HomeScreen] Account selected: $selectedAccount');
          }
        
        // Re-initialize Firebase sync with the new account's email
        final syncEnabled = await _firebaseSync.isSyncEnabled();
        if (syncEnabled) {
          // Set callback to update provider state when Firebase updates are applied
          _firebaseSync.onUpdateApplied = (messageId, localTag, actionDate, actionText, actionComplete) {
            // Update provider state to reflect Firebase changes in UI
            ref.read(emailListProvider.notifier).setLocalTag(messageId, localTag);
          ref.read(emailListProvider.notifier).setAction(
            messageId,
            actionDate,
            actionText,
            actionComplete: actionComplete,
            preserveExisting: true,
          );
          };
          
          // Firebase sync will be initialized after local emails are loaded (via email_list_provider)
        }
        
        // Load emails immediately (non-blocking UI update)
        // Then run sync in background (incremental if history exists, initial if not)
        // Firebase sync will start after local load completes
        if (_selectedAccountId != null) {
          // Load emails from local DB immediately (fast UI update)
          await ref.read(emailListProvider.notifier).loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
          
          // Run sync in background (non-blocking)
          unawaited(Future(() async {
            try {
              final syncService = GmailSyncService();
              await syncService.processPendingOps();
              final hasHistory = await syncService.hasHistoryId(_selectedAccountId!);
              if (hasHistory) {
                // Account already has history - run incremental sync
                await syncService.incrementalSync(_selectedAccountId!);
              }
              // If no history, loadEmails already triggered initial sync in background
              
              // Switch unread count to local after sync
              await _switchUnreadCountToLocal(_selectedAccountId!);
            } catch (e) {
              debugPrint('[HomeScreen] Error during background sync on account tap: $e');
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
        setState(() { _isOpeningAccountDialog = false; });
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
      final accountIdFromRoute = args is String && args.isNotEmpty ? args : null;
      
      WidgetsBinding.instance.addPostFrameCallback((_) async {
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
          if (lastAccount != null && _accounts.any((acc) => acc.id == lastAccount)) {
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
          await ref.read(emailListProvider.notifier).loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
        }
        // Load initial unread counts in background (non-blocking) and start periodic refresh
        unawaited(_refreshAccountUnreadCounts());
        _startUnreadCountRefreshTimer();
      });
      _initializedFromRoute = true;
    }

    // Listen to email list changes and refresh active account's unread count
    ref.listen<AsyncValue<List<MessageIndex>>>(emailListProvider, (previous, next) {
      final activeAccountId = _selectedAccountId;
      if (!mounted || !next.hasValue || activeAccountId == null) {
        return;
      }
      if (_pendingLocalUnreadAccounts.contains(activeAccountId)) {
        return;
      }
      // Refresh active account's unread count from local DB when emails change
      // Use post-frame callback to avoid updating during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_selectedAccountId != activeAccountId) return;
        if (_pendingLocalUnreadAccounts.contains(activeAccountId)) return;
        _refreshAccountUnreadCountLocal(activeAccountId);
      });
    });

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight((kToolbarHeight * 1.4) + MediaQuery.of(context).padding.top),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top row: Title and Account (centered)
                    SizedBox(
                      height: constraints.maxHeight * 0.5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => ActionsSummaryWindow(),
                                );
                              },
                              child: Text(
                                AppConstants.appName,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Theme.of(context).appBarTheme.foregroundColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            TextButton.icon(
                              onPressed: _isOpeningAccountDialog ? null : _showAccountSelectorDialog,
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
                                    ? _accounts.firstWhere((acc) => acc.id == _selectedAccountId, orElse: () => _accounts.first).email
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
                    ),
                    // Bottom row: Folder selector (left) and Filter buttons + Refresh/Settings/Menu (right)
                    SizedBox(
                      height: constraints.maxHeight * 0.5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          children: [
                            // Folder dropdown on left (only show for Gmail folders)
                            if (!_isLocalFolder)
                              AppDropdown<String>(
                                value: _selectedFolder,
                                items: const ['INBOX','SENT','TRASH','SPAM','ARCHIVE'],
                                itemBuilder: (folder) => AppConstants.folderDisplayNames[folder] ?? folder,
                                textColor: Theme.of(context).appBarTheme.foregroundColor,
                                onChanged: (value) async {
                                  if (value != null) {
                                    setState(() {
                                      _selectedFolder = value;
                                      _isLocalFolder = false; // Reset to Gmail folder when using dropdown
                                    });
                                    if (_selectedAccountId != null) {
                                      await ref.read(emailListProvider.notifier).loadFolder(_selectedAccountId!, folderLabel: _selectedFolder);
                                    }
                                  }
                                },
                              )
                            else
                              // Show local folder name as text when viewing local folder
                              Text(
                                _selectedFolder,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).appBarTheme.foregroundColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            const Spacer(),
                            // Personal/Business/All switch
                            _buildAppBarLocalStateSwitch(context),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.menu, size: 18, color: Theme.of(context).appBarTheme.foregroundColor),
                              onSelected: (value) {
                                switch (value) {
                                  case 'Compose':
                                    if (_selectedAccountId != null) {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => ComposeEmailDialog(
                                          accountId: _selectedAccountId!,
                                          mode: ComposeEmailMode.newEmail,
                                        ),
                                      );
                                    }
                                    break;
                                  case 'Refresh':
                                    if (_selectedAccountId != null) {
                                      ref.read(emailListProvider.notifier).refresh(_selectedAccountId!, folderLabel: _selectedFolder);
                                    }
                                    break;
                                  case 'Settings':
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => const AccountsSettingsDialog(),
                                    );
                                    break;
                                  case 'Actions':
                                    showDialog(context: context, builder: (_) => ActionsSummaryWindow());
                                    break;
                                  case 'Attachments':
                                    showDialog(context: context, builder: (_) => const AttachmentsWindow());
                                    break;
                                  case 'Subscriptions':
                                    if (_selectedAccountId != null) {
                                      showDialog(context: context, builder: (_) => SubscriptionsWindow(accountId: _selectedAccountId!));
                                    }
                                    break;
                                  case 'Shopping':
                                    showDialog(context: context, builder: (_) => const ShoppingWindow());
                                    break;
                                }
                              },
                              itemBuilder: (context) {
                                final cs = Theme.of(context).colorScheme;
                                return [
                                  PopupMenuItem(
                                    value: 'Compose',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Compose',
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'Refresh',
                                    child: Row(
                                      children: [
                                        Icon(Icons.refresh, size: 18, color: cs.onSurface),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Refresh',
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'Settings',
                                    child: Row(
                                      children: [
                                        Icon(Icons.settings_outlined, size: 18, color: cs.onSurface),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Settings',
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  // Actions (renamed from Account Digest)
                                  PopupMenuItem(
                                    value: 'Actions',
                                    child: Row(
                                      children: [
                                        Icon(Icons.dashboard_outlined, size: 18, color: cs.onSurface),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Actions',
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Other function windows (excluding Actions and Actions Summary which are shown separately)
                                  ...AppConstants.allFunctionWindows.where((window) => window != AppConstants.windowActions && window != AppConstants.windowActionsSummary).map((window) {
                                    IconData icon;
                                    switch (window) {
                                      case AppConstants.windowActions:
                                        icon = Icons.auto_fix_high;
                                        break;
                                      case AppConstants.windowAttachments:
                                        icon = Icons.attach_file;
                                        break;
                                      case AppConstants.windowSubscriptions:
                                        icon = Icons.subscriptions;
                                        break;
                                      case AppConstants.windowShopping:
                                        icon = Icons.shopping_bag;
                                        break;
                                      default:
                                        icon = Icons.info_outline;
                                    }
                                    return PopupMenuItem(
                                      value: window,
                                      child: Row(
                                        children: [
                                          Icon(icon, size: 18, color: cs.onSurface),
                                          const SizedBox(width: 12),
                                          Text(
                                            window,
                                            style: TextStyle(
                                              color: cs.onSurface,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ];
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
            body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final leftWidth = (constraints.maxWidth * 0.20).clamp(200.0, 360.0);  
          final rightWidth = (constraints.maxWidth * 0.20).clamp(200.0, 360.0); 
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDesktop)
                ClipRect(
                  child: SizedBox(
                    width: leftWidth,
                    child: _buildLeftPanel(context),
                  ),
                ),
              Expanded(
                child: ClipRect(child: _buildMainColumn()),
              ),
              if (isDesktop)
                ClipRect(
                  child: SizedBox(
                    width: rightWidth,
                    child: _buildRightPanel(context),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // Left panel for desktop - Accounts and Gmail folder tree
  Widget _buildLeftPanel(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final highlightColor = ActionMailTheme.alertColor.withValues(alpha: 0.2);
    final highlightBorderColor = ActionMailTheme.alertColor.withValues(alpha: 1);
    const accountSelectedBorderColor = Color(0xFF00695C);
    
    final column = Column(
      children: [
        // Accounts section
        if (_accounts.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: cs.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Accounts',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ..._accounts.map((account) {
                  final isSelected = account.id == _selectedAccountId;
                  final isAccountActive = isSelected && !_isLocalFolder;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        if (account.id != _selectedAccountId) {
                          _pendingLocalUnreadAccounts.add(account.id);
                          setState(() {
                            _selectedAccountId = account.id;
                            _isLocalFolder = false;
                            _selectedFolder = AppConstants.folderInbox;
                          });
                          await _saveLastActiveAccount(account.id);
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
                                final hasHistory = await syncService.hasHistoryId(_selectedAccountId!);
                                if (hasHistory) {
                                  // Account already has history - run incremental sync
                                  await syncService.incrementalSync(_selectedAccountId!);
                                }
                                // If no history, loadEmails already triggered initial sync in background
                                
                                // Switch unread count to local after sync
                                await _switchUnreadCountToLocal(_selectedAccountId!);
                              } catch (e) {
                                debugPrint('[HomeScreen] Error during background sync on account tap: $e');
                                await _switchUnreadCountToLocal(_selectedAccountId!);
                              }
                            }));
                          }
                        } else if (_isLocalFolder) {
                          setState(() {
                            _isLocalFolder = false;
                            _selectedFolder = AppConstants.folderInbox;
                          });
                          if (_selectedAccountId != null) {
                            await _loadFolderEmails(AppConstants.folderInbox, false);
                          }
                          await _saveLastActiveAccount(account.id);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isAccountActive ? highlightColor : Colors.transparent,
                          border: isAccountActive
                              ? Border(
                                  left: BorderSide(
                                    color: highlightBorderColor,
                                    width: 3,
                                  ),
                                )
                              : isSelected
                                  ? const Border(
                                      left: BorderSide(
                                        color: accountSelectedBorderColor,
                                        width: 3,
                                      ),
                                    )
                                  : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.account_circle : Icons.account_circle_outlined,
                              size: 18,
                              color: isAccountActive
                                  ? cs.onSurface
                                  : (isSelected ? accountSelectedBorderColor : cs.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                account.email,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isAccountActive || !isSelected ? cs.onSurface : accountSelectedBorderColor,
                                  fontWeight: isAccountActive ? FontWeight.w600 : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_accountUnreadCounts[account.id] != null && _accountUnreadCounts[account.id]! > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '(${_accountUnreadCounts[account.id]})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isAccountActive
                                        ? cs.onSurface
                                        : (isSelected ? accountSelectedBorderColor : cs.onSurfaceVariant),
                                    fontWeight: FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        // Gmail folder tree
        Expanded(
          child: GmailFolderTree(
      selectedFolder: _selectedFolder,
      isViewingLocalFolder: _isLocalFolder,
      accountId: _selectedAccountId,
      selectedBackgroundColor: highlightColor,
      onFolderSelected: (folderId) async {
        setState(() {
          _selectedFolder = folderId;
          _isLocalFolder = false; // Reset to Gmail folder
        });
        if (_selectedAccountId != null) {
          await ref.read(emailListProvider.notifier).loadFolder(_selectedAccountId!, folderLabel: _selectedFolder);
        }
      },
      onEmailDropped: (folderId, message) async {
        if (_isLocalFolder) {
          if (folderId.toUpperCase() != 'INBOX') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Local emails can only be restored to Inbox')),
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
            if (_selectedFolder != 'TRASH') {
              ref.read(emailListProvider.notifier).removeMessage(message.id);
            } else {
              ref.read(emailListProvider.notifier).setFolder(message.id, 'TRASH');
            }
            final prev = message.folderLabel;
            if (prev.toUpperCase() == 'ARCHIVE') {
              // ARCHIVE -> TRASH: do not change prevFolderLabel
              unawaited(MessageRepository().updateFolderNoPrev(message.id, 'TRASH'));
            } else {
              unawaited(MessageRepository().updateFolderWithPrev(
                message.id,
                'TRASH',
                prevFolderLabel: prev,
              ));
            }
            _enqueueGmailUpdate('trash:${prev.toUpperCase()}', message.id);
          } else if (folderId == 'ARCHIVE') {
            if (_selectedFolder != 'ARCHIVE') {
              ref.read(emailListProvider.notifier).removeMessage(message.id);
            } else {
              ref.read(emailListProvider.notifier).setFolder(message.id, 'ARCHIVE');
            }
            final prev = message.folderLabel;
            if (prev.toUpperCase() == 'TRASH') {
              // TRASH -> ARCHIVE: do not change prevFolderLabel
              unawaited(MessageRepository().updateFolderNoPrev(message.id, 'ARCHIVE'));
            } else {
              unawaited(MessageRepository().updateFolderWithPrev(
                message.id,
                'ARCHIVE',
                prevFolderLabel: prev,
              ));
            }
            _enqueueGmailUpdate('archive:${prev.toUpperCase()}', message.id);
          } else if (folderId == 'INBOX') {
            if (_selectedFolder != 'INBOX') {
              ref.read(emailListProvider.notifier).removeMessage(message.id);
            } else {
              ref.read(emailListProvider.notifier).setFolder(message.id, 'INBOX');
            }
            final prev = message.folderLabel;
            unawaited(MessageRepository().updateFolderWithPrev(
              message.id,
              'INBOX',
              prevFolderLabel: prev,
            ));
            _enqueueGmailUpdate('moveToInbox', message.id);
          } else {
            // Restore to previous folder (if prevFolderLabel matches target)
            final prevFolder = message.prevFolderLabel;
            if (prevFolder != null && prevFolder.toUpperCase() == folderId.toUpperCase()) {
              // Optimistic: assume restore succeeded; we'll adjust based on refreshed value
              // Remove from current view if destination differs, else update folder
              unawaited(() async {
                await MessageRepository().restoreToPrev(message.id);
                if (_selectedAccountId != null) {
                  final updated = await MessageRepository().getByIds(_selectedAccountId!, [message.id]);
                  final restored = updated[message.id];
                  if (restored != null) {
                    final dest = restored.folderLabel;
                    if (_selectedFolder != dest) {
                      ref.read(emailListProvider.notifier).removeMessage(message.id);
                    } else {
                      ref.read(emailListProvider.notifier).setFolder(message.id, dest);
                    }
                    _enqueueGmailUpdate('restore:${dest.toUpperCase()}', message.id);
                  }
                }
              }());
            }
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Email moved to ${AppConstants.folderDisplayNames[folderId] ?? folderId}')),
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
      },
          ),
        ),
      ],
    );
    return Container(
      color: theme.colorScheme.surface,
      child: column,
    );
  }
  
  // Right panel for desktop - local folder tree
  Widget _buildRightPanel(BuildContext context) {
    final highlightColor = ActionMailTheme.alertColor.withValues(alpha: 0.2);
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: LocalFolderTree(
        selectedFolder: _isLocalFolder ? _selectedFolder : null,
        selectedBackgroundColor: highlightColor,
        onFolderSelected: (folderPath) async {
          setState(() {
            _selectedFolder = folderPath;
            _isLocalFolder = true;
          });
          await _loadFolderEmails(folderPath, true);
        },
        onEmailDropped: (folderPath, message) async {
          // Determine if this is a local-to-local move or Gmail-to-local save
          // If we're currently viewing a local folder, the email is from a local folder
          if (_isLocalFolder) {
            // Local email -> Local folder: move within local storage
            await _moveLocalEmailToFolder(folderPath, message);
          } else {
            // Gmail email -> Local folder: only allowed from INBOX, SPAM, SENT
            final src = (message.folderLabel).toUpperCase();
            if (src == 'TRASH' || src == 'ARCHIVE') {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cannot save from Trash/Archive to local. Move to Inbox/Sent/Spam first.')),
                );
              }
              return;
            }
            // Proceed: save and archive
            await _saveEmailToFolder(folderPath, message);
          }
        },
      ),
    );
  }
  
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
        await ref.read(emailListProvider.notifier).loadFolder(_selectedAccountId!, folderLabel: folderLabel);
      }
    }
  }

  // Main content column extracted from previous body
  Widget _buildMainColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Saved List indicator when viewing local folder
        if (_isLocalFolder) _buildSavedListIndicator(),
        
        // Top filter row: Personal/Business, Action buttons, Filter toggle
        _buildTopFilterRow(),
        
        // Filter bar: Unread, Starred, Important, Category filter, Search
        if (_showFilterBar) _buildFilterBar(),
        
        // Search field (below filter bar when active)
        if (_showFilterBar && _showSearch) _buildSearchField(),
        
        // Email list
        Expanded(
          child: _buildEmailList(),
        ),
      ],
    );
  }
  
  /// Indicator showing we're viewing a saved list
  Widget _buildSavedListIndicator() {
    final theme = Theme.of(context);
    final textColor = const Color(0xFF333333);
    final highlightColor = ActionMailTheme.alertColor.withValues(alpha: 0.5);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlightColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.sd_storage_outlined,
            size: 20,
            color: textColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Viewing local storage',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Saved list: $_selectedFolder',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () {
              if (_selectedAccountId == null) return;
              setState(() {
                _isLocalFolder = false;
                _selectedFolder = AppConstants.folderInbox;
              });
              unawaited(_loadFolderEmails(AppConstants.folderInbox, false));
            },
            style: TextButton.styleFrom(
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Back to Gmail'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterBar() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Container(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 2.0, bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // State filter buttons (Unread, Starred, Important) - sophisticated style
          _buildSophisticatedStateFilterButtons(context),
          SizedBox(width: isDesktop ? 4 : 12),
          // Category filter button - sophisticated style
          _buildSophisticatedCategoryButton(context),
          SizedBox(width: isDesktop ? 4 : 12),
          // Search button - sophisticated style
          _buildSophisticatedSearchButton(context),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Center(
        child: SizedBox(
          width: 400,
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search emails...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase().trim();
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedStateFilterButtons(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    
    // Get counts from the currently displayed email list (account + folder)
    // This reflects what's actually shown in the email list
    final emailListAsync = ref.watch(emailListProvider);
    
    // Calculate counts from the current email list
    final counts = emailListAsync.when(
      data: (emails) {
        // Count from emails in the current folder (already filtered by account and folder)
        return {
          'unread': emails.where((m) => !m.isRead).length,
          'starred': emails.where((m) => m.isStarred).length,
          'important': emails.where((m) => m.isImportant).length,
        };
      },
      loading: () => {'unread': 0, 'starred': 0, 'important': 0},
      error: (_, __) => {'unread': 0, 'starred': 0, 'important': 0},
    );
    
    final unreadCount = counts['unread']!;
    final starredCount = counts['starred']!;
    final importantCount = counts['important']!;
    
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSophisticatedFilterButton(
            context,
            'Unread',
            Icons.mark_email_unread_outlined,
            Icons.mark_email_unread,
            _stateFilter == 'Unread',
            unreadCount,
            () {
              setState(() {
                _stateFilter = _stateFilter == 'Unread' ? null : 'Unread';
              });
            },
          ),
          // Mark all as read button (only show when Unread filter is active)
          if (_stateFilter == 'Unread') ...[
            SizedBox(width: isDesktop ? 2 : 12),
            _buildMarkAllAsReadButton(context),
          ],
          SizedBox(width: isDesktop ? 2 : 12),
          _buildSophisticatedFilterButton(
            context,
            'Starred',
            Icons.star_border,
            Icons.star,
            _stateFilter == 'Starred',
            starredCount,
            () {
              setState(() {
                _stateFilter = _stateFilter == 'Starred' ? null : 'Starred';
              });
            },
          ),
          SizedBox(width: isDesktop ? 2 : 12),
          _buildSophisticatedFilterButton(
            context,
            'Important',
            Icons.priority_high_outlined,
            Icons.priority_high,
            _stateFilter == 'Important',
            importantCount,
            () {
              setState(() {
                _stateFilter = _stateFilter == 'Important' ? null : 'Important';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSophisticatedCategoryButton(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasCategories = _selectedCategories.isNotEmpty;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Material(
        color: hasCategories ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showCategoriesPopup(context),
          child: Container(
            padding: isDesktop ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Icon(
                      hasCategories ? Icons.filter_alt : Icons.filter_alt_outlined,
                      size: 18,
                      color: hasCategories 
                          ? cs.onPrimaryContainer 
                          : const Color(0xFF00897B), // Teal for categories
                    ),
                    if (hasCategories)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.primaryContainer, width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Categories',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasCategories ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      fontWeight: hasCategories ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkAllAsReadButton(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // Get unread emails from the current list (reactive)
    final emailListAsync = ref.watch(emailListProvider);
    
    final unreadInfo = emailListAsync.when(
      data: (emails) {
        final unreadEmails = emails.where((m) => !m.isRead).toList();
        return {
          'count': unreadEmails.length,
          'ids': unreadEmails.map((m) => m.id).toList(),
        };
      },
      loading: () => {'count': 0, 'ids': <String>[]},
      error: (_, __) => {'count': 0, 'ids': <String>[]},
    );
    
    final unreadCount = unreadInfo['count'] as int;
    final unreadMessageIds = unreadInfo['ids'] as List<String>;
    final isEnabled = unreadCount > 0 && !_isLocalFolder;
    
    return Tooltip(
      message: 'Mark all as Read',
      child: Material(
        color: isEnabled ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isEnabled
              ? () => _markAllUnreadAsRead(unreadMessageIds)
              : null,
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.done_all,
              size: 18,
              color: isEnabled
                  ? cs.onPrimaryContainer
                  : cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedSearchButton(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSearchActive = _showSearch;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSearchActive ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchQuery = '';
                _searchController.clear();
              }
            });
          },
          child: Container(
            padding: isDesktop ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSearchActive ? Icons.search_off : Icons.search,
                  size: 18,
                  color: isSearchActive 
                      ? cs.onPrimaryContainer 
                      : const Color(0xFF42A5F5), // Blue for search
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Search',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSearchActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      fontWeight: isSearchActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedFilterButton(
    BuildContext context,
    String label,
    IconData outlinedIcon,
    IconData filledIcon,
    bool selected,
    int count,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    
    // Assign colors based on filter type
    Color iconColor;
    if (selected) {
      iconColor = cs.onPrimaryContainer;
    } else {
      switch (label) {
        case 'Unread':
          iconColor = const Color(0xFF2196F3); // Blue
          break;
        case 'Starred':
          iconColor = const Color(0xFFFFB300); // Amber/Yellow
          break;
        case 'Important':
          iconColor = const Color(0xFFE91E63); // Pink/Red
          break;
        default:
          iconColor = cs.onSurfaceVariant;
      }
    }
    
    // Tooltip text
    String tooltipText;
    switch (label) {
      case 'Starred':
        tooltipText = 'Emails you have Starred';
        break;
      case 'Important':
        tooltipText = 'Emails Google has flagged as Important';
        break;
      default:
        tooltipText = label;
    }
    if (count > 0) {
      tooltipText = '$tooltipText ($count)';
    }
    
    return Tooltip(
      message: tooltipText,
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: isDesktop ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? filledIcon : outlinedIcon,
                  size: 18,
                  color: iconColor,
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? cs.primary : iconColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ] else if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? cs.primary : iconColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoriesPopup(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentSelections = Set<String>.from(_selectedCategories);
    
    // Map categories to icons and colors
    final categoryConfig = <String, Map<String, dynamic>>{
      'categoryPersonal': {'icon': Icons.person_outline, 'color': const Color(0xFF2196F3)},
      'categorySocial': {'icon': Icons.people_outline, 'color': const Color(0xFF673AB7)},
      'categoryPromotions': {'icon': Icons.local_offer_outlined, 'color': const Color(0xFFE91E63)},
      'categoryUpdates': {'icon': Icons.info_outline, 'color': const Color(0xFF00BCD4)},
      'categoryForums': {'icon': Icons.forum_outlined, 'color': const Color(0xFFFF9800)},
      'categoryBills': {'icon': Icons.receipt_long_outlined, 'color': const Color(0xFF4CAF50)},
      'categoryPurchases': {'icon': Icons.shopping_bag_outlined, 'color': const Color(0xFFFF5722)},
      'categoryFinance': {'icon': Icons.account_balance_outlined, 'color': const Color(0xFF009688)},
      'categoryTravel': {'icon': Icons.flight_outlined, 'color': const Color(0xFF03A9F4)},
      'categoryReceipts': {'icon': Icons.receipt_outlined, 'color': const Color(0xFF795548)},
    };
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              width: 250,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Categories',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Category list
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: AppConstants.allGmailCategories.map((category) {
                          final displayName = AppConstants.categoryDisplayNames[category] ?? category;
                          final isSelected = currentSelections.contains(category);
                          final config = categoryConfig[category] ?? {'icon': Icons.label_outline, 'color': cs.onSurfaceVariant};
                          final icon = config['icon'] as IconData;
                          final color = config['color'] as Color;
                          
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  currentSelections.remove(category);
                                } else {
                                  currentSelections.add(category);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? cs.primaryContainer.withValues(alpha: 0.3) : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    icon,
                                    size: 20,
                                    color: isSelected ? cs.primary : color,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: isSelected ? cs.onPrimaryContainer : null,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check,
                                      size: 18,
                                      color: cs.primary,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).then((_) {
      // Apply selections when dialog closes
      setState(() {
        _selectedCategories.clear();
        _selectedCategories.addAll(currentSelections);
      });
    });
  }


  /// Save email to local folder and move to Archive
  Future<void> _saveEmailToFolder(String folderName, MessageIndex message) async {
    // Disallow saving to local from Gmail TRASH/ARCHIVE
    final src = (message.folderLabel).toUpperCase();
    if (src == 'TRASH' || src == 'ARCHIVE') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot save from Trash/Archive to local. Move to Inbox/Sent/Spam first.')),
        );
      }
      return;
    }
    // Optimistic UI: reflect archive intent immediately
    if (_selectedAccountId == null) return;
    final wasArchive = message.folderLabel.toUpperCase() == 'ARCHIVE';
    if (!wasArchive) {
      // Remove from current view if not ARCHIVE; otherwise set folder to ARCHIVE
      if (_selectedFolder != 'ARCHIVE') {
        ref.read(emailListProvider.notifier).removeMessage(message.id);
      } else {
        ref.read(emailListProvider.notifier).setFolder(message.id, 'ARCHIVE');
      }
    }

    // Defer heavy work (token check, body fetch, file IO, DB, Gmail) until after UI paints
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Get access token for downloading email body and attachments
        final account = await GoogleAuthService().ensureValidAccessToken(_selectedAccountId!);
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
        final emailBody = await gmailService.getEmailBody(message.id, accessToken);
        if (emailBody == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to save: Could not fetch email body')),
            );
          }
          return;
        }

      String accountEmail = message.accountEmail ??
          _accounts.firstWhere(
            (a) => a.id == _selectedAccountId,
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
          ).email;
      if (accountEmail.isEmpty) {
        accountEmail = message.to.isNotEmpty ? message.to : message.from;
      }
        if (accountEmail.isEmpty) {
          accountEmail = message.to.isNotEmpty ? message.to : message.from;
        }

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
            await MessageRepository().updateFolderWithPrev(
              message.id,
              'ARCHIVE',
              prevFolderLabel: message.folderLabel,
            );
            final src = message.folderLabel.toUpperCase();
            _enqueueGmailUpdate('archive:$src', message.id);
          }
          if (mounted && _isLocalFolder && _selectedFolder == folderName) {
            final refreshed = await _localFolderService.loadFolderEmails(folderName);
            ref.read(emailListProvider.notifier).setEmails(refreshed);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(wasArchive
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
              unawaited(ref.read(emailListProvider.notifier).refresh(_selectedAccountId!, folderLabel: _selectedFolder));
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
            unawaited(ref.read(emailListProvider.notifier).refresh(_selectedAccountId!, folderLabel: _selectedFolder));
          }
        }
      }
    });
  }

  /// Move email between local folders
  Future<void> _moveLocalEmailToFolder(String targetFolderPath, MessageIndex message) async {
    if (_selectedAccountId == null) return;
    
    try {
      // Get the source folder path (from current selection)
      final sourceFolderPath = _isLocalFolder ? _selectedFolder : null;
      
      if (sourceFolderPath == null || sourceFolderPath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to move: Source folder not found')),
          );
        }
        return;
      }
      
      // Load email body from source folder
      final emailBody = await _localFolderService.loadEmailBody(sourceFolderPath, message.id);
      
      if (emailBody == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to move: Could not load email body')),
          );
        }
        return;
      }
      
      // Get access token for downloading attachments if needed
      final account = await GoogleAuthService().ensureValidAccessToken(_selectedAccountId!);
      final accessToken = account?.accessToken;
      
      if (accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to move: No access token')),
          );
        }
        return;
      }
      
      final accountEmail = message.accountEmail ??
          _accounts.firstWhere(
            (a) => a.id == _selectedAccountId,
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
          ).email;

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
        await _localFolderService.removeEmailFromFolder(sourceFolderPath, message.id);
        
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
    final messageAccountEmail = message.accountEmail ?? '';
    if (accountId.isEmpty && messageAccountEmail.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to restore: missing account information')),
        );
      }
      return;
    }

    final sourceFolderPath = _selectedFolder;
    if (sourceFolderPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to restore: source folder unavailable')),
        );
      }
      return;
    }

    final storedAccountEmail = message.accountEmail ??
        _accounts.firstWhere(
          (a) => a.id == message.accountId,
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
        ).email;

    debugPrint('[Restore] requested accountId=$accountId local message account=${message.accountId} email=$storedAccountEmail');
    debugPrint('[Restore] Signed-in accounts: ${_accounts.map((a) => '${a.id}:${a.email}').join(', ')}');

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
        debugPrint('[Restore] Resolved account via email match: ${signedInAccount.email} -> id ${signedInAccount.id}');
        accountId = signedInAccount.id;
      }
    }

    if (signedInAccount.id.isEmpty) {
      debugPrint('[Restore] No matching signed-in account found (wanted id=$accountId email=$storedAccountEmail); aborting restore.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account not signed in. Add the account in Accounts before restoring.'),
          ),
        );
      }
      return;
    }

    final account = await auth.ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    debugPrint('[Restore] ensureValidAccessToken -> accountId=$accountId email=${account?.email ?? 'unknown'} hasAccount=${account != null} '
        'accessToken=${accessToken != null && accessToken.isNotEmpty} '
        'refreshToken=${(account?.refreshToken ?? '').isNotEmpty} '
        'expiryMs=${account?.tokenExpiryMs}');

    if (accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Google session expired. Re-authenticate via the Accounts menu before restoring.'),
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
            debugPrint('[Restore] Calling Gmail restoreMessageToInbox for message=${message.id} account=$accountId email=${account?.email ?? 'unknown'}');
            await GmailSyncService().restoreMessageToInbox(accountId, message.id);
            debugPrint('[Restore] Gmail modify succeeded for message=${message.id} account=$accountId');
            await MessageRepository().updateFolderNoPrev(message.id, 'INBOX');

            await _localFolderService.removeEmailFromFolder(sourceFolderPath, message.id);
            debugPrint('[Restore] Removed local copy for message=${message.id}');
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
              await ref.read(emailListProvider.notifier).loadFolder(accountId, folderLabel: 'INBOX');
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

        return const _ProcessingDialog(message: 'Restoring to Inbox...');
      },
    );
  }

  // Placeholder for background Gmail update scheduling
  void _enqueueGmailUpdate(String action, String messageId) {
    if (_selectedAccountId == null) return;
    // Enqueue to DB; processing is triggered by refresh/incremental sync
    MessageRepository().enqueuePendingOp(_selectedAccountId!, messageId, action);
    // Trigger background processing after current frame to allow optimistic UI to paint first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(GmailSyncService().processPendingOps());
    });
  }

  Widget _buildTopFilterRow() {
    return Container(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 6.0, bottom: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Action filter as text buttons
          Builder(
            builder: (context) {
              final emailsValue = ref.read(emailListProvider);
              int countToday = 0, countUpcoming = 0, countOverdue = 0, countPossible = 0;
              emailsValue.whenData((emails) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                for (final m in emails) {
                  if (_selectedLocalState != null && m.localTagPersonal != _selectedLocalState) {
                    continue;
                  }
                  if (m.actionComplete) {
                    continue;
                  }
                  if (!m.hasAction) {
                    continue;
                  }
                  if (m.actionDate == null) {
                    countPossible++;
                    continue;
                  }
                  final local = m.actionDate!.toLocal();
                  final d = DateTime(local.year, local.month, local.day);
                  if (d == today) {
                    countToday++;
                  } else if (d.isAfter(today)) {
                    countUpcoming++;
                  } else {
                    countOverdue++;
                  }
                }
              });
              // Action filter as text buttons
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionFilterTextButton(context, AppConstants.filterToday, countToday),
                  _buildActionFilterTextButton(context, AppConstants.filterUpcoming, countUpcoming),
                  _buildActionFilterTextButton(context, AppConstants.filterOverdue, countOverdue),
                  _buildActionFilterTextButton(context, AppConstants.filterPossible, countPossible),
                ],
              );
            },
          ),
          const SizedBox(width: 16),
          // Filter toggle icon (subtle, sophisticated)
          IconButton(
            tooltip: 'Filters',
            icon: Icon(_showFilterBar ? Icons.filter_list : Icons.filter_list_outlined),
            color: _showFilterBar 
                ? const Color(0xFF00695C) // Teal when active
                : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            iconSize: 20,
            onPressed: () {
              setState(() {
                _showFilterBar = !_showFilterBar;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarLocalStateSwitch(BuildContext context) {
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate approximate button widths and text widths
        // Personal button: icon (16) + spacing (4) + text (~60) + padding (20) ≈ 100
        // Personal text width: ~60
        // Business button: icon (16) + spacing (4) + text (~65) + padding (20) ≈ 105
        // Business text width: ~65
        const double personalButtonWidth = 95.0;
        const double personalTextWidth = 55.0;
        const double businessTextWidth = 60.0;
        const double iconAndSpacing = 20.0; // icon (16) + spacing (4)
        
        double underlineLeft = 0;
        double underlineWidth = 0;
        
        if (_selectedLocalState == 'Personal') {
          underlineLeft = iconAndSpacing; // Start after icon and spacing
          underlineWidth = personalTextWidth;
        } else if (_selectedLocalState == 'Business') {
          underlineLeft = personalButtonWidth + iconAndSpacing;
          underlineWidth = businessTextWidth;
        }
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Transparent row of buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAppBarStateButton(
                  context,
                  'Personal',
                  Icons.person_outline,
                  Icons.person,
                  _selectedLocalState == 'Personal',
                  () {
                    setState(() {
                      // Toggle: if already selected, deselect; otherwise select
                      _selectedLocalState = _selectedLocalState == 'Personal' ? null : 'Personal';
                    });
                  },
                ),
                _buildAppBarStateButton(
                  context,
                  'Business',
                  Icons.business_center_outlined,
                  Icons.business,
                  _selectedLocalState == 'Business',
                  () {
                    setState(() {
                      // Toggle: if already selected, deselect; otherwise select
                      _selectedLocalState = _selectedLocalState == 'Business' ? null : 'Business';
                    });
                  },
                ),
              ],
            ),
            // Sliding underline
            if (_selectedLocalState != null)
              Positioned(
                bottom: 0,
                left: underlineLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: underlineWidth,
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAppBarStateButton(
    BuildContext context,
    String state,
    IconData outlinedIcon,
    IconData filledIcon,
    bool selected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    
    // Color for icons and text - white for better visibility on teal background
    final Color iconColor = Theme.of(context).appBarTheme.foregroundColor
        ?? Theme.of(context).colorScheme.onPrimary; // fallback if not set

    final Color textColor = Theme.of(context).appBarTheme.foregroundColor
        ?? Theme.of(context).colorScheme.onPrimary;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? filledIcon : outlinedIcon,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 4),
              Text(
                state,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: textColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // (removed) _buildSophisticatedStateButton was unused

  // ignore: unused_element
  Widget _buildCategoryCarousel() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        itemCount: AppConstants.allGmailCategories.length,
        itemBuilder: (context, index) {
          final category = AppConstants.allGmailCategories[index];
          final displayName = AppConstants.categoryDisplayNames[category] ?? category;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: AppToggleChip(
              label: displayName,
              selected: _selectedCategories.contains(category),
              linkStyle: true,
              onTap: () {
                setState(() {
                  if (_selectedCategories.contains(category)) {
                    _selectedCategories.remove(category);
                  } else {
                    _selectedCategories.add(category);
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Color _categoryColor(BuildContext context, String category) {
    final cs = Theme.of(context).colorScheme;
    switch (category) {
      case 'CATEGORY_PERSONAL':
        return cs.primary;
      case 'CATEGORY_PROMOTIONS':
        return cs.tertiary;
      case 'CATEGORY_SOCIAL':
        return Colors.indigo;
      case 'CATEGORY_UPDATES':
        return Colors.teal;
      case 'CATEGORY_FORUMS':
        return Colors.deepOrange;
      default:
        return cs.secondary;
    }
  }

  // ignore: unused_element
  Widget _buildStateFilterIconButton(BuildContext context, String state, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _stateFilter == state;
    Color colorFor(bool sel) => sel ? cs.primary : cs.onSurfaceVariant;
    String tooltip;
    switch (state) {
      case 'Unread':
        tooltip = AppConstants.emailStateUnread;
        break;
      case 'Starred':
        tooltip = AppConstants.emailStateStarred;
        break;
      case 'Important':
        tooltip = AppConstants.emailStateImportant;
        break;
      default:
        tooltip = state;
    }
    return Container(
      decoration: selected
          ? BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: colorFor(selected)),
        onPressed: () {
          setState(() {
            _stateFilter = selected ? null : state;
          });
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLocalStateIconButton(BuildContext context, String state, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selectedLocalState == state;
    Color colorFor(bool sel) => sel ? cs.primary : cs.onSurfaceVariant;
    IconData actualIcon = icon;
    // Match email tile: use solid icon when selected, outlined when not
    if (state == 'Personal') {
      actualIcon = selected ? Icons.person : Icons.person_outline;
    } else if (state == 'Business') {
      actualIcon = selected ? Icons.business_center : Icons.business_center_outlined;
    }
    return Container(
      decoration: selected
          ? BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: IconButton(
        tooltip: state,
        icon: Icon(actualIcon, color: colorFor(selected)),
        onPressed: () {
              setState(() {
            // Toggle: if already selected, deselect; otherwise select
            _selectedLocalState = selected ? null : state;
          });
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildActionFilterIconButton(BuildContext context, String filter, IconData icon, int? count) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selectedActionFilter == filter;
    Color colorFor(bool sel) => sel ? cs.primary : cs.onSurfaceVariant;
    String tooltip;
    switch (filter) {
      case AppConstants.filterToday:
        tooltip = '${AppConstants.actionSummaryToday}${count != null ? ' ($count)' : ''}';
        break;
      case AppConstants.filterUpcoming:
        tooltip = '${AppConstants.actionSummaryUpcoming}${count != null ? ' ($count)' : ''}';
        break;
      case AppConstants.filterOverdue:
        tooltip = '${AppConstants.actionSummaryOverdue}${count != null ? ' ($count)' : ''}';
        break;
      default:
        tooltip = AppConstants.actionSummaryAll;
    }
    return Container(
      decoration: selected
          ? BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: colorFor(selected)),
        onPressed: () {
          setState(() {
            // Toggle: if already selected, deselect (null); otherwise select
            _selectedActionFilter = _selectedActionFilter == filter ? null : filter;
          });
        },
      ),
    );
  }

  Widget _buildActionFilterTextButton(BuildContext context, String filter, int count) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selectedActionFilter == filter;
    String label;
    String tooltipText;
    switch (filter) {
      case AppConstants.filterToday:
        label = AppConstants.actionSummaryToday;
        tooltipText = 'Actions due today';
        break;
      case AppConstants.filterUpcoming:
        label = 'Future';
        tooltipText = 'Upcoming actions';
        break;
      case AppConstants.filterOverdue:
        label = AppConstants.actionSummaryOverdue;
        tooltipText = 'Overdue actions';
        break;
      case AppConstants.filterPossible:
        label = AppConstants.filterPossible;
        tooltipText = 'Actions without a date';
        break;
      default:
        label = AppConstants.actionSummaryAll;
        tooltipText = label;
    }
    final displayText = '$label ($count)';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: Tooltip(
        message: tooltipText,
        child: InkWell(
          onTap: () {
            setState(() {
              // Toggle: if already selected, deselect (null); otherwise select
              _selectedActionFilter = _selectedActionFilter == filter ? null : filter;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: selected
                ? BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Text(
              displayText,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? cs.primary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStateFilterDropdownRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          PopupMenuButton<String?>(
            tooltip: 'Filters',
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                if (value == 'Clear') {
                  _stateFilter = null;
                } else {
                  _stateFilter = value;
                }
              });
            },
            itemBuilder: (context) {
              final cs = Theme.of(context).colorScheme;
              return <PopupMenuEntry<String?>>[
                PopupMenuItem<String?>(
                  value: 'Unread',
                  child: Row(
                    children: [
                      // ignore: deprecated_member_use
                      Radio<String?>(
                        value: 'Unread',
                        // ignore: deprecated_member_use
                        groupValue: _stateFilter,
                        // ignore: deprecated_member_use
                        onChanged: (_) {},
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppConstants.emailStateUnread,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              PopupMenuItem<String?>(
                value: 'Starred',
                child: Row(
                  children: [
                    // ignore: deprecated_member_use
                    Radio<String?>(
                      value: 'Starred',
                      // ignore: deprecated_member_use
                      groupValue: _stateFilter,
                      // ignore: deprecated_member_use
                      onChanged: (_) {},
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppConstants.emailStateStarred,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String?>(
                value: 'Important',
                child: Row(
                  children: [
                    // ignore: deprecated_member_use
                    Radio<String?>(
                      value: 'Important',
                      // ignore: deprecated_member_use
                      groupValue: _stateFilter,
                      // ignore: deprecated_member_use
                      onChanged: (_) {},
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppConstants.emailStateImportant,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String?>(
                value: 'Clear',
                child: Row(
                  children: [
                    Icon(Icons.clear, size: 16, color: cs.onSurface),
                    const SizedBox(width: 6),
                    Text(
                      'Clear Filters',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      ],
    ),
    );
  }

  Widget _buildEmailList() {
    final emailListAsync = ref.watch(emailListProvider);
    final isSyncing = ref.watch(emailSyncingProvider);
    final isLoadingLocal = ref.watch(emailLoadingLocalProvider);

    return emailListAsync.when(
      data: (emails) {
        // Apply filters in-memory for current folder result set
        final filtered = emails.where((m) {
          // Local state filter (null means no filter, Personal/Business means filter)
          if (_selectedLocalState != null) {
            if (m.localTagPersonal != _selectedLocalState) return false;
          }
          // Gmail category filter (AND across selected categories)
          if (_selectedCategories.isNotEmpty) {
            final hasAny = m.gmailCategories.any((c) => _selectedCategories.contains(c));
            if (!hasAny) return false;
          }
          // Email state single-select filter
          if (_stateFilter != null) {
            switch (_stateFilter) {
              case 'Unread':
                if (m.isRead) return false;
                break;
              case 'Starred':
                if (!m.isStarred) return false;
                break;
              case 'Important':
                if (!m.isImportant) return false;
                break;
            }
          }
          // Action summary filter
          if (_selectedActionFilter != null) {
            // Only include messages that have an action
            if (!m.hasAction) return false;
            // Exclude completed actions
            if (m.actionComplete) return false;
            switch (_selectedActionFilter) {
              case AppConstants.filterToday:
                if (m.actionDate == null) return false;
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final local = m.actionDate!.toLocal();
                final d = DateTime(local.year, local.month, local.day);
                if (d != today) return false;
                break;
              case AppConstants.filterUpcoming:
                if (m.actionDate == null) return false;
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final local = m.actionDate!.toLocal();
                final d = DateTime(local.year, local.month, local.day);
                if (!d.isAfter(today)) return false;
                break;
              case AppConstants.filterOverdue:
                if (m.actionDate == null) return false;
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final local = m.actionDate!.toLocal();
                final d = DateTime(local.year, local.month, local.day);
                if (!d.isBefore(today)) return false;
                break;
              case AppConstants.filterPossible:
                if (m.actionDate != null) return false;
                break;
            }
          }
          // Search filter
          if (_searchQuery.isNotEmpty) {
            final query = _searchQuery;
            final matchesSubject = m.subject.toLowerCase().contains(query);
            final matchesFrom = m.from.toLowerCase().contains(query);
            final matchesTo = m.to.toLowerCase().contains(query);
            final matchesSnippet = (m.snippet ?? '').toLowerCase().contains(query);
            if (!matchesSubject && !matchesFrom && !matchesTo && !matchesSnippet) {
              return false;
            }
          }
          return true;
        }).toList();

        final filterBanner = _buildFilterBanner(context);

        final content = Column(
          children: [
            if (isLoadingLocal || isSyncing) const LinearProgressIndicator(minHeight: 2),
            if (filterBanner != null) filterBanner,
            Expanded(
              child: RefreshIndicator(
          onRefresh: () async {
            if (_selectedAccountId != null) {
              await ref.read(emailListProvider.notifier).refresh(_selectedAccountId!, folderLabel: _selectedFolder);
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
                            onRestoreToInbox: _isLocalFolder ? () => _restoreLocalEmailToInbox(message) : null,
                onTap: () {
                  if (_selectedAccountId != null) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => EmailViewerDialog(
                        message: message,
                        accountId: _selectedAccountId!,
                        localFolderName: _isLocalFolder ? _selectedFolder : null,
                        onMarkRead: () async {
                          if (!message.isRead && !_isLocalFolder) {
                            await MessageRepository().updateRead(message.id, true);
                            ref.read(emailListProvider.notifier).setRead(message.id, true);
                            _enqueueGmailUpdate('markRead', message.id);
                          }
                        },
                      ),
                    );
                  }
                },
                onMarkRead: () async {
                  if (!message.isRead) {
                    await MessageRepository().updateRead(message.id, true);
                    ref.read(emailListProvider.notifier).setRead(message.id, true);
                    _enqueueGmailUpdate('markRead', message.id);
                  }
                },
                onStarToggle: (newValue) async {
                  await MessageRepository().updateStarred(message.id, newValue);
                  ref.read(emailListProvider.notifier).setStarred(message.id, newValue);
                  _enqueueGmailUpdate(newValue ? 'star' : 'unstar', message.id);
                },
                onLocalStateChanged: (state) async {
                  // Persist local tag for this message
                  await MessageRepository().updateLocalTag(message.id, state);
                  
                  // Sync to Firebase if enabled (only if changed from initial value)
                  final syncEnabled = await _firebaseSync.isSyncEnabled();
                  if (syncEnabled) {
                    // Always sync the localTagPersonal value (even if null, it represents a change)
                    try {
                      await _firebaseSync.syncEmailMeta(message.id, localTagPersonal: state);
                    } catch (e) {
                      // Log errors but don't crash the UI
                      debugPrint('[HomeScreen] ERROR in syncEmailMeta: $e');
                      if (kReleaseMode) {
                        debugPrint('[HomeScreen] ERROR in syncEmailMeta (release): $e');
                      }
                    }
                  }
                  
                  // Persist a sender preference (future emails rule)
                  // Note: Sender preferences are NOT synced to Firebase - they are derived
                  // locally from emailMeta changes on other devices
                  final senderEmail = _extractEmail(message.from);
                  if (senderEmail.isNotEmpty) {
                    await MessageRepository().setSenderDefaultLocalTag(senderEmail, state);
                  }
                  
                  // Silent update: do not trigger a provider loading state
                  ref.read(emailListProvider.notifier).setLocalTag(message.id, state);
                },
                onTrash: () async {
                  // Optimistic UI update first
                  if (_selectedFolder != 'TRASH') {
                    ref.read(emailListProvider.notifier).removeMessage(message.id);
                  } else {
                    ref.read(emailListProvider.notifier).setFolder(message.id, 'TRASH');
                  }
                  final src = message.folderLabel.toUpperCase();
                  if (src == 'ARCHIVE') {
                    unawaited(MessageRepository().updateFolderNoPrev(message.id, 'TRASH'));
                  } else {
                    unawaited(MessageRepository().updateFolderWithPrev(
                      message.id,
                      'TRASH',
                      prevFolderLabel: message.folderLabel,
                    ));
                  }
                  _enqueueGmailUpdate('trash:$src', message.id);

                  // If viewing a local folder, also remove the saved local copy (additional process)
                  if (_isLocalFolder) {
                    final localPath = _selectedFolder;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      unawaited(_localFolderService.removeEmailFromFolder(localPath, message.id));
                    });
                  }
                },
                onArchive: () async {
                  // Optimistic UI update first
                  if (_selectedFolder != 'ARCHIVE') {
                    ref.read(emailListProvider.notifier).removeMessage(message.id);
                  } else {
                    ref.read(emailListProvider.notifier).setFolder(message.id, 'ARCHIVE');
                  }
                  final src = message.folderLabel.toUpperCase();
                  if (src == 'TRASH') {
                    unawaited(MessageRepository().updateFolderNoPrev(message.id, 'ARCHIVE'));
                  } else {
                    unawaited(MessageRepository().updateFolderWithPrev(
                      message.id,
                      'ARCHIVE',
                      prevFolderLabel: message.folderLabel,
                    ));
                  }
                  _enqueueGmailUpdate('archive:$src', message.id);
                },
                onSaveToFolder: (folderName) async {
                  await _saveEmailToFolder(folderName, message);
                },
                onMoveToInbox: () async {
                  // Optimistic UI update first
                  if (_selectedFolder != 'INBOX') {
                    ref.read(emailListProvider.notifier).removeMessage(message.id);
                  } else {
                    ref.read(emailListProvider.notifier).setFolder(message.id, 'INBOX');
                  }
                  unawaited(MessageRepository().updateFolderWithPrev(
                    message.id,
                    'INBOX',
                    prevFolderLabel: message.folderLabel,
                  ));
                  _enqueueGmailUpdate('moveToInbox', message.id);
                },
                onRestore: () async {
                  // Optimistic: remove from current view immediately; background restore will adjust
                  ref.read(emailListProvider.notifier).removeMessage(message.id);
                  unawaited(() async {
                    await MessageRepository().restoreToPrev(message.id);
                    if (_selectedAccountId != null) {
                      final updated = await MessageRepository().getByIds(_selectedAccountId!, [message.id]);
                      final restored = updated[message.id];
                      if (restored != null) {
                        final dest = restored.folderLabel;
                        if (_selectedFolder == dest) {
                          ref.read(emailListProvider.notifier).setFolder(message.id, dest);
                        }
                        _enqueueGmailUpdate('restore:${dest.toUpperCase()}', message.id);
                      }
                    }
                  }());
                },
                onActionUpdated: (date, text, {bool? actionComplete}) async {
                  // Capture original detected action for feedback
                  final originalAction = message.hasAction
                      ? ActionResult(
                          actionDate: message.actionDate ?? DateTime.now(),
                          confidence: message.actionConfidence ?? 0.0,
                          insightText: message.actionInsightText ?? '',
                        )
                      : null;
                  
                  await MessageRepository().updateAction(message.id, date, text, null, actionComplete);
                  ref.read(emailListProvider.notifier).setAction(message.id, date, text, actionComplete: actionComplete);
                  final hasActionNow = date != null || (text != null && text.isNotEmpty);
                  
                  // Record feedback for ML training
                  final userAction = date != null || text != null
                      ? ActionResult(
                          actionDate: date ?? DateTime.now(),
                          confidence: 1.0, // User-provided actions have max confidence
                          insightText: text ?? '',
                        )
                      : null;
                  
                  // Determine feedback type
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
                  
                  // Sync to Firebase if enabled (only if changed from initial value)
                  final syncEnabled = await _firebaseSync.isSyncEnabled();
                  if (syncEnabled) {
                    // Get current message to check if action actually changed
                    final currentDate = message.actionDate;
                    final currentText = message.actionInsightText;
                    final currentComplete = message.actionComplete;
                    if (currentDate != date || currentText != text || currentComplete != actionComplete || !hasActionNow) {
                      await _firebaseSync.syncEmailMeta(
                        message.id,
                        actionDate: hasActionNow ? date : null,
                        actionInsightText: hasActionNow ? text : null,
                        actionComplete: hasActionNow ? actionComplete : null,
                        clearAction: !hasActionNow,
                      );
                    }
                  }
                },
                onActionCompleted: () async {
                  await MessageRepository().updateAction(message.id, null, null);
                  ref.read(emailListProvider.notifier).setAction(message.id, null, null);
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
                  ref.read(emailListProvider.notifier).refresh(_selectedAccountId!);
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
    if (messageIds.isEmpty || _selectedAccountId == null || _isLocalFolder) return;
    
    try {
      // Batch update in database
      await MessageRepository().batchUpdateRead(messageIds, true);
      
      // Update UI state for all messages
      for (final messageId in messageIds) {
        ref.read(emailListProvider.notifier).setRead(messageId, true);
        // Enqueue Gmail API update
        _enqueueGmailUpdate('markRead', messageId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked ${messageIds.length} email${messageIds.length == 1 ? '' : 's'} as read'),
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
        final localCount = await MessageRepository().getUnreadCountByFolder(account.id, 'INBOX');
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
      localCount = await MessageRepository().getUnreadCountByFolder(accountId, 'INBOX');
    } catch (_) {
      // Keep existing count if refresh fails
    }

    if (!mounted) {
      _pendingLocalUnreadAccounts.remove(accountId);
      if (localCount != null) {
        _accountUnreadCounts[accountId] = localCount;
      }
      return;
    }

    setState(() {
      _pendingLocalUnreadAccounts.remove(accountId);
      if (localCount != null) {
        _accountUnreadCounts[accountId] = localCount;
      }
    });
  }

  /// Refresh unread count for a specific account from local DB
  Future<void> _refreshAccountUnreadCountLocal(String accountId) async {
    if (_pendingLocalUnreadAccounts.contains(accountId)) {
      return;
    }
    try {
      final localCount = await MessageRepository().getUnreadCountByFolder(accountId, 'INBOX');
      if (mounted) {
        setState(() {
          _accountUnreadCounts[accountId] = localCount;
        });
      } else {
        _accountUnreadCounts[accountId] = localCount;
      }
    } catch (_) {
      // Keep existing count if refresh fails
    }
  }

  /// Get unread count for an account using Gmail API /users/me/labels/INBOX endpoint
  Future<int> _getGmailUnreadCount(String accountId) async {
    final authAccount = await GoogleAuthService().ensureValidAccessToken(accountId);
    if (authAccount == null || authAccount.accessToken.isEmpty) {
      // Fallback to local DB if no token
      return await MessageRepository().getUnreadCountByFolder(accountId, 'INBOX');
    }

    final uri = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${authAccount.accessToken}'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['messagesUnread'] as int? ?? 0;
    } else {
      // Fallback to local DB on API error
      return await MessageRepository().getUnreadCountByFolder(accountId, 'INBOX');
    }
  }

  @override
  void dispose() {
    _unreadCountRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<String> _activeFilterLabels() {
    final labels = <String>[];

    if (_selectedLocalState != null) {
      labels.add('${_selectedLocalState!} Emails');
    }

    if (_selectedActionFilter != null) {
      final actionLabel = () {
        switch (_selectedActionFilter) {
          case AppConstants.filterToday:
            return AppConstants.actionSummaryToday;
          case AppConstants.filterUpcoming:
            return 'Future';
          case AppConstants.filterOverdue:
            return AppConstants.actionSummaryOverdue;
          case AppConstants.filterPossible:
            return AppConstants.filterPossible;
          default:
            return AppConstants.actionSummaryAll;
        }
      }();
      labels.add('Action: $actionLabel');
    }

    if (_stateFilter != null) {
      labels.add(_stateFilter!);
    }

    if (_selectedCategories.isNotEmpty) {
      final names = _selectedCategories
          .map((c) => AppConstants.categoryDisplayNames[c] ?? c)
          .join(', ');
      labels.add('Categories: $names');
    }

    if (_searchQuery.isNotEmpty) {
      final raw = _searchController.text.trim();
      if (raw.isNotEmpty) {
        labels.add('Search: "$raw"');
      } else {
        labels.add('Search filters applied');
      }
    }

    return labels;
  }

  Widget? _buildFilterBanner(BuildContext context) {
    final labels = _activeFilterLabels();
    if (labels.isEmpty) return null;

    final theme = Theme.of(context);
    final textColor = const Color(0xFF333333);
    final bannerColor = ActionMailTheme.alertColor.withValues(alpha: 0.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.center,
              children: labels
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _clearAllFilters,
            style: TextButton.styleFrom(
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

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
}

