import 'package:flutter/material.dart';

class ActionMailTheme {
  // Private constructor to prevent instantiation
  ActionMailTheme._();

  // Modern, minimal color scheme for ActionMail
  // Sophisticated slate-blue primary, muted accents
  static const Color primaryColor = Color(0xFF5B6C7D); // Sophisticated slate-blue
  static const Color todayColor = Color(0xFF4A90E2); // Soft blue for Today
  static const Color upcomingColor = Color(0xFF6BC688); // Muted green for Upcoming
  static const Color overdueColor = Color(0xFFE57373); // Soft red for Overdue
  static const Color actionColor = Color(0xFF9E7CC1); // Subtle purple for actions
  static const Color sentMessageColor = Color(0xFFFF6F61);
  static const Color incomingMessageColor = Color(0xFFA288E3);
  static const Color alertColor = Color(0xFFFFC857);
  
  // Dark teal colors for appbars and window headers (consistent across themes)
  static const Color darkTeal = Color(0xFF00695C); // Material Teal 800 - dark teal
  static const Color darkTealLight = Color(0xFF00897B); // Material Teal 600 - slightly lighter variant

  // Light theme - minimal, clean, lots of white space
  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: primaryColor,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE8EDF2),
    onPrimaryContainer: Color(0xFF2C3E50),
    secondary: actionColor,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF0EBF5),
    onSecondaryContainer: Color(0xFF4A3A5A),
    tertiary: todayColor,
    onTertiary: Colors.white,
    error: Color(0xFFC62828),
    onError: Colors.white,
    errorContainer: Color(0xFFFFEBEE),
    onErrorContainer: Color(0xFF8E0000),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1A1A1A),
    onSurfaceVariant: Color(0xFF6B6B6B),
    outline: Color(0xFFE0E0E0),
    outlineVariant: Color(0xFFF5F5F5),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF1A1A1A),
    onInverseSurface: Color(0xFFFFFFFF),
    inversePrimary: Color(0xFFA8BDD3),
    surfaceTint: primaryColor,
    surfaceContainerHighest: Color(0xFFF8F9FA),
    surfaceContainerHigh: Color(0xFFF5F5F5),
    surfaceContainer: Color(0xFFF1F1F1),
    surfaceContainerLow: Color(0xFFEFEFEF),
    surfaceDim: Color(0xFFE8E8E8),
    surfaceBright: Color(0xFFFFFFFF),
  );

  // Dark theme - deep, sophisticated, minimal
  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: Color(0xFF8FA3B8),
    onPrimary: Color(0xFF1A1F26),
    primaryContainer: Color(0xFF3A4A5A),
    onPrimaryContainer: Color(0xFFD6E4F0),
    secondary: Color(0xFFB9A8D4),
    onSecondary: Color(0xFF2A1F3A),
    secondaryContainer: Color(0xFF4A3A5A),
    onSecondaryContainer: Color(0xFFE8DBF5),
    tertiary: Color(0xFF7BB3E8),
    onTertiary: Color(0xFF0A1F2E),
    error: Color(0xFFFF5252),
    onError: Color(0xFF680000),
    errorContainer: Color(0xFF8E0000),
    onErrorContainer: Color(0xFFFFD6D6),
    surface: Color(0xFF121212),
    onSurface: Color(0xFFE8E8E8),
    onSurfaceVariant: Color(0xFFB8B8B8),
    outline: Color(0xFF3A3A3A),
    outlineVariant: Color(0xFF2A2A2A),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE8E8E8),
    onInverseSurface: Color(0xFF1A1A1A),
    inversePrimary: Color(0xFF5B6C7D),
    surfaceTint: Color(0xFF8FA3B8),
    surfaceContainerHighest: Color(0xFF2A2A2A),
    surfaceContainerHigh: Color(0xFF252525),
    surfaceContainer: Color(0xFF1F1F1F),
    surfaceContainerLow: Color(0xFF1A1A1A),
    surfaceDim: Color(0xFF121212),
    surfaceBright: Color(0xFF383838),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _lightColorScheme,
      scaffoldBackgroundColor: _lightColorScheme.surface,
      typography: Typography.material2021(),
      fontFamily: 'Roboto',
      
      // Minimal app bar - dark teal background
      appBarTheme: AppBarTheme(
        backgroundColor: darkTeal,
        foregroundColor: const Color(0xFFB2DFDB), // Light teal text for contrast on dark background
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: const Color(0xFFB2DFDB),
          fontSize: 18,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(
          color: const Color(0xFFB2DFDB),
          size: 22,
        ),
      ),
      
      // Clean cards with subtle elevation
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _lightColorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        color: _lightColorScheme.surface,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        surfaceTintColor: Colors.transparent,
      ),
      
      // Minimal chips
      chipTheme: ChipThemeData(
        backgroundColor: _lightColorScheme.surfaceContainerHighest,
        selectedColor: _lightColorScheme.primaryContainer,
        disabledColor: _lightColorScheme.surfaceContainerHigh,
        labelStyle: TextStyle(
          color: _lightColorScheme.onSurface,
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(
          color: _lightColorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        pressElevation: 0,
      ),
      
      // Refined buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightColorScheme.primary,
          foregroundColor: _lightColorScheme.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          ),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return 1;
            if (states.contains(WidgetState.hovered)) return 1;
            return 0;
          }),
        ),
      ),
      
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          elevation: WidgetStateProperty.all(0),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          )),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          side: WidgetStatePropertyAll(BorderSide(
            color: _lightColorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          )),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          )),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          )),
        ),
      ),
      
      // Minimal icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return _lightColorScheme.surfaceContainerHighest;
            }
            return Colors.transparent;
          }),
        ),
      ),
      
      // Clean input fields
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _lightColorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _lightColorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _lightColorScheme.primary,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: _lightColorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      
      // Text themes - minimal, clean
      textTheme: TextTheme(
        displayLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: -1),
        displayMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300, letterSpacing: -0.5),
        displaySmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: -0.5),
        headlineLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400, letterSpacing: -0.5),
        headlineMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, letterSpacing: -0.5),
        headlineSmall: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0),
        titleLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0),
        titleMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        titleSmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.15),
        bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
        bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
      
      // Dividers
      dividerTheme: DividerThemeData(
        color: _lightColorScheme.outline.withValues(alpha: 0.1),
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _darkColorScheme,
      scaffoldBackgroundColor: _darkColorScheme.surface,
      typography: Typography.material2021(),
      fontFamily: 'Roboto',
      
      // Minimal app bar - dark teal background
      appBarTheme: AppBarTheme(
        backgroundColor: darkTeal,
        foregroundColor: const Color(0xFFB2DFDB), // Light teal text for contrast on dark background
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: const Color(0xFFB2DFDB),
          fontSize: 18,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(
          color: const Color(0xFFB2DFDB),
          size: 22,
        ),
      ),
      
      // Clean cards with subtle elevation
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _darkColorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        color: _darkColorScheme.surfaceContainer,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        surfaceTintColor: Colors.transparent,
      ),
      
      // Minimal chips
      chipTheme: ChipThemeData(
        backgroundColor: _darkColorScheme.surfaceContainerHighest,
        selectedColor: _darkColorScheme.primaryContainer,
        disabledColor: _darkColorScheme.surfaceContainer,
        labelStyle: TextStyle(
          color: _darkColorScheme.onSurface,
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(
          color: _darkColorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        pressElevation: 0,
      ),
      
      // Refined buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkColorScheme.primary,
          foregroundColor: _darkColorScheme.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          ),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return 1;
            if (states.contains(WidgetState.hovered)) return 1;
            return 0;
          }),
        ),
      ),
      
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          elevation: WidgetStateProperty.all(0),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          )),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          side: WidgetStatePropertyAll(BorderSide(
            color: _darkColorScheme.outline.withValues(alpha: 0.4),
            width: 1,
          )),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          )),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            letterSpacing: 0.1,
          )),
        ),
      ),
      
      // Minimal icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return _darkColorScheme.surfaceContainerHighest;
            }
            return Colors.transparent;
          }),
        ),
      ),
      
      // Clean input fields
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _darkColorScheme.outline.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _darkColorScheme.outline.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _darkColorScheme.primary,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: _darkColorScheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      
      // Text themes - minimal, clean
      textTheme: TextTheme(
        displayLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: -1),
        displayMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300, letterSpacing: -0.5),
        displaySmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: -0.5),
        headlineLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400, letterSpacing: -0.5),
        headlineMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, letterSpacing: -0.5),
        headlineSmall: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0),
        titleLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0),
        titleMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        titleSmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.15),
        bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
        bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
      
      // Dividers
      dividerTheme: DividerThemeData(
        color: _darkColorScheme.outline.withValues(alpha: 0.15),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
