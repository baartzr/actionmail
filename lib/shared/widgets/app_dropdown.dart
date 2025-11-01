import 'package:flutter/material.dart';

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
    
    return DropdownButton<T>(
      value: value,
      hint: hint != null ? Text(
        hint!,
        style: TextStyle(color: selectedTextColor, fontSize: 13),
      ) : null,
      icon: Icon(Icons.arrow_drop_down, color: selectedTextColor),
      selectedItemBuilder: (context) {
        return items.map((item) {
          return Text(
            itemBuilder(item),
            style: TextStyle(color: selectedTextColor, fontSize: 13),
          );
        }).toList();
      },
      items: items.map((item) {
        return DropdownMenuItem<T>(
          value: item,
          child: Text(
            itemBuilder(item),
            style: TextStyle(color: cs.onSurface, fontSize: 13),
          ),
        );
      }).toList(),
      onChanged: onChanged,
      underline: const SizedBox.shrink(),
      isDense: isDense,
      style: TextStyle(color: selectedTextColor, fontSize: 13),
      dropdownColor: cs.surface,
      menuMaxHeight: 300,
      iconSize: 20,
    );
  }
}

