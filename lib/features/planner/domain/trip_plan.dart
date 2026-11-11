import 'package:latlong2/latlong.dart';

import '../../../core/config/service_area.dart';
import 'planner_input.dart';

class TripStop {
  const TripStop({
    required this.id,
    required this.placeName,
    required this.description,
    required this.timeSlot,
    required this.durationMinutes,
    this.travelTimeFromPrevious,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.tip,
    this.isCompleted = false,
    this.placeId,
    this.xpReward,
    this.openingHours,
  });

  final String id;
  final String placeName;
  final String description;
  final String timeSlot; // Morning, Afternoon, Evening, Night
  final int durationMinutes;
  final String? travelTimeFromPrevious;
  final double latitude;
  final double longitude;
  final String category;
  final String? tip;
  final bool isCompleted;

  /// The real place this stop is (a `locations` id such as `wiki-123`, an
  /// OSM search id, or a stable id made from the name and position). Trips
  /// started from the stop use it, so arriving counts as visiting that place.
  final String? placeId;

  /// XP for arriving; null means the default.
  final int? xpReward;

  /// Typical opening hours the AI suggested, in OpenStreetMap's format
  /// ("Tu-Su 09:30-17:00; Mo off"). Only an estimate: the stop card prefers
  /// OpenStreetMap's own hours when the place has them.
  final String? openingHours;

  static const defaultXp = 50;

  LatLng get coordinates => LatLng(latitude, longitude);

  /// Whether the stop has a usable position in India. (Missing coordinates
  /// parse as 0, 0, which is outside.)
  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      ServiceArea.containsCoordinates(latitude, longitude);

  TripStop copyWith({
    String? id,
    String? placeName,
    String? description,
    String? timeSlot,
    int? durationMinutes,
    String? travelTimeFromPrevious,
    double? latitude,
    double? longitude,
    String? category,
    String? tip,
    bool? isCompleted,
    String? placeId,
    int? xpReward,
    String? openingHours,
  }) {
    return TripStop(
      id: id ?? this.id,
      placeName: placeName ?? this.placeName,
      description: description ?? this.description,
      timeSlot: timeSlot ?? this.timeSlot,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      travelTimeFromPrevious:
          travelTimeFromPrevious ?? this.travelTimeFromPrevious,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      category: category ?? this.category,
      tip: tip ?? this.tip,
      isCompleted: isCompleted ?? this.isCompleted,
      placeId: placeId ?? this.placeId,
      xpReward: xpReward ?? this.xpReward,
      openingHours: openingHours ?? this.openingHours,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'placeName': placeName,
    'description': description,
    'timeSlot': timeSlot,
    'durationMinutes': durationMinutes,
    'travelTimeFromPrevious': travelTimeFromPrevious,
    'latitude': latitude,
    'longitude': longitude,
    'category': category,
    'tip': tip,
    'isCompleted': isCompleted,
    'placeId': placeId,
    'xpReward': xpReward,
    'openingHours': openingHours,
  };

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      id:
          json['id'] as String? ??
          'stop-${DateTime.now().microsecondsSinceEpoch}',
      placeName: json['placeName'] as String? ?? 'Scenic Spot',
      description: json['description'] as String? ?? '',
      timeSlot: json['timeSlot'] as String? ?? 'Morning',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 60,
      travelTimeFromPrevious: json['travelTimeFromPrevious'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      category: json['category'] as String? ?? 'attraction',
      tip: json['tip'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      placeId: json['placeId'] as String?,
      xpReward: (json['xpReward'] as num?)?.toInt(),
      openingHours: (json['openingHours'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['openingHours'] as String).trim(),
    );
  }
}

class TripDayPlan {
  const TripDayPlan({
    required this.dayNumber,
    required this.title,
    this.theme,
    required this.stops,
    this.foodSuggestions = const [],
    this.dayTip,
  });

  final int dayNumber;
  final String title;
  final String? theme;
  final List<TripStop> stops;
  final List<String> foodSuggestions;
  final String? dayTip;

  TripDayPlan copyWith({
    int? dayNumber,
    String? title,
    String? theme,
    List<TripStop>? stops,
    List<String>? foodSuggestions,
    String? dayTip,
  }) {
    return TripDayPlan(
      dayNumber: dayNumber ?? this.dayNumber,
      title: title ?? this.title,
      theme: theme ?? this.theme,
      stops: stops ?? this.stops,
      foodSuggestions: foodSuggestions ?? this.foodSuggestions,
      dayTip: dayTip ?? this.dayTip,
    );
  }

  Map<String, dynamic> toJson() => {
    'dayNumber': dayNumber,
    'title': title,
    'theme': theme,
    'stops': stops.map((s) => s.toJson()).toList(),
    'foodSuggestions': foodSuggestions,
    'dayTip': dayTip,
  };

  factory TripDayPlan.fromJson(Map<String, dynamic> json) {
    return TripDayPlan(
      dayNumber: (json['dayNumber'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? 'Day 1 Highlights',
      theme: json['theme'] as String?,
      stops:
          (json['stops'] as List<dynamic>?)
              ?.map((s) => TripStop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      foodSuggestions:
          (json['foodSuggestions'] as List<dynamic>?)
              ?.map((f) => f.toString())
              .toList() ??
          const [],
      dayTip: json['dayTip'] as String?,
    );
  }
}

class TripPlan {
  const TripPlan({
    required this.id,
    required this.title,
    required this.destination,
    this.cityId,
    required this.daysCount,
    this.companion = TripCompanion.friends,
    this.pace = TripPace.moderate,
    this.budget = TripBudget.moderate,
    this.interests = const [],
    this.startDate,
    required this.createdAt,
    required this.days,
    this.overview,
    this.travelingFrom,
    this.travellers,
    this.packingChecked = const [],
    this.ownerUid,
    this.memberUids = const [],
    this.updatedAt,
    this.cloudSynced = false,
  });

  final String id;
  final String title;
  final String destination;
  final String? cityId;
  final int daysCount;
  final TripCompanion companion;
  final TripPace pace;
  final TripBudget budget;
  final List<String> interests;
  final DateTime? startDate;
  final DateTime createdAt;
  final List<TripDayPlan> days;
  final String? overview;
  final String? travelingFrom;

  /// How many people the budget estimate is for; null means the default for
  /// [companion] (see [travellerCount]).
  final int? travellers;

  /// Packing checklist items the user has ticked off.
  final List<String> packingChecked;

  /// Who created the trip in the cloud and everyone who may see and edit it
  /// (the owner included). Empty until the trip is first synced while signed
  /// in.
  final String? ownerUid;
  final List<String> memberUids;

  /// When the plan was last changed on any device. On sync the newer copy
  /// wins.
  final DateTime? updatedAt;

  /// Whether this copy has been in the cloud at least once. A synced trip
  /// that's no longer in the cloud was deleted or unshared elsewhere.
  final bool cloudSynced;

  int get travellerCount =>
      travellers ??
      switch (companion) {
        TripCompanion.solo => 1,
        TripCompanion.couple => 2,
        TripCompanion.friends => 2,
        TripCompanion.family => 4,
      };

  bool get isShared => memberUids.length > 1;

  bool isOwnedBy(String uid) => ownerUid == null || ownerUid == uid;

  DateTime get lastChanged => updatedAt ?? createdAt;

  int get totalStops => days.fold<int>(0, (sum, day) => sum + day.stops.length);

  TripPlan copyWith({
    String? id,
    String? title,
    String? destination,
    String? cityId,
    int? daysCount,
    TripCompanion? companion,
    TripPace? pace,
    TripBudget? budget,
    List<String>? interests,
    DateTime? startDate,
    DateTime? createdAt,
    List<TripDayPlan>? days,
    String? overview,
    String? travelingFrom,
    int? travellers,
    List<String>? packingChecked,
    String? ownerUid,
    List<String>? memberUids,
    DateTime? updatedAt,
    bool? cloudSynced,
  }) {
    return TripPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      destination: destination ?? this.destination,
      cityId: cityId ?? this.cityId,
      daysCount: daysCount ?? this.daysCount,
      companion: companion ?? this.companion,
      pace: pace ?? this.pace,
      budget: budget ?? this.budget,
      interests: interests ?? this.interests,
      startDate: startDate ?? this.startDate,
      createdAt: createdAt ?? this.createdAt,
      days: days ?? this.days,
      overview: overview ?? this.overview,
      travelingFrom: travelingFrom ?? this.travelingFrom,
      travellers: travellers ?? this.travellers,
      packingChecked: packingChecked ?? this.packingChecked,
      ownerUid: ownerUid ?? this.ownerUid,
      memberUids: memberUids ?? this.memberUids,
      updatedAt: updatedAt ?? this.updatedAt,
      cloudSynced: cloudSynced ?? this.cloudSynced,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'destination': destination,
    'cityId': cityId,
    'daysCount': daysCount,
    'companion': companion.name,
    'pace': pace.name,
    'budget': budget.name,
    'interests': interests,
    'startDate': startDate?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'days': days.map((d) => d.toJson()).toList(),
    'overview': overview,
    'travelingFrom': travelingFrom,
    'travellers': travellers,
    'packingChecked': packingChecked,
    'ownerUid': ownerUid,
    'memberUids': memberUids,
    'updatedAt': updatedAt?.toIso8601String(),
    'cloudSynced': cloudSynced,
  };

  factory TripPlan.fromJson(Map<String, dynamic> json) {
    return TripPlan(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Trip Itinerary',
      destination: json['destination'] as String? ?? 'India',
      cityId: json['cityId'] as String?,
      daysCount: (json['daysCount'] as num?)?.toInt() ?? 1,
      companion: TripCompanion.values.firstWhere(
        (c) => c.name == json['companion'],
        orElse: () => TripCompanion.friends,
      ),
      pace: TripPace.values.firstWhere(
        (p) => p.name == json['pace'],
        orElse: () => TripPace.moderate,
      ),
      budget: TripBudget.values.firstWhere(
        (b) => b.name == json['budget'],
        orElse: () => TripBudget.moderate,
      ),
      interests:
          (json['interests'] as List<dynamic>?)
              ?.map((i) => i.toString())
              .toList() ??
          const [],
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      days:
          (json['days'] as List<dynamic>?)
              ?.map((d) => TripDayPlan.fromJson(d as Map<String, dynamic>))
              .toList() ??
          const [],
      overview: json['overview'] as String?,
      travelingFrom: json['travelingFrom'] as String?,
      travellers: (json['travellers'] as num?)?.toInt(),
      packingChecked:
          (json['packingChecked'] as List<dynamic>?)
              ?.map((i) => i.toString())
              .toList() ??
          const [],
      ownerUid: json['ownerUid'] as String?,
      memberUids:
          (json['memberUids'] as List<dynamic>?)
              ?.map((i) => i.toString())
              .toList() ??
          const [],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      cloudSynced: json['cloudSynced'] as bool? ?? false,
    );
  }
}
