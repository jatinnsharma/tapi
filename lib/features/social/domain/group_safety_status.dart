enum SafetyStatusValue { ok, offRoute }

class GroupSafetyStatus {
  const GroupSafetyStatus({
    required this.uid,
    required this.status,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  final String uid;
  final SafetyStatusValue status;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory GroupSafetyStatus.fromMap(Map<String, Object?> map) {
    return GroupSafetyStatus(
      uid: map['uid'] as String,
      status: SafetyStatusValue.values.byName(map['status'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
    );
  }
}
