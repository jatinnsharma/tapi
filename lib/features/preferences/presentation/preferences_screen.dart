import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/battery_settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../application/preferences_service.dart';
import '../domain/user_preferences.dart';
import '../../notifications/application/reminder_settings_service.dart';

class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesAsync = ref.watch(userPreferencesProvider);
    final notifier = ref.read(userPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exploration Preferences'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () async {
                await notifier.save();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Preferences saved.')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: preferencesAsync.when(
        loading: () => const _PreferencesSkeleton(),
        error: (error, stack) => ListView(
          padding: AppSpacing.page,
          children: [
            EmptyStateCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load preferences',
              message: '$error',
            ),
          ],
        ),
        data: (preferences) {
          return ListView(
            padding: AppSpacing.page,
            children: [
              FadeSlideIn(
                child: _PreferenceSection(
                  title: 'Interests',
                  children: [
                    for (final interest in interestOptions)
                      CategoryChip(
                        label: interest,
                        selected: preferences.interests.contains(interest),
                        onTap: () => notifier.toggleInterest(interest),
                      ),
                  ],
                ),
              ),
              _buildSingleChoiceSection(
                title: 'Duration',
                delay: 60,
                options: durationOptions,
                selected: preferences.duration,
                onSelected: notifier.setDuration,
              ),
              _buildSingleChoiceSection(
                title: 'Difficulty',
                delay: 120,
                options: difficultyOptions,
                selected: preferences.difficulty,
                onSelected: notifier.setDifficulty,
              ),
              _buildSingleChoiceSection(
                title: 'Social Preference',
                delay: 180,
                options: socialPreferenceOptions,
                selected: preferences.socialPreference,
                onSelected: notifier.setSocialPreference,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: FadeSlideIn(
                  delay: Duration(milliseconds: 240),
                  child: _BatterySavingCard(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: FadeSlideIn(
                  delay: Duration(milliseconds: 280),
                  child: _RemindersCard(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSingleChoiceSection({
    required String title,
    required int delay,
    required List<String> options,
    required String? selected,
    required void Function(String?) onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: FadeSlideIn(
        delay: Duration(milliseconds: delay),
        child: _PreferenceSection(
          title: title,
          children: [
            for (final option in options)
              CategoryChip(
                label: option,
                selected: selected == option,
                onTap: () => onSelected(selected == option ? null : option),
              ),
          ],
        ),
      ),
    );
  }
}

/// Battery saving for trips: lower GPS accuracy and fewer updates. Saved as
/// soon as it's switched (it isn't part of the Save button's preferences)
/// and applied the next time a trip starts or resumes.
class _BatterySavingCard extends ConsumerWidget {
  const _BatterySavingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(batterySavingModeProvider).value ?? false;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: SwitchListTile(
        activeThumbColor: AppTheme.forest,
        title: const Text(
          'Battery saving on trips',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
        subtitle: const Text(
          'Uses less GPS: longer trips last longer, but directions update a '
          'little less often.',
          style: TextStyle(color: AppTheme.inkMuted),
        ),
        value: enabled,
        onChanged: (value) =>
            ref.read(batterySavingModeProvider.notifier).setEnabled(value),
      ),
    );
  }
}

class _RemindersCard extends ConsumerWidget {
  const _RemindersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    final notifier = ref.read(reminderSettingsProvider.notifier);

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'Reminders & Notifications',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppTheme.ink,
              ),
            ),
          ),
          SwitchListTile(
            activeThumbColor: AppTheme.forest,
            title: const Text(
              'Daily streak alerts',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            subtitle: const Text(
              'Get a gentle reminder in the evening if your streak is at risk.',
              style: TextStyle(color: AppTheme.inkMuted),
            ),
            value: settings.streakReminders,
            onChanged: (val) => notifier.setStreakReminders(val),
          ),
          SwitchListTile(
            activeThumbColor: AppTheme.forest,
            title: const Text(
              'Daily challenge updates',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            subtitle: const Text(
              'Notify when each day\'s new exploration challenge becomes available.',
              style: TextStyle(color: AppTheme.inkMuted),
            ),
            value: settings.challengeReminders,
            onChanged: (val) => notifier.setChallengeReminders(val),
          ),
          SwitchListTile(
            activeThumbColor: AppTheme.forest,
            title: const Text(
              'Social & friend alerts',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            subtitle: const Text(
              'Notify when friends complete adventures or challenge you.',
              style: TextStyle(color: AppTheme.inkMuted),
            ),
            value: settings.socialReminders,
            onChanged: (val) => notifier.setSocialReminders(val),
          ),
        ],
      ),
    );
  }
}

/// Titled soft card holding a wrap of pill chips.
class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 12, children: children),
        ],
      ),
    );
  }
}

class _PreferencesSkeleton extends StatelessWidget {
  const _PreferencesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: AppSpacing.page,
      child: Shimmer(
        child: Column(
          children: [
            SkeletonBox(height: 150, radius: 24),
            SizedBox(height: 14),
            SkeletonBox(height: 100, radius: 24),
            SizedBox(height: 14),
            SkeletonBox(height: 100, radius: 24),
          ],
        ),
      ),
    );
  }
}
