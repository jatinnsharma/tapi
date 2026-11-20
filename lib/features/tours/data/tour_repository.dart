import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/curated_tour.dart';

final tourRepositoryProvider = Provider<TourRepository>((ref) {
  return TourRepository(FirebaseFirestore.instance);
});

/// Most tours listed for one city.
const maxToursPerCity = 30;

/// Most ratings read for one tour.
const maxRatingsRead = 100;

/// Community tours in Firestore: `curated_tours/{id}`, with one rating per
/// person in `curated_tours/{id}/ratings/{uid}`. See `firestore.rules`.
class TourRepository {
  TourRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tours =>
      _firestore.collection('curated_tours');

  /// Publishes [tour] and returns its new id.
  Future<String> publish(CuratedTour tour) async {
    final doc = await _tours.add({
      ...tour.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Tours of a city, newest first. Sorted here, not in the query, so no
  /// composite index is needed.
  Future<List<CuratedTour>> toursForCity(String cityId) async {
    final snapshot = await _tours
        .where('cityId', isEqualTo: cityId)
        .limit(maxToursPerCity)
        .get();
    final tours = [for (final doc in snapshot.docs) _fromDoc(doc)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tours;
  }

  Future<void> delete(String tourId) => _tours.doc(tourId).delete();

  Future<List<TourRating>> ratings(String tourId) async {
    final snapshot = await _tours
        .doc(tourId)
        .collection('ratings')
        .limit(maxRatingsRead)
        .get();
    return [
      for (final doc in snapshot.docs) TourRating.fromMap(doc.id, doc.data()),
    ];
  }

  /// Sets (or replaces) the signed-in user's rating.
  Future<void> rate(String tourId, TourRating rating) => _tours
      .doc(tourId)
      .collection('ratings')
      .doc(rating.uid)
      .set(rating.toMap());

  static CuratedTour _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = {...?doc.data()};
    final created = data['createdAt'];
    data['createdAt'] = created is Timestamp ? created.toDate() : null;
    return CuratedTour.fromMap(doc.id, data);
  }
}

/// Tours for a catalog city id.
final cityToursProvider = FutureProvider.autoDispose
    .family<List<CuratedTour>, String>(
      (ref, cityId) => ref.watch(tourRepositoryProvider).toursForCity(cityId),
    );

/// Ratings of a tour.
final tourRatingsProvider = FutureProvider.autoDispose
    .family<List<TourRating>, String>(
      (ref, tourId) => ref.watch(tourRepositoryProvider).ratings(tourId),
    );
