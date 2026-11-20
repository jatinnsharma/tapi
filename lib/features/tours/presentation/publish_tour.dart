import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/firebase_status.dart';
import '../../auth/application/auth_service.dart';
import '../../auth/application/display_name_provider.dart';
import '../../explore/data/city_repository.dart';
import '../../explore/domain/city.dart';
import '../../planner/domain/trip_plan.dart';
import '../../planner/presentation/stop_actions.dart';
import '../../tracking/data/adventure_repository.dart';
import '../data/tour_repository.dart';
import '../domain/curated_tour.dart';

/// Publishes day [dayIndex] of [plan] as a community tour, after checking
/// the user is signed in and reached at least [minTourStops] of its stops
/// on counted trips. Explains in a snack bar when it can't.
Future<void> publishDayAsTour(
  BuildContext context,
  WidgetRef ref,
  TripPlan plan,
  int dayIndex,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final user = ref.read(firebaseReadyProvider)
      ? ref.read(authStateProvider).value
      : null;
  if (user == null) {
    say('Sign in to publish tours.');
    if (ref.read(firebaseReadyProvider) && context.mounted) {
      context.push('/login');
    }
    return;
  }

  final visits = await ref
      .read(adventureRepositoryProvider)
      .getCountedPlaceVisits();
  final day = plan.days[dayIndex];
  final verified = verifiedTourStops(day, {
    for (final v in visits) v.placeId,
  }, placeIdOfStop);
  if (verified.length < minTourStops) {
    say(
      'Reach at least $minTourStops stops of Day ${day.dayNumber} on a trip '
      '(with the live photo) to publish it. ${verified.length} so far.',
    );
    return;
  }

  final city = await _cityFor(ref, plan, verified.first);
  if (!context.mounted) return;
  final details = await showDialog<({String title, String description})>(
    context: context,
    builder: (_) => _PublishDialog(
      initialTitle: day.title,
      stopCount: verified.length,
      cityName: city?.name ?? plan.destination,
    ),
  );
  if (details == null) return;

  final tour = CuratedTour(
    id: '',
    creatorUid: user.uid,
    creatorName:
        ref.read(displayNameProvider) ??
        user.email?.split('@').first ??
        'Explorer',
    cityId: city?.id ?? '',
    cityName: city?.name ?? plan.destination,
    title: details.title,
    description: details.description,
    stops: [
      for (final s in verified)
        TourStop(
          name: s.placeName,
          latitude: s.latitude,
          longitude: s.longitude,
          category: s.category,
          tip: switch (s.tip) {
            final tip? when tip.length > maxTourTipLength => tip.substring(
              0,
              maxTourTipLength,
            ),
            final tip => tip,
          },
        ),
    ],
    createdAt: DateTime.now(),
  );
  try {
    await ref.read(tourRepositoryProvider).publish(tour);
    if (tour.cityId.isNotEmpty) ref.invalidate(cityToursProvider(tour.cityId));
    say('Published! It now shows on ${tour.cityName}\'s page.');
  } catch (_) {
    say('Could not publish the tour. Check your connection and try again.');
  }
}

/// The plan's catalog city, else the city nearest the first stop.
Future<City?> _cityFor(WidgetRef ref, TripPlan plan, TripStop first) async {
  final repository = ref.read(cityRepositoryProvider);
  final id = plan.cityId;
  if (id != null) {
    final city = await repository.getCityById(id);
    if (city != null) return city;
  }
  const distance = Distance();
  City? nearest;
  var best = double.infinity;
  for (final city in await repository.getCities()) {
    final m = distance(first.coordinates, city.location);
    if (m < best) {
      best = m;
      nearest = city;
    }
  }
  return best <= 50000 ? nearest : null;
}

class _PublishDialog extends StatefulWidget {
  const _PublishDialog({
    required this.initialTitle,
    required this.stopCount,
    required this.cityName,
  });

  final String initialTitle;
  final int stopCount;
  final String cityName;

  @override
  State<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<_PublishDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initialTitle);
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publish as a community tour'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.stopCount} stops you reached in ${widget.cityName}. '
              'Anyone signed in can see it, with your public name.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              maxLength: maxTourTitleLength,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Give it a title' : null,
            ),
            TextFormField(
              controller: _description,
              maxLength: maxTourDescriptionLength,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What makes it special? (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((
              title: _title.text.trim(),
              description: _description.text.trim(),
            ));
          },
          child: const Text('Publish'),
        ),
      ],
    );
  }
}
