import 'package:flutter/material.dart';

/// AppBar state switch widget (All/Personal/Business)
class HomeAppBarStateSwitch extends StatelessWidget {
  final String? selectedLocalState;
  final Function(String?) onStateChanged;

  const HomeAppBarStateSwitch({
    super.key,
    required this.selectedLocalState,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate approximate button widths (text only, no icons)
        // All button: text (~30) + padding (20) ≈ 50
        // Personal button: text (~60) + padding (20) ≈ 80
        // Business button: text (~65) + padding (20) ≈ 85
        const double allButtonWidth = 50.0;
        const double allTextWidth = 30.0;
        const double personalButtonWidth = 80.0;
        const double personalTextWidth = 60.0;
        const double businessTextWidth = 65.0;

        double underlineLeft = 0;
        double underlineWidth = 0;

        if (selectedLocalState == null) {
          // All selected
          underlineLeft = 0;
          underlineWidth = allTextWidth;
        } else if (selectedLocalState == 'Personal') {
          underlineLeft = allButtonWidth;
          underlineWidth = personalTextWidth;
        } else if (selectedLocalState == 'Business') {
          underlineLeft = allButtonWidth + personalButtonWidth;
          underlineWidth = businessTextWidth;
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Row of text-only switch buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAppBarStateButton(
                  context,
                  'All',
                  'Show All messages',
                  selectedLocalState == null,
                  () => onStateChanged(null),
                ),
                _buildAppBarStateButton(
                  context,
                  'Personal',
                  'Show messages tagged as Personal',
                  selectedLocalState == 'Personal',
                  () => onStateChanged('Personal'),
                ),
                _buildAppBarStateButton(
                  context,
                  'Business',
                  'Show messages tagged as Business',
                  selectedLocalState == 'Business',
                  () => onStateChanged('Business'),
                ),
              ],
            ),
            // Sliding underline indicator
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
    String toolTip,
    bool selected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);

    // Color for text - white for better visibility on teal background
    final Color textColor = Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).colorScheme.onPrimary;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: toolTip, // <-- change this
        waitDuration: const Duration(milliseconds: 500),
        showDuration: const Duration(seconds: 2),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              state,
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

