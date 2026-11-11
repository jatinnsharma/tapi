import 'package:flutter/material.dart';

/// Spacing scale shared by all screens.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Standard page padding.
  static const EdgeInsets page = EdgeInsets.fromLTRB(20, 8, 20, 24);
}

/// Corner radii shared by all components.
class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
}

class AppTheme {
  AppTheme._();

  static const Color seedColor = Colors.green;

  static const Color deepGreen = Color(0xFF14532D);
  static const Color primaryGreen = Color(0xFF237A4B);
  static const Color primary = primaryGreen;
  static const Color emerald = Color(0xFF1FA36B);

  /// Darkest brand green: selected nav item, selected chips, hero start.
  static const Color forest = Color(0xFF0F3D2B);

  /// Soft sage used in gradients and subtle tinting.
  static const Color sage = Color(0xFFC4E4CF);

  /// Warm cream background/surface tone.
  static const Color cream = Color(0xFFF7FBF5);

  /// Warm accent used for primary actions on dark surfaces, XP and badges.
  static const Color amber = Color(0xFFF5A623);

  /// Amber that is dark enough to read as text on a light background.
  static const Color amberText = Color(0xFFB45F06);

  /// Hero card gradient: deep forest to lively emerald.
  static const List<Color> heroGradient = [
    Color(0xFF0D3F2E),
    Color(0xFF17694B),
    Color(0xFF26996C),
  ];

  /// Main text colour: a very dark green-tinted ink, softer than pure black.
  static const Color ink = Color(0xFF0F2A1E);

  /// Secondary text colour.
  static const Color inkMuted = Color(0xFF55675C);

  /// Page gradient, painted from the right edge towards the left. It is a
  /// restrained wash: a soft sage on the right edge that dissolves into a
  /// near-white mint, so cards and the deep-green hero carry the colour.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [
      Color(0xFFC4E4CF), // soft sage on the right edge
      Color(0xFFDDEFE2),
      Color(0xFFEDF5EE),
      Color(0xFFF5F9F5), // near-white mint on the left
    ],
    stops: [0.0, 0.25, 0.6, 1.0],
  );

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    ).copyWith(primary: primaryGreen, surface: const Color(0xFFF7FBF5));

    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    final textTheme = base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineMedium: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
            color: ink,
          ),
          headlineSmall: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.2,
            color: ink,
          ),
          titleLarge: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: ink,
          ),
          titleMedium: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: ink,
          ),
          bodyMedium: const TextStyle(height: 1.4, color: ink),
          bodyLarge: const TextStyle(height: 1.45, color: ink),
        );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    return base.copyWith(
      textTheme: textTheme,
      // Transparent so the gradient from AppBackground shows through.
      scaffoldBackgroundColor: Colors.transparent,
      splashColor: primaryGreen.withValues(alpha: 0.10),
      highlightColor: primaryGreen.withValues(alpha: 0.05),
      hoverColor: primaryGreen.withValues(alpha: 0.06),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: deepGreen,
        titleTextStyle: TextStyle(
          color: deepGreen,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        color: Colors.white.withValues(alpha: 0.94),
        shadowColor: forest.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.8),
            width: 1.2,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // Translucent: the frosted look comes from the blur in MainLayout.
        backgroundColor: Colors.white.withValues(alpha: 0.55),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: emerald.withValues(alpha: 0.28),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? deepGreen
                : Colors.grey.shade700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? deepGreen
                : Colors.grey.shade700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: forest,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: emerald.withValues(alpha: 0.5),
              shape: buttonShape,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ).copyWith(
              // Lift with a glow on hover/press.
              elevation: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) return 1;
                if (states.contains(WidgetState.hovered)) return 8;
                return 3;
              }),
            ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: forest,
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          backgroundColor: Colors.white.withValues(alpha: 0.5),
          side: const BorderSide(color: primaryGreen, width: 1.4),
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: deepGreen,
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: forest,
        foregroundColor: Colors.white,
        elevation: 6,
        hoverElevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.7),
        selectedColor: emerald.withValues(alpha: 0.3),
        side: BorderSide(color: primaryGreen.withValues(alpha: 0.25)),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.78),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: primaryGreen.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: emerald, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        iconColor: primaryGreen,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFF7FBF5),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFF7FBF5),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: deepGreen,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: buttonShape,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: emerald),
    );
  }
}
