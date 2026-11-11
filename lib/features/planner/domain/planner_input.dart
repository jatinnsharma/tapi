import 'package:latlong2/latlong.dart';

/// Travel companion style.
enum TripCompanion {
  solo('Solo', 'Self discovery & independence'),
  friends('Friends', 'Excitement, nightlife & fun'),
  couple('Couple', 'Romantic & scenic vibes'),
  family('Family', 'Kid & elder friendly pace');

  const TripCompanion(this.label, this.description);
  final String label;
  final String description;
}

/// Travel pacing.
enum TripPace {
  relaxed('Relaxed', '1-2 highlights a day, lots of leisure'),
  moderate('Balanced', '3-4 stops a day with good food breaks'),
  packed('Packed', 'Maximize sights from sunrise to night');

  const TripPace(this.label, this.description);
  final String label;
  final String description;
}

/// Budget tiers.
enum TripBudget {
  budget('Budget', 'Hostels, local street eats, public transport'),
  moderate('Moderate', 'Comfortable stays, good cafes, cabs'),
  luxury('Luxury', 'Heritage hotels, fine dining, private tours');

  const TripBudget(this.label, this.description);
  final String label;
  final String description;
}

/// Structured user input to generate a trip plan.
class PlannerInput {
  const PlannerInput({
    required this.destination,
    this.cityId,
    this.destinationCoordinates,
    required this.daysCount,
    this.companion = TripCompanion.friends,
    this.pace = TripPace.moderate,
    this.budget = TripBudget.moderate,
    this.interests = const [],
    this.travelingFrom,
    this.startDate,
    this.language = 'en',
  });

  final String destination;
  final String? cityId;
  final LatLng? destinationCoordinates;
  final int daysCount;
  final TripCompanion companion;
  final TripPace pace;
  final TripBudget budget;
  final List<String> interests;
  final String? travelingFrom;
  final DateTime? startDate;
  final String language; // 'en' or 'hi'

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'cityId': cityId,
    'daysCount': daysCount,
    'companion': companion.name,
    'pace': pace.name,
    'budget': budget.name,
    'interests': interests,
    'travelingFrom': travelingFrom,
    'startDate': startDate?.toIso8601String(),
    'language': language,
  };
}
