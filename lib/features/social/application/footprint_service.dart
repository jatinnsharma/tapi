import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/utils/polyline_codec.dart';
import '../../auth/application/auth_service.dart';
import '../../locations/data/location_repository.dart';
import '../../tracking/data/adventure_repository.dart';
import '../data/social_repository.dart';
import '../domain/footprint.dart';

/// Keeps the shareable copy of the user's exploration footprint in Firestore
/// in step with the local SQLite history, according to their chosen
/// [FootprintVisibility]. Private means nothing is uploaded: the doc then
/// only records the choice, with empty route and place lists.
class FootprintService {
  FootprintService(this._social, this._adventures, this._locations);

  final SocialRepository _social;
  final AdventureRepository _adventures;
  final LocationRepository _locations;

  /// Firestore documents are capped at 1 MiB, so the shared copy is bounded:
  /// the most recent routes only, each thinned to a few hundred points, and
  /// a limited number of places.
  static const _maxRoutes = 60;
  static const _maxPointsPerRoute = 200;
  static const _maxPlaces = 300;

  Future<Footprint?> getMine(String uid) => _social.getFootprint(uid);

  /// Applies a new visibility and uploads (or clears) the footprint to match.
  Future<void> setVisibility({
    required String uid,
    required String fallbackName,
    required FootprintVisibility visibility,
  }) {
    return _sync(uid, fallbackName, visibility);
  }

  /// Refreshes the shared copy after new activity. Does nothing unless the
  /// user has opted in, so a private user never creates a footprint doc.
  Future<void> refreshIfShared({
    required String uid,
    required String fallbackName,
  }) async {
    final current = await _social.getFootprint(uid);
    if (current == null || current.visibility == FootprintVisibility.private) {
      return;
    }
    await _sync(uid, fallbackName, current.visibility);
  }

  Future<void> _sync(
    String uid,
    String fallbackName,
    FootprintVisibility visibility,
  ) async {
    final profile = await _social.getProfile(uid);
    final name = profile?.displayName ?? fallbackName;

    if (visibility == FootprintVisibility.private) {
      await _social.saveFootprint(
        Footprint(
          uid: uid,
          displayName: name,
          visibility: visibility,
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }

    final paths = await _adventures.getAllCompletedRoutePaths();
    final recent = paths.length > _maxRoutes
        ? paths.sublist(paths.length - _maxRoutes)
        : paths;
    final routes = <String>[
      for (final path in recent)
        if (path.length >= 2)
          PolylineCodec.encode(
            _thin([for (final p in path) LatLng(p.latitude, p.longitude)]),
          ),
    ];

    final visited = (await _locations.getAll())
        .where((l) => l.isDiscovered)
        .take(_maxPlaces);

    await _social.saveFootprint(
      Footprint(
        uid: uid,
        displayName: name,
        visibility: visibility,
        updatedAt: DateTime.now(),
        routes: routes,
        places: [
          for (final location in visited)
            FootprintPlace(
              id: location.id,
              name: location.name,
              latitude: location.latitude,
              longitude: location.longitude,
              category: location.category.name,
            ),
        ],
      ),
    );
  }

  /// Keeps at most [_maxPointsPerRoute] evenly spaced points, always
  /// including the first and last.
  List<LatLng> _thin(List<LatLng> points) {
    if (points.length <= _maxPointsPerRoute) return points;
    final step = (points.length - 1) / (_maxPointsPerRoute - 1);
    return [
      for (var i = 0; i < _maxPointsPerRoute; i++) points[(i * step).round()],
    ];
  }
}

final footprintServiceProvider = Provider<FootprintService>((ref) {
  return FootprintService(
    ref.watch(socialRepositoryProvider),
    ref.watch(adventureRepositoryProvider),
    ref.watch(locationRepositoryProvider),
  );
});

/// The signed-in user's own footprint doc; null when they've never chosen a
/// visibility (treated as private).
final myFootprintProvider = FutureProvider.autoDispose<Footprint?>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return null;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.watch(footprintServiceProvider).getMine(user.uid);
});

/// A footprint someone else shared with the signed-in user.
enum FootprintAccess { available, notShared }

class FootprintResult {
  const FootprintResult.available(this.footprint)
    : access = FootprintAccess.available;
  const FootprintResult.notShared()
    : access = FootprintAccess.notShared,
      footprint = null;

  final FootprintAccess access;
  final Footprint? footprint;
}

/// Loads another explorer's footprint. A missing doc or a permission-denied
/// from Firestore both mean "not shared with you": the rule hides everything
/// the owner's visibility doesn't allow, so the app can't tell (or reveal)
/// the difference between private and never-set.
final footprintOfProvider = FutureProvider.autoDispose
    .family<FootprintResult, String>((ref, uid) async {
      try {
        final footprint = await ref
            .watch(socialRepositoryProvider)
            .getFootprint(uid);
        if (footprint == null ||
            footprint.visibility == FootprintVisibility.private) {
          return const FootprintResult.notShared();
        }
        return FootprintResult.available(footprint);
      } catch (_) {
        return const FootprintResult.notShared();
      }
    });
