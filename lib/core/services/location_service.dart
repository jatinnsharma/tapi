import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import 'gps_fix.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

class LocationService {
  /// A reading from a mock-location app (fake GPS) can't be trusted: places
  /// would be "discovered" and trips "walked" from the couch. Debug builds
  /// allow mocks, so the app can still be tested on an emulator.
  static bool isUntrusted(Position position) =>
      position.isMocked && !kDebugMode;

  Future<bool> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  /// Where the user is now, or null. Never waits forever: a fresh fix is
  /// given 10 seconds, then the phone's last known position is used.
  ///
  /// With [acceptRecent], a position the phone knew in the last [recentFor] is
  /// returned at once (good enough to decide "are you in Chandigarh?").
  Future<LatLng?> getCurrentLocation({
    bool acceptRecent = false,
    Duration recentFor = const Duration(minutes: 10),
  }) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LatLng? usable(Position? p) =>
        p == null || isUntrusted(p) ? null : LatLng(p.latitude, p.longitude);

    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {
      // Not available on this platform: carry on to a fresh fix.
    }
    if (acceptRecent &&
        lastKnown != null &&
        DateTime.now().difference(lastKnown.timestamp) < recentFor) {
      final recent = usable(lastKnown);
      if (recent != null) return recent;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return usable(position);
    } catch (e) {
      // Timed out or failed: an older position beats none.
      return usable(lastKnown);
    }
  }

  /// Live location for casual foreground use (e.g. the Map screen's blue
  /// dot). Not configured to survive backgrounding — there's no need to pay
  /// for a persistent notification/battery cost just to browse the map.
  Stream<LatLng> getLocationStream() {
    return Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        )
        .where((position) => !isUntrusted(position))
        .map(
          (Position position) => LatLng(position.latitude, position.longitude),
        );
  }

  /// Live location for an active adventure, configured to keep recording
  /// after the user locks the phone or switches app: a foreground-service
  /// notification on Android, and background location updates (with the OS's
  /// blue location indicator) on iOS. Both work with ordinary "while using
  /// the app" permission because the trip is started from the app; version 1
  /// never asks for "allow all the time".
  ///
  /// [batterySaving] trades GPS freshness for battery life on long
  /// adventures: lower accuracy, a larger distance filter, and a longer
  /// Android polling interval.
  Stream<GpsFix> getAdventureTrackingStream({bool batterySaving = false}) {
    return Geolocator.getPositionStream(
      locationSettings: _adventureTrackingSettings(
        batterySaving: batterySaving,
      ),
    ).map(
      (Position position) => GpsFix(
        position: LatLng(position.latitude, position.longitude),
        time: position.timestamp,
        accuracyMeters: position.accuracy,
        isMocked: isUntrusted(position),
      ),
    );
  }

  LocationSettings _adventureTrackingSettings({required bool batterySaving}) {
    final accuracy = batterySaving
        ? LocationAccuracy.medium
        : LocationAccuracy.high;
    final distanceFilter = batterySaving ? 30 : 10;

    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: Duration(seconds: batterySaving ? 20 : 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tabi',
          notificationText: 'Tracking your adventure',
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }
}
