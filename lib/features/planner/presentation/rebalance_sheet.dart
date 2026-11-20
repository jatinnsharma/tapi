import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/day_rebalance.dart';
import '../domain/opening_hours.dart';
import '../domain/trip_plan.dart';
import 'stop_actions.dart';
import 'stop_number_badge.dart';

/// "Adjust my day": asks why, shows what the rest of [plan]'s day
/// [dayIndex] would become, and returns the changed plan when the user
/// applies it (null if they don't). Opens at once; where you are is found
/// inside the sheet.
Future<TripPlan?> showRebalanceSheet(
  BuildContext context,
  WidgetRef ref,
  TripPlan plan,
  int dayIndex,
) {
  return showModalBottomSheet<TripPlan>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        _RebalanceSheet(plan: plan, dayIndex: dayIndex, now: DateTime.now()),
  );
}

class _RebalanceSheet extends ConsumerStatefulWidget {
  const _RebalanceSheet({
    required this.plan,
    required this.dayIndex,
    required this.now,
  });

  final TripPlan plan;
  final int dayIndex;
  final DateTime now;

  @override
  ConsumerState<_RebalanceSheet> createState() => _RebalanceSheetState();
}

class _RebalanceSheetState extends ConsumerState<_RebalanceSheet> {
  RebalanceReason? _reason;
  final _closed = <String>{};

  /// Where the user is, or null when unknown (the first stop is used).
  LatLng? _from;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    LatLng? here;
    try {
      here = await ref
          .read(locationServiceProvider)
          .getCurrentLocation(acceptRecent: true);
    } catch (_) {
      // Unknown: plan from the first stop.
    }
    if (!mounted) return;
    setState(() {
      _from = here;
      _locating = false;
    });
  }

  TripDayPlan get _day => widget.plan.days[widget.dayIndex];
  List<TripStop> get _pending =>
      _day.stops.where((s) => !s.isCompleted).toList();

  RebalanceResult? get _result {
    final reason = _reason;
    if (reason == null || _locating) return null;
    if (reason == RebalanceReason.placeClosed && _closed.isEmpty) return null;
    return rebalanceDay(
      pending: _pending,
      now: widget.now,
      reason: reason,
      from: _from,
      closedStopIds: reason == RebalanceReason.placeClosed ? _closed : const {},
      isOpenAt: (stop, at) =>
          OpeningHours.parse(stop.openingHours)?.isOpenAt(at),
      categoryOf: (stop) => categoryOfStop(stop.category),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final time = DateFormat.jm();
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodyMedium?.copyWith(color: colors.textSecondary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Adjust Day ${_day.dayNumber}', style: text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  _locating
                      ? 'Finding where you are…'
                      : _from == null
                      ? 'Re-plans the stops you have left. Location is off, '
                            'so it starts from your next stop.'
                      : 'Re-plans the stops you have left, from where you '
                            'are now.',
                  style: muted,
                ),
                const SizedBox(height: 8),
                RadioGroup<RebalanceReason>(
                  groupValue: _reason,
                  onChanged: (r) => setState(() => _reason = r),
                  child: Column(
                    children: [
                      for (final reason in RebalanceReason.values)
                        RadioListTile<RebalanceReason>(
                          contentPadding: EdgeInsets.zero,
                          value: reason,
                          title: Text(reason.label),
                          subtitle: Text(reason.description),
                        ),
                    ],
                  ),
                ),
                if (_reason == RebalanceReason.placeClosed) ...[
                  const SizedBox(height: 8),
                  Text('Which place is closed?', style: text.titleSmall),
                  for (final stop in _pending)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _closed.contains(stop.id),
                      title: Text(stop.placeName),
                      onChanged: (on) => setState(
                        () => on == true
                            ? _closed.add(stop.id)
                            : _closed.remove(stop.id),
                      ),
                    ),
                ],
                if (_reason != null && _locating) ...[
                  const Divider(height: 28),
                  const LinearProgressIndicator(),
                ],
                if (result != null) ...[
                  const Divider(height: 28),
                  Text(
                    result.kept.isEmpty
                        ? 'Nothing more fits today.'
                        : 'New plan: ${result.kept.length} '
                              '${result.kept.length == 1 ? 'stop' : 'stops'}, '
                              'done by about ${time.format(result.finishAt)}',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  for (final (i, stop) in result.kept.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: StopNumberBadge(
                        number: i + 1,
                        done: false,
                        size: 28,
                      ),
                      title: Text(stop.placeName),
                      subtitle: Text('${stop.durationMinutes} min visit'),
                    ),
                  for (final drop in result.dropped)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.remove_circle_outline,
                        color: colors.danger,
                        semanticLabel: 'Dropped',
                      ),
                      title: Text(
                        drop.stop.placeName,
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(drop.explanation),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (result != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: AppButton(
                label: 'Apply new plan',
                expand: true,
                onPressed: () {
                  final days = [...widget.plan.days];
                  days[widget.dayIndex] = applyRebalance(_day, result);
                  Navigator.of(context).pop(widget.plan.copyWith(days: days));
                },
              ),
            ),
          ),
      ],
    );
  }
}
