import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/ai_status.dart';
import '../../ai/data/gemini_client.dart';
import '../../explore/data/city_repository.dart';
import '../../explore/data/place_search_service.dart';
import '../../explore/domain/city.dart';
import '../../locations/data/location_repository.dart';
import '../../locations/data/nearby_places_service.dart';
import '../../locations/domain/location.dart';
import '../domain/planner_input.dart';
import '../domain/trip_plan.dart';
import 'itinerary_repair.dart';

final tripPlannerServiceProvider = Provider<TripPlannerService>((ref) {
  return TripPlannerService(
    geminiClient: ref.watch(geminiClientProvider),
    nearbyPlacesService: ref.watch(nearbyPlacesServiceProvider),
    locationRepository: ref.watch(locationRepositoryProvider),
    cityRepository: ref.watch(cityRepositoryProvider),
    placeSearchService: ref.watch(placeSearchServiceProvider),
    isAiReady: ref.watch(aiReadyProvider),
  );
});

class TripPlannerService {
  TripPlannerService({
    required this.geminiClient,
    required this.nearbyPlacesService,
    required this.locationRepository,
    required this.cityRepository,
    required this.placeSearchService,
    required this.isAiReady,
  });

  final GeminiClient geminiClient;
  final NearbyPlacesService nearbyPlacesService;
  final LocationRepository locationRepository;
  final CityRepository cityRepository;
  final PlaceSearchService placeSearchService;
  final bool isAiReady;

  static const _uuid = Uuid();

  /// AI plans by request, kept across restarts so asking for the same trip
  /// twice costs one Gemini call. Rules-based plans are cheap and aren't
  /// cached, so a later request can still get an AI plan once AI is back.
  static const _planCacheKey = 'trip_plan_cache_v1';
  static const _planCacheMax = 15;
  static const _planCacheMaxAge = Duration(days: 30);

  /// Generates a comprehensive, day-by-day trip plan.
  /// Grounded in real OpenStreetMap/Wikipedia places for that destination.
  Future<TripPlan> generatePlan(PlannerInput input) async {
    final interests = [...input.interests]..sort();
    final cacheKey = [
      input.destination.trim().toLowerCase(),
      input.daysCount,
      input.companion.name,
      input.pace.name,
      input.budget.name,
      input.language,
      interests.join('+').toLowerCase(),
    ].join('_');

    final cached = await _readCachedPlan(cacheKey);
    if (cached != null) return _asNewTrip(cached, input);

    // 1. Resolve coordinates & city info
    final (coords, matchedCity) = await _resolveDestination(input);

    // 2. Fetch and ground with real places around this destination
    final realPlaces = await _fetchGroundingPlaces(coords);

    // 3. Attempt Gemini generation if AI is configured
    if (isAiReady) {
      try {
        final plan =
            await _generateWithGemini(
              input: input,
              coords: coords,
              city: matchedCity,
              groundedPlaces: realPlaces,
            ).timeout(
              // Never keep the user waiting forever: past this, use the
              // rules planner below.
              const Duration(seconds: 100),
            );
        if (plan != null) {
          await _writeCachedPlan(cacheKey, plan);
          return _asNewTrip(plan, input);
        }
      } catch (_) {
        // Fallback gracefully to deterministic rules planner (this includes
        // AiLimitException once the device's AI allowance is used up).
      }
    }

    // 4. Deterministic rules-based grounded planner fallback
    final fallbackPlan = _generateRulesBasedPlan(
      input: input,
      coords: coords,
      city: matchedCity,
      groundedPlaces: realPlaces,
    );
    return _asNewTrip(fallbackPlan, input);
  }

  /// Every generated plan becomes its own trip: a fresh id (so a cached plan
  /// never overwrites a saved trip the user has since edited) plus the
  /// request's own details that the cache key leaves out.
  TripPlan _asNewTrip(TripPlan plan, PlannerInput input) {
    final now = DateTime.now();
    return TripPlan(
      id: _uuid.v4(),
      title: plan.title,
      destination: input.destination,
      cityId: plan.cityId ?? input.cityId,
      daysCount: plan.daysCount,
      companion: input.companion,
      pace: input.pace,
      budget: input.budget,
      interests: input.interests,
      startDate: input.startDate,
      createdAt: now,
      updatedAt: now,
      days: plan.days,
      overview: plan.overview,
      travelingFrom: input.travelingFrom,
    );
  }

  Future<TripPlan?> _readCachedPlan(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_planCacheKey);
      if (raw == null) return null;
      final entry = (jsonDecode(raw) as Map<String, dynamic>)[key];
      if (entry is! Map<String, dynamic>) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(entry['at'] as int);
      if (DateTime.now().difference(at) > _planCacheMaxAge) return null;
      return TripPlan.fromJson(entry['plan'] as Map<String, dynamic>);
    } catch (_) {
      return null; // A broken cache just means a fresh plan.
    }
  }

  Future<void> _writeCachedPlan(String key, TripPlan plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_planCacheKey);
      final cache = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      cache[key] = {
        'at': DateTime.now().millisecondsSinceEpoch,
        'plan': plan.toJson(),
      };
      // Keep only the newest entries.
      final keys = cache.keys.toList()
        ..sort(
          (a, b) => ((cache[b] as Map)['at'] as int).compareTo(
            (cache[a] as Map)['at'] as int,
          ),
        );
      for (final old in keys.skip(_planCacheMax)) {
        cache.remove(old);
      }
      await prefs.setString(_planCacheKey, jsonEncode(cache));
    } catch (_) {}
  }

  /// Regenerates a single day with fresh stops and activities, avoiding
  /// places already planned on the other days.
  Future<TripDayPlan> regenerateDay({
    required TripPlan currentPlan,
    required int dayNumber,
  }) async {
    final (coords, matchedCity) = await _resolveDestination(
      PlannerInput(
        destination: currentPlan.destination,
        cityId: currentPlan.cityId,
        daysCount: currentPlan.daysCount,
      ),
    );

    final realPlaces = await _fetchGroundingPlaces(coords);
    final usedElsewhere = {
      for (final day in currentPlan.days)
        if (day.dayNumber != dayNumber)
          for (final stop in day.stops) ?stop.placeId,
    };
    final repairer = _repairerFor(realPlaces, coords, currentPlan.destination);
    TripDayPlan fallback(int n, Set<String> used) => _rulesDay(
      dayNumber: n,
      places: realPlaces,
      used: used,
      stopsPerDay: _stopsPerDay(currentPlan.pace),
      destination: currentPlan.destination,
      center: coords,
      city: matchedCity,
    );

    if (isAiReady) {
      try {
        final available = realPlaces
            .where((p) => !usedElsewhere.contains(p.id))
            .take(30)
            .map(
              (p) =>
                  '- ${p.name} (${p.category.name}) at ${p.latitude}, ${p.longitude}: ${p.description}',
            )
            .join('\n');
        final prompt =
            '''
Regenerate Day $dayNumber for a ${currentPlan.daysCount}-day trip to ${currentPlan.destination} (${currentPlan.companion.label}, ${currentPlan.pace.label} pace).
Pick ${_stopsPerDay(currentPlan.pace)} stops from these real places, copying each "placeName" exactly as written here:
$available

Return ONLY JSON:
{
  "dayNumber": $dayNumber,
  "title": "Fresh Theme for Day $dayNumber",
  "theme": "Theme description",
  "dayTip": "Helpful local tip",
  "foodSuggestions": ["Food place 1", "Food place 2"],
  "stops": [
    {
      "placeName": "Exact name from the list",
      "description": "Activity description",
      "timeSlot": "Morning",
      "durationMinutes": 90,
      "travelTimeFromPrevious": "10 min walk",
      "latitude": ${coords.latitude},
      "longitude": ${coords.longitude},
      "category": "heritage",
      "tip": "Tip",
      "openingHours": "Tu-Su 09:30-17:00; Mo off"
    }
  ]
}
''';
        final raw = await geminiClient
            .sendMessage(userMessage: prompt, maxTokens: 4096, json: true)
            .timeout(const Duration(seconds: 60));
        final parsed = jsonDecode(_extractJson(raw)) as Map<String, dynamic>;
        final repaired = await repairer.repair(
          [TripDayPlan.fromJson(parsed)],
          daysCount: 1,
          fallbackDay: (_, used) => fallback(dayNumber, used),
          alreadyUsed: usedElsewhere,
        );
        return repaired.single.copyWith(dayNumber: dayNumber);
      } catch (_) {}
    }

    // Rules fallback for this single day
    return fallback(dayNumber, usedElsewhere);
  }

  ItineraryRepairer _repairerFor(
    List<ExploreLocation> places,
    LatLng center,
    String destination,
  ) {
    return ItineraryRepairer(
      places: places,
      center: center,
      geocode: (name) async {
        final found = await placeSearchService.geocodePlace(
          name,
          near: center,
          cityName: destination,
        );
        if (found == null) return null;
        return (
          point: found.location,
          placeId: found.placeId ?? 'osm-${found.title}',
        );
      },
    );
  }

  static int _stopsPerDay(TripPace pace) => switch (pace) {
    TripPace.relaxed => 2,
    TripPace.moderate => 3,
    TripPace.packed => 4,
  };

  Future<(LatLng, City?)> _resolveDestination(PlannerInput input) async {
    if (input.destinationCoordinates != null) {
      return (input.destinationCoordinates!, null);
    }

    if (input.cityId != null) {
      final city = await cityRepository.getCityById(input.cityId!);
      if (city != null) return (city.location, city);
    }

    final matched = await cityRepository.searchCities(input.destination);
    if (matched.isNotEmpty) {
      return (matched.first.location, matched.first);
    }

    // Search via PlaceSearchService (OSM Geocoding)
    final results = await placeSearchService.search(input.destination);
    if (results.isNotEmpty) {
      return (results.first.location, results.first.city);
    }

    // Default to New Delhi if not found
    return (const LatLng(28.6139, 77.2090), null);
  }

  Future<List<ExploreLocation>> _fetchGroundingPlaces(LatLng coords) async {
    try {
      // Trigger background Overpass / Wikipedia fetch with timeout
      await nearbyPlacesService
          .ensureFresh(coords)
          .timeout(const Duration(seconds: 4), onTimeout: () => 0);
    } catch (_) {}

    final all = await locationRepository.getAll();
    const distance = Distance();
    final places = all
        .where(
          (p) => distance(coords, LatLng(p.latitude, p.longitude)) <= 40000,
        )
        .toList();
    return places;
  }

  Future<TripPlan?> _generateWithGemini({
    required PlannerInput input,
    required LatLng coords,
    required City? city,
    required List<ExploreLocation> groundedPlaces,
  }) async {
    final placesContext = groundedPlaces
        .take(40)
        .map((p) {
          return '- ${p.name} (Category: ${p.category.name}, Lat: ${p.latitude}, Lng: ${p.longitude}): ${p.description}';
        })
        .join('\n');

    final systemPrompt =
        '''
You are an expert Indian travel itinerary planner. You create vibrant, culturally authentic, and realistic day-by-day travel plans grounded in genuine places in India.
Ground your itinerary in the following REAL places known for this area:
$placesContext

STRICT REQUIREMENTS:
1. Return strictly raw JSON with NO markdown code fences, NO explanation.
2. Plan each stop for a time slot when the place is open (many museums close on Mondays or Fridays; temples often close in the afternoon).
3. Prefer places from the list above and copy their names exactly as written. Only add a place that is not listed if it is a well-known real landmark in this destination, and give its true coordinates.
4. The JSON schema must match:
{
  "title": "Title of trip",
  "overview": "Overview of this trip",
  "days": [
    {
      "dayNumber": 1,
      "title": "Day title",
      "theme": "Day theme",
      "dayTip": "Local tip (e.g. dress code, best time to visit)",
      "foodSuggestions": ["Specific famous food or street eatery"],
      "stops": [
        {
          "placeName": "Name of real place",
          "description": "What to do and see here",
          "timeSlot": "Morning / Afternoon / Evening",
          "durationMinutes": 90,
          "travelTimeFromPrevious": "15 min cab / walk",
          "latitude": 28.6139,
          "longitude": 77.2090,
          "category": "heritage / spiritual / food / nature",
          "tip": "Short insider tip",
          "openingHours": "Typical hours in OpenStreetMap format, e.g. Tu-Su 09:30-17:00; Mo off, or 24/7 for ghats, streets and open areas"
        }
      ]
    }
  ]
}
''';

    final langInstruction = input.language == 'hi'
        ? '- Language: Write all titles, overview, day themes, descriptions, tips, and food suggestions in Hindi (हिंदी script).'
        : '- Language: English with authentic local Indian terminology.';

    final userMessage =
        '''
Create a ${input.daysCount}-day trip itinerary to ${input.destination}.
- Companion: ${input.companion.label} (${input.companion.description})
- Pacing: ${input.pace.label} (${input.pace.description})
- Budget: ${input.budget.label}
- Interests: ${input.interests.isEmpty ? 'Highlights & Culture' : input.interests.join(', ')}
${input.travelingFrom != null ? '- Traveling from: ${input.travelingFrom}' : ''}
$langInstruction

Generate exactly ${input.daysCount} days with 2 to 4 stops per day matching the pace.
''';

    final response = await geminiClient.sendMessage(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 8192,
      json: true,
    );

    final cleanJson = _extractJson(response);
    final data = jsonDecode(cleanJson) as Map<String, dynamic>;

    final rawDays = data['days'] as List<dynamic>? ?? [];
    final parsedDays = rawDays
        .whereType<Map<String, dynamic>>()
        .map(TripDayPlan.fromJson)
        .toList();
    if (parsedDays.isEmpty) return null;

    final days = await _repairerFor(groundedPlaces, coords, input.destination)
        .repair(
          parsedDays,
          daysCount: input.daysCount,
          fallbackDay: (n, used) => _rulesDay(
            dayNumber: n,
            places: groundedPlaces,
            used: used,
            stopsPerDay: _stopsPerDay(input.pace),
            destination: input.destination,
            center: coords,
            city: city,
          ),
        );

    return TripPlan(
      id: _uuid.v4(),
      title:
          data['title'] as String? ??
          '${input.daysCount} Days in ${input.destination}',
      destination: input.destination,
      cityId: input.cityId ?? city?.id,
      daysCount: input.daysCount,
      companion: input.companion,
      pace: input.pace,
      budget: input.budget,
      interests: input.interests,
      startDate: input.startDate,
      createdAt: DateTime.now(),
      days: days,
      overview: data['overview'] as String?,
    );
  }

  TripPlan _generateRulesBasedPlan({
    required PlannerInput input,
    required LatLng coords,
    required City? city,
    required List<ExploreLocation> groundedPlaces,
  }) {
    final used = <String>{};
    final days = [
      for (var d = 1; d <= input.daysCount; d++)
        _rulesDay(
          dayNumber: d,
          places: groundedPlaces,
          used: used,
          stopsPerDay: _stopsPerDay(input.pace),
          destination: input.destination,
          center: coords,
          city: city,
        ),
    ];

    return TripPlan(
      id: _uuid.v4(),
      title: '${input.daysCount} Days in ${input.destination}',
      destination: input.destination,
      cityId: input.cityId ?? city?.id,
      daysCount: input.daysCount,
      companion: input.companion,
      pace: input.pace,
      budget: input.budget,
      interests: input.interests,
      startDate: input.startDate,
      createdAt: DateTime.now(),
      days: days,
      overview:
          'A curated journey through ${input.destination} tailored for a ${input.companion.label.toLowerCase()} trip at a ${input.pace.label.toLowerCase()} pace.',
    );
  }

  /// One day built from real places not in [used] (which it adds to). Stops
  /// carry the place's id and XP, so arriving counts as visiting it. With no
  /// places left it revisits one with a different focus; with none at all,
  /// it uses generic spots around the destination.
  TripDayPlan _rulesDay({
    required int dayNumber,
    required List<ExploreLocation> places,
    required Set<String> used,
    required int stopsPerDay,
    required String destination,
    required LatLng center,
    required City? city,
  }) {
    final pool = places.isNotEmpty
        ? places
        : _createDefaultPlaces(destination, center, city);
    final fresh = pool.where((p) => !used.contains(p.id)).take(stopsPerDay);

    TripStop stopFor(
      ExploreLocation p,
      int s, {
      bool revisit = false,
    }) => TripStop(
      id: _uuid.v4(),
      placeName: revisit ? '${p.name} & Surrounds' : p.name,
      description: revisit
          ? 'Local neighborhood walk, street food and viewpoint.'
          : p.description.isNotEmpty
          ? p.description
          : 'Explore iconic highlights, photography and local architecture.',
      timeSlot: ItineraryRepairer.normalizeTimeSlot('', s),
      durationMinutes: revisit ? 90 : 75,
      travelTimeFromPrevious: s > 0 ? '15 min cab / walk' : null,
      latitude: p.latitude,
      longitude: p.longitude,
      category: p.category.name,
      tip: revisit
          ? 'Enjoy a leisurely stroll.'
          : 'Visit with comfortable shoes and keep camera ready.',
      placeId: p.id,
      xpReward: p.xpReward,
    );

    final stops = <TripStop>[];
    for (final p in fresh) {
      used.add(p.id);
      stops.add(stopFor(p, stops.length));
    }
    // Ran out of unique places: revisit one with a different focus.
    if (stops.isEmpty) {
      stops.add(stopFor(pool[(dayNumber - 1) % pool.length], 0, revisit: true));
    }

    return TripDayPlan(
      dayNumber: dayNumber,
      title: switch (dayNumber) {
        1 => 'Welcome & Iconic Landmarks',
        2 => 'Heritage, Culture & Local Markets',
        3 => 'Hidden Corners & Viewpoints',
        _ => 'Day $dayNumber Exploration',
      },
      theme: 'Experiencing the heart of $destination',
      stops: stops,
      foodSuggestions: const [
        'Local regional specialty breakfast & chai',
        'Authentic thali / popular heritage eatery for lunch',
      ],
      dayTip: 'Carry cash for small street vendors and stay hydrated throughout the day.',
    );
  }

  List<ExploreLocation> _createDefaultPlaces(
    String destination,
    LatLng center,
    City? city,
  ) {
    return [
      ExploreLocation(
        id: 'place-${destination.toLowerCase()}-1',
        name: '${city?.name ?? destination} Heritage Core',
        category: LocationCategory.heritage,
        description: 'Historic city square and architectural center.',
        latitude: center.latitude,
        longitude: center.longitude,
        city: city?.name ?? destination,
        xpReward: 60,
      ),
      ExploreLocation(
        id: 'place-${destination.toLowerCase()}-2',
        name: '${city?.name ?? destination} Grand Promenade',
        category: LocationCategory.viewpoint,
        description: 'Vibrant local walk with panoramic sights.',
        latitude: center.latitude + 0.008,
        longitude: center.longitude + 0.008,
        city: city?.name ?? destination,
        xpReward: 50,
      ),
      ExploreLocation(
        id: 'place-${destination.toLowerCase()}-3',
        name: '${city?.name ?? destination} Traditional Bazaar',
        category: LocationCategory.food,
        description: 'Bustling bazaar with handicrafts and street cuisine.',
        latitude: center.latitude - 0.007,
        longitude: center.longitude + 0.005,
        city: city?.name ?? destination,
        xpReward: 50,
      ),
    ];
  }

  /// The JSON object in a reply, ignoring code fences or any text around it.
  String _extractJson(String response) {
    final text = response.trim();
    final first = text.indexOf('{');
    final last = text.lastIndexOf('}');
    if (first < 0 || last <= first) return text;
    return text.substring(first, last + 1);
  }
}
