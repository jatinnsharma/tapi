class RoutePoint {
  const RoutePoint({
    required this.adventureId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitude,
    this.speed,
  });

  final String adventureId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? altitude;
  final double? speed;

  Map<String, Object?> toMap() {
    return {
      'adventure_id': adventureId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'altitude': altitude,
      'speed': speed,
    };
  }

  factory RoutePoint.fromMap(Map<String, Object?> map) {
    return RoutePoint(
      adventureId: map['adventure_id'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      timestamp: DateTime.parse(map['timestamp'] as String),
      altitude: map['altitude'] as double?,
      speed: map['speed'] as double?,
    );
  }
}
