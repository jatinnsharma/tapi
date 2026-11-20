import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_components.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';

/// WCAG relative luminance and contrast ratio.
double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  home: Scaffold(body: child),
);

void main() {
  group('colour tokens meet WCAG AA', () {
    for (final (name, c) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      test('$name: text on page and surface', () {
        for (final bg in [c.bg, c.surface]) {
          expect(contrast(c.textPrimary, bg), greaterThanOrEqualTo(7));
          expect(contrast(c.textSecondary, bg), greaterThanOrEqualTo(4.5));
        }
      });

      test('$name: status text on its own container', () {
        for (final (fg, bg) in [
          (c.success, c.successContainer),
          (c.warning, c.warningContainer),
          (c.danger, c.dangerContainer),
          (c.info, c.infoContainer),
        ]) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
        }
      });
    }

    test('light: reward text and brand on white', () {
      final c = AppColors.light;
      expect(contrast(c.rewardText, c.surface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(AppTheme.primaryGreen, Colors.white),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppTheme.inkMuted, AppColors.light.bg),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  test('type scale: nothing below 12 sp, nothing above w700, Inter', () {
    final text = AppTheme.light.textTheme;
    for (final style in [
      text.displaySmall,
      text.headlineMedium,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
    ]) {
      expect(style!.fontSize, greaterThanOrEqualTo(12));
      expect(style.fontWeight!.value, lessThanOrEqualTo(700));
      expect(style.fontFamily, 'Inter');
    }
  });

  test('both themes carry the AppColors extension', () {
    expect(AppTheme.light.extension<AppColors>(), AppColors.light);
    expect(AppTheme.dark.extension<AppColors>(), AppColors.dark);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });

  testWidgets('buttons are at least 48 px tall; loading disables', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            AppButton(label: 'Start', onPressed: () => taps++),
            AppButton(label: 'Saving', onPressed: () => taps++, loading: true),
            AppIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(FilledButton).first).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byType(IconButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('Start'));
    await tester.tap(find.byType(CircularProgressIndicator));
    expect(taps, 1);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('status shows icon and words, not colour alone', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            StatusBanner(kind: StatusKind.warning, title: 'Heavy rain'),
            StatusBadge(kind: StatusKind.success, label: 'Safe'),
          ],
        ),
      ),
    );
    expect(find.text('Heavy rain'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Safe'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('sign-in prompt and error state have an action', (tester) async {
    var signedIn = false, retried = false;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            Expanded(
              child: SignInPrompt(
                reason: 'see your friends',
                onSignIn: () => signedIn = true,
              ),
            ),
            Expanded(
              child: ErrorState(
                error: StateError('internal detail'),
                onRetry: () => retried = true,
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Sign in to see your friends.'), findsOneWidget);
    expect(find.textContaining('internal detail'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.tap(find.text('Try again'));
    expect(signedIn && retried, isTrue);
  });

  testWidgets('the app sheet has a title, a close button and its action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              title: 'Add contact',
              body: const Text('Form'),
              action: AppButton(label: 'Save', onPressed: () {}, expand: true),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add contact'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Add contact'), findsNothing);
  });
}
