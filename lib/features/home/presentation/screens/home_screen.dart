import 'package:flutter/material.dart';
import 'package:actionmail/shared/widgets/app_toggle_chip.dart';
import 'package:actionmail/shared/widgets/app_dropdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/constants/app_constants.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/features/home/presentation/widgets/email_tile.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/features/settings/presentation/accounts_settings_dialog.dart';
import 'package:actionmail/features/home/presentation/windows/actions_window.dart';
import 'package:actionmail/features/home/presentation/windows/actions_summary_window.dart';
import 'package:actionmail/features/home/presentation/windows/attachments_window.dart';
import 'package:actionmail/features/home/presentation/windows/subscriptions_window.dart';
import 'package:actionmail/features/home/presentation/windows/shopping_window.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:actionmail/features/home/presentation/widgets/account_selector_dialog.dart';
import 'package:actionmail/features/home/presentation/widgets/email_viewer_dialog.dart';
import 'package:actionmail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'dart:async';

/// Main home screen for ActionMail
/// Displays email list with filters and action management
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Selected folder (default to Inbox)
  String _selectedFolder = AppConstants.folderInbox;
  // Accounts
  String? _selectedAccountId;
  List<GoogleAccount> _accounts = [];
  bool _initializedFromRoute = false;
  
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

  Future<void> _loadAccounts() async {
    final svc = GoogleAuthService();
    final list = await svc.loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = list;
    });
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
    await _loadAccounts();
    if (!mounted) return;
    final selectedAccount = await showDialog<String>(
      context: context,
      builder: (context) => AccountSelectorDialog(
        accounts: _accounts,
        selectedAccountId: _selectedAccountId,
      ),
    );
    // Reload accounts to ensure we have the latest list (including newly added accounts)
    await _loadAccounts();
    if (!mounted) return;
    if (selectedAccount != null) {
      // Verify the account still exists in the list
      if (_accounts.any((acc) => acc.id == selectedAccount)) {
        setState(() {
          _selectedAccountId = selectedAccount;
        });
        await _saveLastActiveAccount(selectedAccount);
        if (_selectedAccountId != null) {
          // Use loadEmails for account switch to trigger full initial sync if needed
          await ref.read(emailListProvider.notifier).loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
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
  }

  @override
  Widget build(BuildContext context) {
    // Initialize selected account from route args if provided
    if (!_initializedFromRoute) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _selectedAccountId = args;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadAccounts();
        if (_selectedAccountId == null && _accounts.isNotEmpty) {
          // Try to load last active account from preferences
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
          await ref.read(emailListProvider.notifier).loadEmails(_selectedAccountId!, folderLabel: _selectedFolder);
        }
      });
      _initializedFromRoute = true;
    }
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight((kToolbarHeight * 1.5) + MediaQuery.of(context).padding.top),
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
                              onPressed: _showAccountSelectorDialog,
                              icon: Icon(
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
                            // Folder dropdown on left
                            AppDropdown<String>(
                              value: _selectedFolder,
                              items: const ['INBOX','SENT','TRASH','SPAM','ARCHIVE'],
                              itemBuilder: (folder) => AppConstants.folderDisplayNames[folder] ?? folder,
                              textColor: Theme.of(context).appBarTheme.foregroundColor,
                              onChanged: (value) async {
                                if (value != null) {
                                  setState(() {
                                    _selectedFolder = value;
                                  });
                                  if (_selectedAccountId != null) {
                                    await ref.read(emailListProvider.notifier).loadFolder(_selectedAccountId!, folderLabel: _selectedFolder);
                                  }
                                }
                              },
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
                                    showDialog(context: context, builder: (_) => const ActionsWindow());
                                    break;
                                  case 'Account Digest':
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
                                  // Actions and other function windows (excluding Actions Summary)
                                  ...AppConstants.allFunctionWindows.where((window) => window != AppConstants.windowActionsSummary).map((window) {
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
                                  const PopupMenuDivider(),
                                  // Account Digest (moved to bottom)
                                  PopupMenuItem(
                                    value: 'Account Digest',
                                    child: Row(
                                      children: [
                                        Icon(Icons.dashboard_outlined, size: 18, color: cs.onSurface),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Account Digest',
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

  // Left panel for desktop
  Widget _buildLeftPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('Filters', style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          // Reuse existing controls if desired later
          // Placeholder for future nav/filters
        ],
      ),
    );
  }

  // Main content column extracted from previous body
  Widget _buildMainColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            () {
              setState(() {
                _stateFilter = _stateFilter == 'Unread' ? null : 'Unread';
              });
            },
          ),
          SizedBox(width: isDesktop ? 2 : 8),
          _buildSophisticatedFilterButton(
            context,
            'Starred',
            Icons.star_border,
            Icons.star,
            _stateFilter == 'Starred',
            () {
              setState(() {
                _stateFilter = _stateFilter == 'Starred' ? null : 'Starred';
              });
            },
          ),
          SizedBox(width: isDesktop ? 2 : 8),
          _buildSophisticatedFilterButton(
            context,
            'Important',
            Icons.label_outline,
            Icons.label,
            _stateFilter == 'Important',
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
    
    return Material(
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
              ],
            ],
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

  // Right panel for desktop
  Widget _buildRightPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('Details', style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          // Placeholder for preview/details
        ],
      ),
    );
  }

  // Placeholder for background Gmail update scheduling
  void _enqueueGmailUpdate(String action, String messageId) {
    if (_selectedAccountId == null) return;
    // Enqueue to DB; processing is triggered by refresh/incremental sync
    MessageRepository().enqueuePendingOp(_selectedAccountId!, messageId, action);
    // Also trigger immediate background processing so Gmail updates quickly
    unawaited(GmailSyncService().processPendingOps());
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
              int countToday = 0, countUpcoming = 0, countOverdue = 0;
              emailsValue.whenData((emails) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                for (final m in emails) {
                  if (m.actionDate == null) continue;
                  // Filter by Personal/Business selection
                  if (_selectedLocalState != null && m.localTagPersonal != _selectedLocalState) {
                    continue;
                  }
                  // Exclude completed actions
                  if (m.actionInsightText != null && 
                      m.actionInsightText!.toLowerCase().contains('complete')) {
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate approximate button widths and text widths
        // Personal button: icon (16) + spacing (4) + text (~60) + padding (20) ≈ 100
        // Personal text width: ~60
        // Business button: icon (16) + spacing (4) + text (~65) + padding (20) ≈ 105
        // Business text width: ~65
        const double personalButtonWidth = 95.0;
        const double businessButtonWidth = 100.0;
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
    final cs = theme.colorScheme;
    
    // Color for icons and text - white for better visibility on teal background
    const Color iconColor = Colors.white;
    const Color textColor = Colors.white;
    
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
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedLocalStateButtons(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPersonal = _selectedLocalState == 'Personal';
    final isBusiness = _selectedLocalState == 'Business';
    
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
          _buildSophisticatedStateButton(
            context,
            'Personal',
            Icons.person_outline,
            Icons.person,
            isPersonal,
          ),
          _buildSophisticatedStateButton(
            context,
            'Business',
            Icons.business_center_outlined,
            Icons.business,
            isBusiness,
          ),
        ],
      ),
    );
  }

  Widget _buildSophisticatedStateButton(
    BuildContext context,
    String state,
    IconData outlinedIcon,
    IconData filledIcon,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 900;
    
    // Color for Personal/Business icons
    Color iconColor;
    if (selected) {
      iconColor = cs.onPrimaryContainer;
    } else {
      iconColor = state == 'Personal' 
          ? const Color(0xFF2196F3) // Blue for Personal
          : const Color(0xFF9C27B0); // Purple for Business
    }
    
    return Material(
      color: selected ? cs.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            // Toggle: if already selected, deselect; otherwise select
            _selectedLocalState = selected ? null : state;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 12, 
            vertical: 6
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? filledIcon : outlinedIcon,
                size: 18,
                color: iconColor,
              ),
              // Hide text on mobile
              if (!isMobile) ...[
                const SizedBox(width: 6),
                Text(
                  state,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

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
    switch (filter) {
      case AppConstants.filterToday:
        label = AppConstants.actionSummaryToday;
        break;
      case AppConstants.filterUpcoming:
        label = 'Future';
        break;
      case AppConstants.filterOverdue:
        label = AppConstants.actionSummaryOverdue;
        break;
      default:
        label = AppConstants.actionSummaryAll;
    }
    final displayText = '$label ($count)';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
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
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 12,
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
            if (m.actionDate == null) return false;
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final d = DateTime(m.actionDate!.year, m.actionDate!.month, m.actionDate!.day);
            switch (_selectedActionFilter) {
              case AppConstants.filterToday:
                if (d != today) return false;
                break;
              case AppConstants.filterUpcoming:
                if (!d.isAfter(today)) return false;
                break;
              case AppConstants.filterOverdue:
                if (!d.isBefore(today)) return false;
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

        final content = Column(
          children: [
            if (isLoadingLocal || isSyncing) const LinearProgressIndicator(minHeight: 2),
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
                onTap: () {
                  if (_selectedAccountId != null) {
                    showDialog(
                      context: context,
                      builder: (ctx) => EmailViewerDialog(
                        message: message,
                        accountId: _selectedAccountId!,
                      ),
                    );
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
                  // Persist a sender preference (future emails rule)
                  final senderEmail = _extractEmail(message.from);
                  if (senderEmail.isNotEmpty) {
                    await MessageRepository().setSenderDefaultLocalTag(senderEmail, state);
                  }
                  // Silent update: do not trigger a provider loading state
                  ref.read(emailListProvider.notifier).setLocalTag(message.id, state);
                },
                onTrash: () async {
                  // Move to TRASH: record previous and update folder
                  await MessageRepository().updateFolderWithPrev(
                    message.id,
                    'TRASH',
                    prevFolderLabel: message.folderLabel,
                  );
                  // Remove from current view if not TRASH folder
                  if (_selectedFolder != 'TRASH') {
                    ref.read(emailListProvider.notifier).removeMessage(message.id);
                  } else {
                    ref.read(emailListProvider.notifier).setFolder(message.id, 'TRASH');
                  }
                  // Include source label so Gmail modify removes it appropriately (INBOX or SENT)
                  final src = message.folderLabel.toUpperCase();
                  _enqueueGmailUpdate('trash:$src', message.id);
                },
                onArchive: () async {
                  // Move to ARCHIVE: remove any primary label
                  await MessageRepository().updateFolderWithPrev(
                    message.id,
                    'ARCHIVE',
                    prevFolderLabel: message.folderLabel,
                  );
                  if (_selectedFolder != 'ARCHIVE') {
                    ref.read(emailListProvider.notifier).removeMessage(message.id);
                  } else {
                    ref.read(emailListProvider.notifier).setFolder(message.id, 'ARCHIVE');
                  }
                  final src = message.folderLabel.toUpperCase();
                  _enqueueGmailUpdate('archive:$src', message.id);
                },
                onRestore: () async {
                  // Restore to previous folder
                  await MessageRepository().restoreToPrev(message.id);
                  // Fetch updated message to know the restored folder
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
                    } else {
                      ref.read(emailListProvider.notifier).removeMessage(message.id);
                    }
                  } else {
                    ref.read(emailListProvider.notifier).removeMessage(message.id);
                  }
                },
                onActionUpdated: (date, text) async {
                  await MessageRepository().updateAction(message.id, date, text);
                  ref.read(emailListProvider.notifier).setAction(message.id, date, text);
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

