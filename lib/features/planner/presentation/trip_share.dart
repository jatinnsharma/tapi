import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

/// Opens a preview of the itinerary card with a button that shares it as an
/// image.
Future<void> showTripImageShare(BuildContext context, TripPlan plan) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _TripImageShareScreen(plan: plan)),
  );
}

class _TripImageShareScreen extends StatefulWidget {
  const _TripImageShareScreen({required this.plan});

  final TripPlan plan;

  @override
  State<_TripImageShareScreen> createState() => _TripImageShareScreenState();
}

class _TripImageShareScreenState extends State<_TripImageShareScreen> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not render the image.');

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'trip-${widget.plan.id}.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.plan.title} · planned with Tabi',
          subject: widget.plan.title,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create the image. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share as image')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: RepaintBoundary(
          key: _boundaryKey,
          child: _TripShareCard(plan: widget.plan),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sharing ? null : _share,
        backgroundColor: AppTheme.forest,
        foregroundColor: Colors.white,
        icon: _sharing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.ios_share),
        label: const Text('Share image'),
      ),
    );
  }
}

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
                Text(
                  '📍 ${plan.destination} · ${plan.daysCount} days · ${plan.companion.label}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
                if (plan.startDate != null)
                  Text(
                    '📅 ${_dateRange(plan)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                    ),
                  ),
              ],
            ),
          ),
          for (final day in plan.days)
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
                    Text(
                      '🍽️ ${day.foodSuggestions.take(3).join(' · ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                ],
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
