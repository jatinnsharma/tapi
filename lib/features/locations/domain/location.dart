import 'package:flutter/material.dart';

enum LocationCategory {
  city,
  trek,
  mountain,
  waterfall,
  lake,
  viewpoint,
  heritage,
  food,
  photography,
  hiddenGem,
  camping,
  nature,
  mystery,
}

extension LocationCategoryX on LocationCategory {
  String get label {
    switch (this) {
      case LocationCategory.city:
        return 'City';
      case LocationCategory.trek:
        return 'Trek';
      case LocationCategory.mountain:
        return 'Mountain';
      case LocationCategory.waterfall:
        return 'Waterfall';
      case LocationCategory.lake:
        return 'Lake';
      case LocationCategory.viewpoint:
        return 'Viewpoint';
      case LocationCategory.heritage:
        return 'Heritage';
      case LocationCategory.food:
        return 'Food';
      case LocationCategory.photography:
        return 'Photography';
      case LocationCategory.hiddenGem:
        return 'Hidden Gem';
      case LocationCategory.camping:
        return 'Camping';
      case LocationCategory.nature:
        return 'Nature';
      case LocationCategory.mystery:
        return 'Mystery';
    }
  }

  IconData get icon {
    switch (this) {
      case LocationCategory.city:
        return Icons.location_city;
      case LocationCategory.trek:
        return Icons.terrain;
      case LocationCategory.mountain:
        return Icons.landscape;
      case LocationCategory.waterfall:
        return Icons.water_drop;
      case LocationCategory.lake:
        return Icons.water;
      case LocationCategory.viewpoint:
        return Icons.visibility;
      case LocationCategory.heritage:
        return Icons.account_balance;
      case LocationCategory.food:
        return Icons.restaurant;
      case LocationCategory.photography:
        return Icons.camera_alt;
      case LocationCategory.hiddenGem:
        return Icons.diamond;
      case LocationCategory.camping:
        return Icons.cabin;
      case LocationCategory.nature:
        return Icons.forest;
      case LocationCategory.mystery:
        return Icons.help_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case LocationCategory.city:
        return Colors.indigo;
      case LocationCategory.trek:
        return Colors.green;
      case LocationCategory.mountain:
        return Colors.brown;
      case LocationCategory.waterfall:
        return Colors.lightBlue;
      case LocationCategory.lake:
        return Colors.blue;
      case LocationCategory.viewpoint:
        return Colors.teal;
      case LocationCategory.heritage:
        return Colors.deepOrange;
      case LocationCategory.food:
        return Colors.red;
      case LocationCategory.photography:
        return Colors.purple;
      case LocationCategory.hiddenGem:
        return Colors.pink;
      case LocationCategory.camping:
        return Colors.orange;
      case LocationCategory.nature:
        return Colors.green.shade800;
      case LocationCategory.mystery:
        return Colors.deepPurple;
    }
  }
}

/// Discovered/total counts for any level of the spec's §28 regional
/// hierarchy (city, region/state, or country) — the same shape at every
/// level, just grouped by a different field.
class RegionProgress {
  const RegionProgress({
    required this.name,
    required this.discovered,
    required this.total,
  });

  final String name;
  final int discovered;
  final int total;

  double get percent => total == 0 ? 0 : discovered / total;
}

class ExploreLocation {
  const ExploreLocation({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.difficulty,
    this.xpReward = 50,
    this.discoveredAt,
    // Defaults for places with no region info (e.g. AI suggestions):
    // version 1 covers Chandigarh only.
    this.neighborhood = 'Central',
    this.city = 'Chandigarh',
    this.district = 'Chandigarh',
    this.region = 'Chandigarh',
    this.country = 'India',
    this.imageUrl,
    this.mysteryHint,
  });

  final String id;
  final String name;
  final LocationCategory category;
  final String description;
  final double latitude;
  final double longitude;
  final String? difficulty;
  final int xpReward;
  final DateTime? discoveredAt;
  final String? imageUrl;
  final String? mysteryHint;

  /// The spec's §28 regional hierarchy:
  /// Location → Neighborhood → City → District → Region(State) → Country
  final String neighborhood;
  final String city;
  final String district;
  final String region;
  final String country;

  bool get isDiscovered => discoveredAt != null;
  bool get isMystery =>
      category == LocationCategory.mystery || mysteryHint != null;

  ExploreLocation copyWith({DateTime? discoveredAt, String? mysteryHint}) {
    return ExploreLocation(
      id: id,
      name: name,
      category: category,
      description: description,
      latitude: latitude,
      longitude: longitude,
      difficulty: difficulty,
      xpReward: xpReward,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      neighborhood: neighborhood,
      city: city,
      district: district,
      region: region,
      country: country,
      imageUrl: imageUrl,
      mysteryHint: mysteryHint ?? this.mysteryHint,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'difficulty': difficulty,
      'xp_reward': xpReward,
      'discovered_at': discoveredAt?.toIso8601String(),
      'neighborhood': neighborhood,
      'city': city,
      'district': district,
      'region': region,
      'country': country,
      'image_url': imageUrl,
      'mystery_hint': mysteryHint,
    };
  }

  factory ExploreLocation.fromMap(Map<String, Object?> map) {
    return ExploreLocation(
      id: map['id'] as String,
      name: map['name'] as String,
      category: LocationCategory.values.byName(map['category'] as String),
      description: map['description'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      difficulty: map['difficulty'] as String?,
      discoveredAt: map['discovered_at'] == null
          ? null
          : DateTime.parse(map['discovered_at'] as String),
      xpReward: map['xp_reward'] as int,
      neighborhood: (map['neighborhood'] as String?) ?? 'Central',
      city: (map['city'] as String?) ?? 'Delhi',
      district: (map['district'] as String?) ?? 'New Delhi',
      region: (map['region'] as String?) ?? 'Delhi',
      country: (map['country'] as String?) ?? 'India',
      imageUrl: map['image_url'] as String?,
      mysteryHint: map['mystery_hint'] as String?,
    );
  }
}
