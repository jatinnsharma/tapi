/// `unverified`: finished, but it didn't pass the trip checks (too short, or
/// the GPS looked faked), so it earns nothing and counts toward no
/// achievement.
enum AdventureStatus { active, paused, completed, discarded, unverified }

class AdventureSession {
  const AdventureSession({
    required this.id,
    required this.title,
    required this.startedAt,
    this.endedAt,
    this.status = AdventureStatus.active,
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.xpEarned = 0,
    this.groupAdventureId,
    this.trekMeters = 0,
    this.trekSeconds = 0,
    this.journeyMeters = 0,
    this.journeySeconds = 0,
    this.steps = 0,
    this.trekSteps = 0,
  });

  final String id;
  final String title;
  final DateTime startedAt;
  final DateTime? endedAt;
  final AdventureStatus status;

  /// Everything moved on the trip, journey and trek together.
  final double distanceMeters;

  /// Total trip time (journey + trek + breaks), excluding pauses.
  final int durationSeconds;
  final int xpEarned;

  /// The trek: on foot from the trek's start, return hike included (see
  /// TripSplit). Trek statistics, achievements and difficulty use only this.
  final double trekMeters;
  final int trekSeconds;

  /// The journey: getting to the trek and back, by any transport.
  final double journeyMeters;
  final int journeySeconds;

  /// Steps from the phone's step sensor over the whole trip, and while
  /// trekking. 0 when the phone has no step sensor or it wasn't allowed.
  final int steps;
  final int trekSteps;

  /// Set when this adventure was started from a Firestore Group Adventure
  /// (`features/social/domain/group_adventure.dart`) — lets live location
  /// sharing be visible to the whole group, not just 1:1 friends.
  final String? groupAdventureId;

  AdventureSession copyWith({
    DateTime? endedAt,
    AdventureStatus? status,
    double? distanceMeters,
    int? durationSeconds,
    int? xpEarned,
    double? trekMeters,
    int? trekSeconds,
    double? journeyMeters,
    int? journeySeconds,
    int? steps,
    int? trekSteps,
  }) {
    return AdventureSession(
      id: id,
      title: title,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      xpEarned: xpEarned ?? this.xpEarned,
      groupAdventureId: groupAdventureId,
      trekMeters: trekMeters ?? this.trekMeters,
      trekSeconds: trekSeconds ?? this.trekSeconds,
      journeyMeters: journeyMeters ?? this.journeyMeters,
      journeySeconds: journeySeconds ?? this.journeySeconds,
      steps: steps ?? this.steps,
      trekSteps: trekSteps ?? this.trekSteps,
    );
  }

  bool get isCompleted => status == AdventureStatus.completed;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'status': status.name,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'xp_earned': xpEarned,
      'group_adventure_id': groupAdventureId,
      'trek_meters': trekMeters,
      'trek_seconds': trekSeconds,
      'journey_meters': journeyMeters,
      'journey_seconds': journeySeconds,
      'steps': steps,
      'trek_steps': trekSteps,
    };
  }

  factory AdventureSession.fromMap(Map<String, Object?> map) {
    return AdventureSession(
      id: map['id'] as String,
      title: map['title'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: map['ended_at'] == null
          ? null
          : DateTime.parse(map['ended_at'] as String),
      status: AdventureStatus.values.byName(map['status'] as String),
      distanceMeters: (map['distance_meters'] as num).toDouble(),
      durationSeconds: map['duration_seconds'] as int,
      xpEarned: map['xp_earned'] as int,
      groupAdventureId: map['group_adventure_id'] as String?,
      trekMeters: (map['trek_meters'] as num?)?.toDouble() ?? 0,
      trekSeconds: (map['trek_seconds'] as int?) ?? 0,
      journeyMeters: (map['journey_meters'] as num?)?.toDouble() ?? 0,
      journeySeconds: (map['journey_seconds'] as int?) ?? 0,
      steps: (map['steps'] as int?) ?? 0,
      trekSteps: (map['trek_steps'] as int?) ?? 0,
    );
  }
}
