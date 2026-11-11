import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/domain/location.dart';
import '../../preferences/domain/user_preferences.dart';
import '../data/gemini_client.dart';

final aiPlacesServiceProvider = Provider<AiPlacesService>((ref) {
  return AiPlacesService(ref.watch(geminiClientProvider));
});

/// AI help with places: a short "where to go today" recommendation for Home,
/// and suggestions of places around a point for the Map's "Discover" button.
class AiPlacesService {
  AiPlacesService(this._client);

  final GeminiClient _client;

  Future<String> getHomeRecommendation({
    required List<ExploreLocation> nearby,
    UserPreferences? preferences,
  }) async {
    if (nearby.isEmpty) return 'No nearby locations found to recommend.';

    final candidateList = nearby
        .take(8)
        .map((l) => '${l.name} (${l.category.label})')
        .join(', ');

    final preferenceLine = preferences == null || !preferences.hasAnyPreference
        ? ''
        : 'User interests: ${preferences.interests.join(", ")}. ';

    final systemPrompt = '''
You are an AI exploration assistant. Based on the nearby locations and user preferences, recommend ONE place to visit today and give a short 2-sentence pitch on why. Be enthusiastic. Do not output JSON, just conversational text.
''';

    final userMessage = '${preferenceLine}Nearby places: $candidateList.';

    return _client.sendMessage(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );
  }

  Future<List<ExploreLocation>> generateNearbyLocations(
    double latitude,
    double longitude,
  ) async {
    final systemPrompt = '''
You are an AI location generator for an exploration app.
Given a latitude and longitude, generate EXACTLY 50 real-world interesting places (parks, heritage sites, cafes, viewpoints, hidden gems) within a few kilometers of those coordinates.
Return ONLY a JSON array of objects, no markdown fences, no commentary, shaped exactly like this:
[
  {
    "id": "loc-unique-id",
    "name": "Place Name",
    "category": "heritage", // Must be one of: city, trek, mountain, waterfall, lake, viewpoint, heritage, food, photography, hiddenGem, camping, nature
    "description": "A short, engaging description.",
    "latitude": 12.34,
    "longitude": 56.78,
    "xpReward": 50,
    "neighborhood": "Local area name",
    "city": "City name",
    "district": "District name",
    "region": "State/Region name",
    "country": "Country name",
    "imageUrl": "https://image.pollinations.ai/prompt/{url_encoded_detailed_description_of_place}"
  }
]
For the imageUrl, use the pollinations.ai prompt URL format shown above, replacing {url_encoded_detailed_description_of_place} with a URL-encoded descriptive prompt for an image of that place (e.g. "A%20beautiful%20view%20of%20Sukhna%20Lake%20Chandigarh").
''';

    final userMessage =
        'Generate 50 locations near latitude: $latitude, longitude: $longitude.';

    final raw = await _client.sendMessage(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 8192,
    );

    try {
      final jsonStart = raw.indexOf('[');
      final jsonEnd = raw.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd < jsonStart) {
        throw FormatException('AI response was not a valid JSON array: $raw');
      }
      final decoded =
          jsonDecode(raw.substring(jsonStart, jsonEnd + 1)) as List<dynamic>;
      final locations = <ExploreLocation>[];
      for (int i = 0; i < decoded.length; i++) {
        final map = decoded[i] as Map<String, dynamic>;
        locations.add(
          ExploreLocation(
            id:
                map['id'] as String? ??
                'loc-${DateTime.now().microsecondsSinceEpoch}-$i',
            name: map['name'] as String? ?? 'Unknown Place',
            category: LocationCategory.values.firstWhere(
              (e) => e.name == map['category'],
              orElse: () => LocationCategory.hiddenGem,
            ),
            description: map['description'] as String? ?? '',
            latitude: (map['latitude'] as num).toDouble(),
            longitude: (map['longitude'] as num).toDouble(),
            xpReward: (map['xpReward'] as num?)?.toInt() ?? 50,
            neighborhood: map['neighborhood'] as String? ?? 'Local',
            city: map['city'] as String? ?? 'City',
            district: map['district'] as String? ?? 'District',
            region: map['region'] as String? ?? 'Region',
            country: map['country'] as String? ?? 'Country',
            imageUrl: map['imageUrl'] as String?,
          ),
        );
      }
      return locations;
    } catch (e) {
      throw StateError('Failed to parse AI location generation: $e');
    }
  }
}
