import 'package:flutter/material.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Floating draggable account widget that expands on hover
class FloatingAccountWidget extends StatefulWidget {
  final List<GoogleAccount> accounts;
  final String? selectedAccountId;
  final Map<String, int> accountUnreadCounts;
  final ValueChanged<String> onAccountSelected;

  const FloatingAccountWidget({
    super.key,
    required this.accounts,
    required this.selectedAccountId,
    required this.accountUnreadCounts,
    required this.onAccountSelected,
  });

  @override
  State<FloatingAccountWidget> createState() => _FloatingAccountWidgetState();
}

class _FloatingAccountWidgetState extends State<FloatingAccountWidget> {
  bool _isExpanded = false;
  Offset _position = const Offset(16, 80); // Default position (top-left area)
  bool _isDragging = false;
  Offset? _dragStartPosition;
  Offset? _dragStartOffset;

  static const String _prefsKeyPosition = 'floating_account_widget_position';

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('${_prefsKeyPosition}_x');
    final y = prefs.getDouble('${_prefsKeyPosition}_y');
    if (x != null && y != null) {
      if (mounted) {
        setState(() {
          _position = Offset(x, y);
        });
      }
    }
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_prefsKeyPosition}_x', _position.dx);
    await prefs.setDouble('${_prefsKeyPosition}_y', _position.dy);
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragStartPosition = details.globalPosition;
      _dragStartOffset = _position;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_dragStartPosition != null && _dragStartOffset != null) {
      final delta = details.globalPosition - _dragStartPosition!;
      setState(() {
        _position = _dragStartOffset! + delta;
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _dragStartPosition = null;
      _dragStartOffset = null;
    });
    _savePosition();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.accounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedAccount = widget.accounts.firstWhere(
      (acc) => acc.id == widget.selectedAccountId,
      orElse: () => widget.accounts.first,
    );

    final unreadCount = widget.accountUnreadCounts[selectedAccount.id] ?? 0;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: MouseRegion(
        onEnter: (_) {
          if (!_isDragging) {
            setState(() => _isExpanded = true);
          }
        },
        onExit: (_) {
          if (!_isDragging) {
            setState(() => _isExpanded = false);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: _isExpanded ? 280 : 48,
          constraints: BoxConstraints(
            minHeight: 48,
            maxHeight: _isExpanded ? 400 : 48,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onPanStart: _handlePanStart,
              onPanUpdate: _handlePanUpdate,
              onPanEnd: _handlePanEnd,
              child: _isExpanded ? _buildExpanded() : _buildCollapsed(selectedAccount, unreadCount),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed(GoogleAccount account, int unreadCount) {
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Center(
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: account.photoUrl != null
                  ? ClipOval(
                      child: Image.network(
                        account.photoUrl!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.account_circle,
                          size: 20,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.account_circle,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpanded() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with drag handle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.drag_handle,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Accounts',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Icon(
                Icons.account_circle,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        // Account list
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.accounts.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
            itemBuilder: (context, index) {
              final account = widget.accounts[index];
              final isSelected = account.id == widget.selectedAccountId;
              final unreadCount = widget.accountUnreadCounts[account.id] ?? 0;

              return InkWell(
                onTap: () {
                  widget.onAccountSelected(account.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primaryContainer,
                        child: account.photoUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  account.photoUrl!,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.account_circle,
                                    size: 20,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.account_circle,
                                size: 20,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                      ),
                      const SizedBox(width: 12),
                      // Email and unread count
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.email,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (unreadCount > 0)
                              Text(
                                '$unreadCount unread',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      // Selected indicator
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
