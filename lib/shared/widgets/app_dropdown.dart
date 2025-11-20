import 'package:flutter/material.dart';
import 'package:domail/app/theme/actionmail_theme.dart';

/// Reusable dropdown widget with consistent styling
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T) itemBuilder;
  final void Function(T?) onChanged;
  final String? hint;
  final bool isDense;
  final Color? textColor;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.itemBuilder,
    required this.onChanged,
    this.hint,
    this.isDense = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // Use provided textColor or default gray color for dropdown text
    final selectedTextColor = textColor ?? cs.onSurface.withValues(alpha: 0.8);
    
    return Theme(
      data: theme.copyWith(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        listTileTheme: ListTileThemeData(
          selectedTileColor: ActionMailTheme.darkTealLight, // Try lighter variant
          selectedColor: cs.onSurface,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      child: DropdownButton<T>(
        value: value,
        hint: hint != null ? Text(
          hint!,
          style: TextStyle(color: selectedTextColor, fontSize: 14),
        ) : null,
        icon: Icon(Icons.arrow_drop_down, color: selectedTextColor),
        selectedItemBuilder: (context) {
          return items.map((item) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                itemBuilder(item),
                style: TextStyle(color: selectedTextColor, fontSize: 14),
              ),
            );
          }).toList();
        },
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                itemBuilder(item),
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
          );
        }).toList(),
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
        isDense: isDense,
        style: TextStyle(color: selectedTextColor, fontSize: 14),
        dropdownColor: cs.surface,
        menuMaxHeight: 300,
        iconSize: 24,
      ),
    );
  }
}

