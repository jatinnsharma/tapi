import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../explore/data/city_repository.dart';
import '../../tracking/data/adventure_repository.dart';
import '../domain/passport_stamp.dart';

/// The user's passport stamps, first earned first. Rebuilt whenever a trip
/// reaches a place (the tracking service refreshes [visitedPlaceIdsProvider]).
final passportStampsProvider = FutureProvider<List<PassportStamp>>((ref) async {
  ref.watch(visitedPlaceIdsProvider);
  final visits = await ref
      .watch(adventureRepositoryProvider)
      .getCountedPlaceVisits();
  final cities = await ref.watch(cityRepositoryProvider).getCities();
  return buildStamps(visits, cities);
});
