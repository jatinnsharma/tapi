import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/firebase_status.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/glass.dart';
import 'features/notifications/application/reminder_settings_service.dart';
import 'features/onboarding/application/onboarding_service.dart';
import 'firebase_options.dart';
import 'features/album/presentation/album_auto_sync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (_) {
    // No Firebase on this platform (iOS isn't registered yet; Windows and
    // Linux desktop aren't supported by Firebase) or it failed to start. The
    // rest of the app is local-first and keeps working; only the
    // auth/social screens need Firebase.
    firebaseReady = false;
  }

  // Known before the first screen: a new user goes straight to onboarding.
  final onboarded = await readOnboardingCompleted();

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        onboardingCompletedProvider.overrideWith(
          () => OnboardingNotifier(initial: onboarded),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Loads the reminder switches at start, which re-schedules reminders.
    ref.listen(reminderSettingsProvider, (_, _) {});

    return MaterialApp.router(
      title: 'Tabi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Light until every screen reads its colours from the theme
      // (UI_REDESIGN.md, Phase 3); then switch to ThemeMode.system.
      themeMode: ThemeMode.light,
      // Album photos taken offline upload when the app is opened again.
      builder: (context, child) => AlbumAutoSync(
        child: AppBackground(child: child ?? const SizedBox.shrink()),
      ),
      routerConfig: router,
    );
  }
}

/// The bundled fonts' licences, shown in Settings → Open-source licences.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in [
      ('Inter', 'OFL-Inter.txt'),
      ('Noto Sans Devanagari', 'OFL-NotoSansDevanagari.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}
