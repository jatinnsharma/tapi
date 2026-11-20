import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../social/application/friends_service.dart';
import '../../social/data/social_repository.dart';
import '../../social/domain/explorer_profile.dart';
import '../../weather/data/weather_repository.dart';
import '../../weather/domain/weather_model.dart';
import '../data/saved_trips_repository.dart';
import '../domain/trip_extras.dart';
import '../domain/trip_plan.dart';
import '../../../core/theme/app_components.dart';

import 'package:go_router/go_router.dart';

typedef _ForecastKey = ({double lat, double lng, DateTime start, int days});

final _tripForecastProvider = FutureProvider.autoDispose
    .family<List<DailyForecast>?, _ForecastKey>((ref, key) {
      return ref
          .read(weatherRepositoryProvider)
          .getDailyForecast(key.lat, key.lng, start: key.start, days: key.days);
    });

/// Profiles of a shared trip's members, keyed by their uids joined with ','.
final _tripMembersProvider = FutureProvider.autoDispose
    .family<List<ExplorerProfile>, String>((ref, uidsKey) async {
      final social = ref.read(socialRepositoryProvider);
      final profiles = await Future.wait(
        uidsKey.split(',').where((u) => u.isNotEmpty).map((uid) async {
          try {
            return await social.getProfile(uid);
          } catch (_) {
            return null;
          }
        }),
      );
      return [for (final p in profiles) ?p];
    });

/// The "Essentials" tab of an itinerary: dates and forecast, who's going,
/// budget, packing checklist and booking links.
class TripEssentialsView extends ConsumerWidget {
  const TripEssentialsView({
    super.key,
    required this.plan,
    required this.onEdit,
    required this.onStored,
  });

  final TripPlan plan;

  /// A change the parent should save (it stamps and persists it).
  final ValueChanged<TripPlan> onEdit;

  /// A change that's already been saved (e.g. sharing), to show.
  final ValueChanged<TripPlan> onStored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _DatesCard(plan: plan, onEdit: onEdit),
        const SizedBox(height: 14),
        _TravellersCard(plan: plan, onStored: onStored),
        const SizedBox(height: 14),
        _BudgetCard(plan: plan, onEdit: onEdit),
        const SizedBox(height: 14),
        _PackingCard(plan: plan, onEdit: onEdit),
        const SizedBox(height: 14),
        _BookingCard(plan: plan),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.icon, this.title, {this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

const _mutedStyle = TextStyle(color: AppTheme.inkMuted, height: 1.35);

// ---------------------------------------------------------------------------
// Dates & weather
// ---------------------------------------------------------------------------

class _DatesCard extends ConsumerWidget {
  const _DatesCard({required this.plan, required this.onEdit});

  final TripPlan plan;
  final ValueChanged<TripPlan> onEdit;

  Future<void> _pickDate(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: plan.startDate != null && !plan.startDate!.isBefore(today)
          ? plan.startDate!
          : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      helpText: 'First day of the trip',
    );
    if (picked != null) onEdit(plan.copyWith(startDate: picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = plan.startDate;
    final fmt = DateFormat('EEE, d MMM');
    final firstStop = plan.days
        .expand((d) => d.stops)
        .cast<TripStop?>()
        .firstWhere((_) => true, orElse: () => null);

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            Icons.event_outlined,
            'Dates & weather',
            trailing: start == null
                ? null
                : AppButton.tertiary(
                    label: 'Change',
                    onPressed: () => _pickDate(context),
                  ),
          ),
          const SizedBox(height: 6),
          // Dates unlock the forecast and the season's packing list, so
          // they're the first thing to ask for.
          if (start == null) ...[
            const Text(
              'Add your travel dates to see the forecast and a packing list '
              'for the season.',
              style: _mutedStyle,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Add dates',
              icon: Icons.event_outlined,
              onPressed: () => _pickDate(context),
            ),
          ] else ...[
            Text(
              '${fmt.format(start)} – ${fmt.format(start.add(Duration(days: plan.daysCount - 1)))}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(seasonNote(start), style: _mutedStyle),
            if (firstStop != null) ...[
              const SizedBox(height: 10),
              _Forecast(
                key: ValueKey(start),
                forecastKey: (
                  lat: firstStop.latitude,
                  lng: firstStop.longitude,
                  start: start,
                  days: plan.daysCount,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Forecast extends ConsumerWidget {
  const _Forecast({super.key, required this.forecastKey});

  final _ForecastKey forecastKey;

  IconData _icon(int code) {
    if (code == 0) return Icons.wb_sunny_outlined;
    if (code <= 3) return Icons.cloud_queue;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 95) return Icons.thunderstorm_outlined;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    return Icons.water_drop_outlined;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(_tripForecastProvider(forecastKey));
    return forecast.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, _) =>
          const Text('Forecast unavailable right now.', style: _mutedStyle),
      data: (days) {
        if (days == null || days.isEmpty) {
          return const Text(
            'The forecast opens up about 16 days before the trip.',
            style: _mutedStyle,
          );
        }
        final text = Theme.of(context).textTheme;
        final colors = AppColors.of(context);
        // Tiles grow with the text size instead of a fixed height.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, d) in days.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 84),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('EEE d').format(d.date),
                          style: text.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Icon(
                          _icon(d.weatherCode),
                          color: Theme.of(context).colorScheme.primary,
                          semanticLabel: d.conditionDescription,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${d.maxTemp.round()}° / ${d.minTemp.round()}°',
                          style: text.labelLarge,
                        ),
                        if (d.rainChance != null)
                          Text(
                            '${d.rainChance}% rain',
                            style: text.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Travelling together
// ---------------------------------------------------------------------------

class _TravellersCard extends ConsumerWidget {
  const _TravellersCard({required this.plan, required this.onStored});

  final TripPlan plan;
  final ValueChanged<TripPlan> onStored;

  Future<void> _share(BuildContext context, WidgetRef ref, String myUid) async {
    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FriendPicker(
        initial: plan.memberUids.where((u) => u != myUid).toSet(),
      ),
    );
    if (chosen == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stored = await ref
          .read(savedTripsListProvider.notifier)
          .setMembers(plan, chosen);
      onStored(stored);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            chosen.isEmpty
                ? 'Trip is now just yours'
                : 'Shared with ${chosen.length} friend${chosen.length == 1 ? '' : 's'}. You can both edit it.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Could not share the trip. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(tripSyncUidProvider);
    final isOwner = myUid != null && plan.isOwnedBy(myUid);

    final Widget body;
    if (myUid == null) {
      body = const Text(
        'Sign in to back up this trip and plan it together with a friend.',
        style: _mutedStyle,
      );
    } else if (!plan.isShared) {
      body = const Text(
        'Share this trip with the friends you are travelling with. Everyone can edit stops, dates and the packing list.',
        style: _mutedStyle,
      );
    } else {
      final members = ref.watch(
        _tripMembersProvider(plan.memberUids.join(',')),
      );
      body = members.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (_, _) =>
            Text('${plan.memberUids.length} travellers', style: _mutedStyle),
        data: (profiles) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in profiles)
              Chip(
                avatar: AppAvatar(
                  initial: p.displayName.isEmpty
                      ? '?'
                      : p.displayName[0].toUpperCase(),
                  size: 24,
                ),
                label: Text(
                  '${p.uid == myUid ? 'You' : p.displayName}'
                  '${p.uid == plan.ownerUid ? ' · planner' : ''}',
                ),
              ),
          ],
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            Icons.group_outlined,
            'Travelling together',
            trailing: isOwner
                ? TextButton.icon(
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(plan.isShared ? 'Edit' : 'Share'),
                    onPressed: () => _share(context, ref, myUid),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}

class _FriendPicker extends ConsumerStatefulWidget {
  const _FriendPicker({required this.initial});

  final Set<String> initial;

  @override
  ConsumerState<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends ConsumerState<_FriendPicker> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(acceptedFriendsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Who is coming along?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Friends you pick can see and edit this trip.',
              style: _mutedStyle,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: friends.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Could not load your friends.'),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No friends yet. Add your travel buddy first, '
                              'then share the trip.',
                              style: _mutedStyle,
                            ),
                            const SizedBox(height: 8),
                            AppButton.secondary(
                              label: 'Find friends',
                              icon: Icons.person_add_alt_1_outlined,
                              onPressed: () {
                                Navigator.of(context).pop();
                                context.go('/social');
                              },
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final f in list)
                            CheckboxListTile(
                              value: _selected.contains(f.uid),
                              onChanged: (v) => setState(() {
                                v == true
                                    ? _selected.add(f.uid)
                                    : _selected.remove(f.uid);
                              }),
                              secondary: AppAvatar(
                                initial: f.displayName.isEmpty
                                    ? '?'
                                    : f.displayName[0].toUpperCase(),
                                size: 36,
                              ),
                              title: Text(f.displayName),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Save',
              expand: true,
              onPressed: () => Navigator.of(context).pop(_selected.toList()),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.plan, required this.onEdit});

  final TripPlan plan;
  final ValueChanged<TripPlan> onEdit;

  @override
  Widget build(BuildContext context) {
    final estimate = estimateBudget(plan);
    final people = plan.travellerCount;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            Icons.account_balance_wallet_outlined,
            'Budget estimate · ${plan.budget.label}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Travellers', style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Fewer travellers',
                onPressed: people > 1
                    ? () => onEdit(plan.copyWith(travellers: people - 1))
                    : null,
              ),
              Text('$people', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'More travellers',
                onPressed: people < 20
                    ? () => onEdit(plan.copyWith(travellers: people + 1))
                    : null,
              ),
            ],
          ),
          for (final line in estimate.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(line.icon, size: 18, color: AppTheme.inkMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${formatRupees(line.low)} – ${formatRupees(line.high)}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '${formatRupees(estimate.low)} – ${formatRupees(estimate.high)}',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          if (people > 1)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${formatRupees(estimate.perPersonLow)} – ${formatRupees(estimate.perPersonHigh)} per person',
                style: _mutedStyle,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Rough estimate for ${estimate.nights} night${estimate.nights == 1 ? '' : 's'} at typical prices. '
            'Getting to ${plan.destination} is not included.',
            style: _mutedStyle,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Packing
// ---------------------------------------------------------------------------

class _PackingCard extends StatelessWidget {
  const _PackingCard({required this.plan, required this.onEdit});

  final TripPlan plan;
  final ValueChanged<TripPlan> onEdit;

  void _toggle(String item, bool checked) {
    final next = {...plan.packingChecked};
    checked ? next.add(item) : next.remove(item);
    onEdit(plan.copyWith(packingChecked: next.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final sections = packingListFor(plan);
    final all = sections.expand((s) => s.items).toList();
    final done = all.where(plan.packingChecked.contains).length;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            Icons.luggage_outlined,
            'Packing checklist',
            trailing: Text('$done / ${all.length}', style: _mutedStyle),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: all.isEmpty ? 0 : done / all.length,
              minHeight: 6,
              backgroundColor: AppTheme.sage.withValues(alpha: 0.4),
              color: AppTheme.primary,
            ),
          ),
          for (final section in sections)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: Icon(section.icon, color: AppTheme.inkMuted, size: 20),
                title: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  '${section.items.where(plan.packingChecked.contains).length} of ${section.items.length} packed',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.of(context).textSecondary),
                ),
                children: [
                  for (final item in section.items)
                    // Full 48 px rows: easy to tick while packing.
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: plan.packingChecked.contains(item),
                      onChanged: (v) => _toggle(item, v ?? false),
                      title: Text(item),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Booking links
// ---------------------------------------------------------------------------

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.plan});

  final TripPlan plan;

  Future<void> _open(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            Icons.confirmation_number_outlined,
            'Book stays & travel',
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Opens public booking sites. Nothing is booked from the app.',
              style: _mutedStyle,
            ),
          ),
          for (final link in bookingLinksFor(plan))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(link.icon, color: AppTheme.primary),
              title: Text(
                link.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                link.subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(context, link.url),
            ),
        ],
      ),
    );
  }
}
