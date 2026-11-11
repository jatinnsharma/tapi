import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the server decided about a trip.
class VerifiedTrip {
  const VerifiedTrip({
    required this.ok,
    required this.totalXp,
    required this.placeXp,
    required this.completionXp,
    required this.counted,
    required this.reasons,
    required this.replay,
  });

  factory VerifiedTrip.fromMap(Map<Object?, Object?> m) => VerifiedTrip(
    ok: m['ok'] == true,
    totalXp: (m['totalXp'] as num?)?.toInt() ?? 0,
    placeXp: (m['placeXp'] as num?)?.toInt() ?? 0,
    completionXp: (m['completionXp'] as num?)?.toInt() ?? 0,
    counted: m['counted'] == true,
    reasons: [for (final r in (m['reasons'] as List? ?? const [])) '$r'],
    replay: m['replay'] == true,
  );

  final bool ok;
  final int totalXp;
  final int placeXp;
  final int completionXp;
  final bool counted;
  final List<String> reasons;

  /// True when the server had already judged this trip.
  final bool replay;
}

/// Sends a finished trip to the `verifyTrip` Cloud Function.
class ServerXpService {
  ServerXpService([FirebaseFunctions? functions])
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<VerifiedTrip> submitTrip(Map<String, Object> payload) async {
    final result = await _functions
        .httpsCallable(
          'verifyTrip',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call<Map<Object?, Object?>>(payload);
    return VerifiedTrip.fromMap(result.data);
  }
}

final serverXpServiceProvider = Provider<ServerXpService>(
  (ref) => ServerXpService(),
);
