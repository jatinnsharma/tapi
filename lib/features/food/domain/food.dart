/// Vegetarian or not, as Indian menus mark it.
enum Diet {
  veg('Veg'),
  nonVeg('Non-veg'),
  both('Veg & non-veg');

  const Diet(this.label);
  final String label;

  static Diet parse(String? raw) => switch (raw) {
    'veg' => Diet.veg,
    'nonveg' => Diet.nonVeg,
    _ => Diet.both,
  };
}

/// A dish a city is known for. General knowledge, not a particular shop.
class SignatureDish {
  const SignatureDish({
    required this.name,
    required this.diet,
    required this.when,
    required this.note,
  });

  final String name;
  final Diet diet;

  /// When it is best eaten, e.g. "Breakfast" or "Winter mornings".
  final String when;
  final String note;

  factory SignatureDish.fromJson(Map<String, dynamic> json) => SignatureDish(
    name: json['name'] as String,
    diet: Diet.parse(json['diet'] as String?),
    when: (json['when'] as String?) ?? '',
    note: (json['note'] as String?) ?? '',
  );
}

/// A real place to eat, from OpenStreetMap.
class FoodSpot {
  const FoodSpot({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.kind,
    this.cuisine,
    this.diet,
    this.openingHours,
  });

  /// `osm-node-<id>`, so the same spot keeps one id.
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// "Restaurant", "Street food", "Café", "Sweets" and so on.
  final String kind;

  /// OSM's cuisine tag, made readable ("north indian, chaat").
  final String? cuisine;

  /// Only when OSM says so (`diet:vegetarian=only` is pure veg).
  final Diet? diet;

  /// OpenStreetMap opening_hours text.
  final String? openingHours;

  /// An OSM element from Overpass, or null when it has no name or position.
  static FoodSpot? fromOverpass(Map<String, dynamic> element) {
    final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = (tags['name:en'] ?? tags['name']) as String?;
    final lat = (element['lat'] ?? element['center']?['lat']) as num?;
    final lon = (element['lon'] ?? element['center']?['lon']) as num?;
    if (name == null || name.trim().isEmpty || lat == null || lon == null) {
      return null;
    }

    final amenity = tags['amenity'] as String?;
    final shop = tags['shop'] as String?;
    final kind = switch ((amenity, shop)) {
      ('restaurant', _) => 'Restaurant',
      ('fast_food', _) => 'Street food',
      ('cafe', _) => 'Café',
      ('food_court', _) => 'Food court',
      ('ice_cream', _) => 'Ice cream',
      (_, 'confectionery' || 'pastry') => 'Sweets',
      (_, 'bakery') => 'Bakery',
      _ => 'Food',
    };

    final vegTag = tags['diet:vegetarian'] as String?;
    final diet = switch (vegTag) {
      'only' => Diet.veg,
      'yes' => Diet.both,
      'no' => Diet.nonVeg,
      _ => null,
    };

    final cuisine = (tags['cuisine'] as String?)
        ?.split(';')
        .map((c) => c.trim().replaceAll('_', ' '))
        .where((c) => c.isNotEmpty)
        .join(', ');

    return FoodSpot(
      id: 'osm-${element['type'] ?? 'node'}-${element['id']}',
      name: name.trim(),
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      kind: kind,
      cuisine: cuisine == null || cuisine.isEmpty ? null : cuisine,
      diet: diet,
      openingHours: tags['opening_hours'] as String?,
    );
  }
}
