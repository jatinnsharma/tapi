import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/confirm_destructive.dart';
import '../../auth/application/auth_service.dart';
import '../../offline/data/offline_pack_store.dart';
import 'delete_account_dialog.dart';

/// Downloaded offline city maps.
final _offlinePacksProvider = FutureProvider.autoDispose<List<PackInfo>>(
  (ref) => OfflinePackStore.instance.all(),
);

/// `/settings` (You → Settings): account, app preferences, safety, offline
/// maps and privacy in one place.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = firebaseReady ? ref.watch(authStateProvider).value : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          if (firebaseReady)
            AppListGroup(
              title: 'ACCOUNT',
              children: user == null
                  ? [
                      SettingsTile(
                        icon: Icons.login_rounded,
                        title: 'Sign in',
                        subtitle: 'Back up trips and explore with friends',
                        onTap: () => context.push('/login'),
                      ),
                    ]
                  : [
                      AppListTile(
                        leading: const Icon(Icons.person_outline),
                        title: user.email ?? 'Signed in',
                        subtitle: 'Signed in',
                      ),
                      SettingsTile(
                        icon: Icons.logout_rounded,
                        title: 'Sign out',
                        onTap: () async {
                          final ok = await confirmDestructive(
                            context,
                            title: 'Sign out?',
                            message:
                                'Your trips and memories stay on this phone.',
                            confirmLabel: 'Sign out',
                          );
                          if (ok) await ref.read(authServiceProvider).signOut();
                        },
                      ),
                      SettingsTile(
                        icon: Icons.delete_forever_outlined,
                        title: 'Delete account',
                        subtitle: 'Removes your profile, friends and posts',
                        onTap: () => showDeleteAccountDialog(context, user.uid),
                      ),
                    ],
            ),
          AppListGroup(
            title: 'APP',
            children: [
              SettingsTile(
                icon: Icons.tune_rounded,
                title: 'Preferences & reminders',
                subtitle: 'Interests, pace, reminders, battery saving',
                onTap: () => context.push('/preferences'),
              ),
              SettingsTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Safety & SOS',
                subtitle: 'Emergency contacts and helplines',
                onTap: () => context.push('/safety'),
              ),
              SettingsTile(
                icon: Icons.bookmark_outline_rounded,
                title: 'Wishlist',
                onTap: () => context.push('/wishlist'),
              ),
            ],
          ),
          if (OfflinePackStore.instance.available) const _OfflineMapsGroup(),
          if (user != null)
            AppListGroup(
              title: 'PRIVACY',
              children: [
                SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Privacy',
                  subtitle: 'Who sees your map, blocked and muted people',
                  onTap: () => context.push('/settings/privacy'),
                ),
              ],
            ),
          AppListGroup(
            title: 'ABOUT',
            children: [
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Open-source licences',
                onTap: () =>
                    showLicensePage(context: context, applicationName: 'Tabi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineMapsGroup extends ConsumerWidget {
  const _OfflineMapsGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(_offlinePacksProvider).value ?? const [];
    return AppListGroup(
      title: 'OFFLINE MAPS',
      children: packs.isEmpty
          ? [
              const AppListTile(
                leading: Icon(Icons.download_for_offline_outlined),
                title: 'No offline maps yet',
                subtitle: "Download one from a city's page",
              ),
            ]
          : [
              for (final pack in packs)
                AppListTile(
                  leading: const Icon(Icons.offline_pin_outlined),
                  title: pack.cityName,
                  subtitle:
                      '${(pack.bytes / (1024 * 1024)).ceil()} MB'
                      '${pack.complete ? '' : ' · partly downloaded'}',
                  trailing: AppIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete ${pack.cityName} offline map',
                    onPressed: () async {
                      final ok = await confirmDestructive(
                        context,
                        title: 'Delete the ${pack.cityName} offline map?',
                        message: 'You can download it again later.',
                        confirmLabel: 'Delete',
                      );
                      if (!ok) return;
                      await OfflinePackStore.instance.delete(pack.cityId);
                      ref.invalidate(_offlinePacksProvider);
                    },
                  ),
                ),
            ],
    );
  }
}
