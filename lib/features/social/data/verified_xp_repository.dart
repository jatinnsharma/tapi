import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final verifiedXpRepositoryProvider = Provider<VerifiedXpRepository>(
  (ref) => VerifiedXpRepository(FirebaseFirestore.instance),
);

/// Totals written only by the `verifyTrip` Cloud Function
/// (`verified_xp/{uid}.totalXp`; the rules let no app write there).
class VerifiedXpRepository {
  VerifiedXpRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _totals =>
      _firestore.collection('verified_xp');

  static int _xpOf(Map<String, dynamic>? data) =>
      (data?['totalXp'] as num?)?.toInt() ?? 0;

  /// The highest verified totals, highest first.
  Future<List<({String uid, int xp})>> top({int limit = 50}) async {
    final snapshot = await _totals
        .orderBy('totalXp', descending: true)
        .limit(limit)
        .get();
    return [for (final d in snapshot.docs) (uid: d.id, xp: _xpOf(d.data()))];
  }

  /// Verified totals for [uids]; anyone without one has 0.
  Future<Map<String, int>> totalsFor(Iterable<String> uids) async {
    final docs = await Future.wait(uids.map((u) => _totals.doc(u).get()));
    return {for (final d in docs) d.id: _xpOf(d.data())};
  }

  Future<int> countWithMoreThan(int xp) async {
    final result = await _totals
        .where('totalXp', isGreaterThan: xp)
        .count()
        .get();
    return result.count ?? 0;
  }
}
