import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trip_plan.dart';

/// The last copy of each trip seen in the cloud: the common starting point
/// for merging this phone's edits with a friend's (see `mergePlans`).
/// Kept on the phone, so edits made offline still merge after a restart.
class TripBaseStore {
  static const _prefix = 'trip_base_v1_';

  Future<TripPlan?> get(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$tripId');
    if (raw == null) return null;
    try {
      return TripPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> set(TripPlan cloudCopy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix${cloudCopy.id}',
      jsonEncode(cloudCopy.toJson()),
    );
  }

  Future<void> remove(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$tripId');
  }
}
