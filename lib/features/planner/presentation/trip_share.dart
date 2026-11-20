import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/ui/share_card.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/trip_extras.dart';
import '../domain/trip_plan.dart';

/// The itinerary as plain text, for messaging apps.
String tripAsText(TripPlan plan) {
  final buffer = StringBuffer()
    ..writeln('🗺️ ${plan.title}')
    ..writeln('📍 ${plan.destination} · ${plan.daysCount} days');
  if (plan.startDate != null) {
    buffer.writeln('📅 ${_dateRange(plan)}');
  }
  if (plan.overview != null) buffer.writeln('\n${plan.overview}');
  buffer.writeln();

  for (final day in plan.days) {
    buffer.writeln('--- Day ${day.dayNumber}: ${day.title} ---');
    for (final stop in day.stops) {
      buffer.writeln(
        '• [${stop.timeSlot}] ${stop.placeName} (${stop.durationMinutes} min)',
      );
      if (stop.tip != null) buffer.writeln('  Tip: ${stop.tip}');
    }
    if (day.foodSuggestions.isNotEmpty) {
      buffer.writeln('🍽️ Eats: ${day.foodSuggestions.join(', ')}');
    }
    buffer.writeln();
  }
  final budget = estimateBudget(plan);
  buffer.writeln(
    '💰 Rough budget: ${formatRupees(budget.low)} – ${formatRupees(budget.high)} '
    'for ${budget.travellers} traveller${budget.travellers == 1 ? '' : 's'}',
  );
  buffer.writeln('\nPlanned with Tabi');
  return buffer.toString();
}

String _dateRange(TripPlan plan) {
  final fmt = DateFormat('d MMM yyyy');
  final start = plan.startDate!;
  final end = start.add(Duration(days: plan.daysCount - 1));
  return '${fmt.format(start)} – ${fmt.format(end)}';
}

Future<void> shareTripAsText(TripPlan plan) {
  return SharePlus.instance.share(
    ShareParams(text: tripAsText(plan), subject: plan.title),
  );
}

/// Shares the itinerary as an image (or its text), from the shared share
/// sheet.
Future<void> showTripImageShare(BuildContext context, TripPlan plan) {
  return showShareCardSheet(
    context,
    title: 'Share trip',
    card: _TripShareCard(plan: plan),
    fileName: 'trip-${plan.id}.png',
    shareText: '${plan.title} · planned with Tabi',
    copyText: tripAsText(plan),
  );
}

/// Days drawn on the image; a longer trip says "+N more days".
const shareCardMaxDays = 3;

/// The itinerary laid out as one shareable card.
class _TripShareCard extends StatelessWidget {
  const _TripShareCard({required this.plan});

  final TripPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cream,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.heroGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                // Icons, not emoji: emoji look different on every phone.
                _IconLine(
                  icon: Icons.place_outlined,
                  text:
                      '${plan.destination} · ${plan.daysCount} days · '
                      '${plan.companion.label}',
                ),
                if (plan.startDate != null)
                  _IconLine(icon: Icons.event_outlined, text: _dateRange(plan)),
              ],
            ),
          ),
          for (final day in plan.days.take(shareCardMaxDays))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Day ${day.dayNumber} · ${day.title}',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.forest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final stop in day.stops)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 78,
                            child: Text(
                              stop.timeSlot,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              stop.placeName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (day.foodSuggestions.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1, right: 6),
                          child: Icon(
                            Icons.restaurant_menu,
                            size: 14,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            day.foodSuggestions.take(3).join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (plan.days.length > shareCardMaxDays)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                '+${plan.days.length - shareCardMaxDays} more '
                '${plan.days.length - shareCardMaxDays == 1 ? 'day' : 'days'}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkMuted,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Planned with Tabi',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A white line with an icon on the card's green header.
class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.white70),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
        ),
      ],
    ),
  );
}
