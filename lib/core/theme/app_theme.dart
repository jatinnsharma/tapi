import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Spacing scale shared by all screens (4-point grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double smd = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Standard page padding: a 20 px side gutter on phones.
  static const EdgeInsets page = EdgeInsets.fromLTRB(20, 8, 20, 24);

  /// Widest a reading screen gets on tablets and the web.
  static const double readingWidth = 720;
}

/// Corner radii shared by all components: four steps plus pill.
class AppRadius {
  AppRadius._();

  /// Chips, small images, tags.
  static const double sm = 8;

  /// Cards, inputs, list groups.
  static const double md = 12;

  /// Hero media, large cards.
  static const double lg = 20;

  /// Sheets and dialogs.
  static const double xl = 28;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
}

/// Animation durations. Every animation must also check
/// `MediaQuery.disableAnimationsOf(context)` (reduced motion).
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}

/// Elevation: almost everything is flat (level 0). Only the one floating
/// layer of a screen (a sheet, the FAB, a sticky action bar, the tab bar)
/// gets [level1].
class AppElevation {
  AppElevation._();

  static const List<BoxShadow> level0 = [];

  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x1A0F2A1E), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

/// Colours a [ColorScheme] has no slot for: status colours, the reward
/// accent and the text and surface tiers. Read with
/// `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.reward,
    required this.rewardText,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.infoContainer,
  });

  /// Page background (flat).
  final Color bg;

  /// Cards and sheets.
  final Color surface;

  /// Grouped rows, input fills, skeletons.
  final Color surfaceMuted;

  /// Hairline borders between flat surfaces.
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  /// XP, stars and stamps only: never for warnings.
  final Color reward;
  final Color rewardText;

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color info;
  final Color infoContainer;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  static const light = AppColors(
    bg: Color(0xFFF6F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF1EE),
    border: Color(0xFFDDE3DE),
    textPrimary: Color(0xFF14201A),
    textSecondary: Color(0xFF56635B),
    textDisabled: Color(0xFF9AA59F),
    reward: Color(0xFFF5A623),
    rewardText: Color(0xFFA35A00),
    success: Color(0xFF1A7046),
    successContainer: Color(0xFFDDF3E6),
    warning: Color(0xFF9A5B00),
    warningContainer: Color(0xFFFFF0D6),
    danger: Color(0xFFC62828),
    dangerContainer: Color(0xFFFDE4E4),
    info: Color(0xFF1D4ED8),
    infoContainer: Color(0xFFE2EAFD),
  );

  static const dark = AppColors(
    bg: Color(0xFF0E1311),
    surface: Color(0xFF161C19),
    surfaceMuted: Color(0xFF1D2420),
    border: Color(0xFF2A332E),
    textPrimary: Color(0xFFE9EEEB),
    textSecondary: Color(0xFFA9B4AE),
    textDisabled: Color(0xFF66716B),
    reward: Color(0xFFF5B547),
    rewardText: Color(0xFFF5B547),
    success: Color(0xFF5FC79A),
    successContainer: Color(0xFF123D2B),
    warning: Color(0xFFF2B866),
    warningContainer: Color(0xFF3A2A10),
    danger: Color(0xFFFF8A80),
    dangerContainer: Color(0xFF3D1616),
    info: Color(0xFF93B4FF),
    infoContainer: Color(0xFF16243F),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      other is AppColors && t >= 0.5 ? other : this;
}

class AppTheme {
  AppTheme._();

  /// The brand colour the colour scheme is built from.
  static const Color seedColor = Color(0xFF1F6F4A);

  // Brand greens. The names stay so existing screens keep working; their
  // values are the calmer v2 palette (UI_REDESIGN.md, section 5.1).
  static const Color deepGreen = Color(0xFF14532D);
  static const Color primaryGreen = Color(0xFF1F6F4A);
  static const Color primary = primaryGreen;

  /// Lively accent green: progress and highlights on dark surfaces. Not
  /// for text or thin lines on white (too little contrast).
  static const Color emerald = Color(0xFF1FA36B);

  /// Darkest brand green: primary buttons, selected items, hero start.
  static const Color forest = Color(0xFF0F3D2B);

  /// Soft sage for subtle tinting.
  static const Color sage = Color(0xFFC4E4CF);

  /// Light surface for sheets and dialogs.
  static const Color cream = Color(0xFFFFFFFF);

  /// Reward accent: XP, stars, stamps. Fill colour; use [amberText] for text.
  static const Color amber = Color(0xFFF5A623);

  /// Amber dark enough to read as text on white (about 4.6:1).
  static const Color amberText = Color(0xFFA35A00);

  /// Hero imagery only: deep forest to emerald.
  static const List<Color> heroGradient = [
    Color(0xFF0D3F2E),
    Color(0xFF17694B),
    Color(0xFF26996C),
  ];

  /// Main text.
  static const Color ink = Color(0xFF14201A);

  /// Secondary text (meets 4.5:1 on white and on the page background).
  static const Color inkMuted = Color(0xFF56635B);

  /// Map pins for things that aren't places: food spots and voice notes.
  /// Dark enough for a white icon (at least 4.5:1).
  static const Color mapFood = Color(0xFFB4532A);
  static const Color mapVoice = Color(0xFF5B3FB0);

  /// The page background: flat. Kept as a gradient type for code that
  /// still paints it; both ends are the same calm colour.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFFF6F7F5), Color(0xFFF6F7F5)],
  );

  /// The type scale (UI_REDESIGN.md, section 5.2): nothing below 12 sp,
  /// weights 400–700. Inter, with Noto Sans Devanagari for Hindi.
  static TextTheme _textTheme(Color primary, Color secondary) {
    TextStyle s(double size, FontWeight weight, {double? height, Color? c}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: c ?? primary,
        );
    return TextTheme(
      displaySmall: s(32, FontWeight.w700, height: 1.15),
      headlineMedium: s(24, FontWeight.w700, height: 1.2),
      headlineSmall: s(22, FontWeight.w700, height: 1.25),
      titleLarge: s(20, FontWeight.w600, height: 1.3),
      titleMedium: s(17, FontWeight.w600, height: 1.3),
      titleSmall: s(15, FontWeight.w600, height: 1.3),
      bodyLarge: s(16, FontWeight.w400, height: 1.45),
      bodyMedium: s(14, FontWeight.w400, height: 1.45),
      bodySmall: s(12, FontWeight.w500, height: 1.35, c: secondary),
      labelLarge: s(14, FontWeight.w600),
      labelMedium: s(13, FontWeight.w600),
      labelSmall: s(12, FontWeight.w500, c: secondary),
    );
  }

  static const String fontFamily = 'Inter';
  static const List<String> fontFallback = ['NotoSansDevanagari'];

  static ThemeData get light => _build(Brightness.light);

  /// Ready for when every screen reads colours from the theme (Phase 3 of
  /// UI_REDESIGN.md); the app still runs in light mode until then.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF5FC79A) : primaryGreen,
          onPrimary: isDark ? const Color(0xFF0E1311) : Colors.white,
          surface: c.surface,
          onSurface: c.textPrimary,
          onSurfaceVariant: c.textSecondary,
          outline: c.border,
          outlineVariant: c.border,
          error: c.danger,
        );
    final text = _textTheme(c.textPrimary, c.textSecondary);
    final buttonPrimary = isDark ? const Color(0xFF5FC79A) : forest;
    const pill = StadiumBorder();
    const minSize = Size(64, 48);
    final buttonText = text.labelLarge!;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: text,
      extensions: [c],
      scaffoldBackgroundColor: c.bg,
      splashColor: scheme.primary.withValues(alpha: 0.08),
      highlightColor: scheme.primary.withValues(alpha: 0.04),
      hoverColor: scheme.primary.withValues(alpha: 0.05),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          // Apple platforms keep their own slide, which brings back the
          // edge-swipe to go back.
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: c.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: buttonPrimary,
          foregroundColor: scheme.onPrimary,
          minimumSize: minSize,
          shape: pill,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        // Same as a filled button: one primary style, no glow.
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonPrimary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: minSize,
          shape: pill,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: c.border, width: 1.2),
          minimumSize: minSize,
          shape: pill,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: minSize,
          shape: pill,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: buttonPrimary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: const StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: c.border),
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.card,
          // Brand green, not emerald: emerald is about 3:1 on white.
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: c.danger),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        hintStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        minVerticalPadding: 10,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.surfaceMuted : const Color(0xFF14201A),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: isDark ? scheme.primary : const Color(0xFF9EE0BF),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: c.surfaceMuted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
        decoration: BoxDecoration(
          color: const Color(0xE614201A),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}
