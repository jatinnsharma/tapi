import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';

void main() {
  group('Mystery Places Domain & Model', () {
    test('isMystery is true for LocationCategory.mystery', () {
      const loc = ExploreLocation(
        id: 'mystery-1',
        name: 'Hidden Temple',
        category: LocationCategory.mystery,
        description: 'An ancient relic buried beneath the ridge.',
        latitude: 30.75,
        longitude: 76.78,
        mysteryHint: 'Look where the red stones stand upright',
      );

      expect(loc.isMystery, isTrue);
      expect(
        loc.mysteryHint,
        equals('Look where the red stones stand upright'),
      );
      expect(loc.category.label, equals('Mystery'));
    });

    test('isMystery is true when mysteryHint is present even with another category', () {
      const loc = ExploreLocation(
        id: 'mystery-2',
        name: 'Secret Garden',
        category: LocationCategory.nature,
        description: 'A quiet green pocket.',
        latitude: 30.73,
        longitude: 76.79,
        mysteryHint: 'Between the two weeping fig trees',
      );

      expect(loc.isMystery, isTrue);
      expect(loc.mysteryHint, isNotNull);
    });

    test('isMystery is false for regular locations without hint', () {
      const loc = ExploreLocation(
        id: 'reg-1',
        name: 'Rose Garden',
        category: LocationCategory.nature,
        description: 'Beautiful blooming roses in springtime.',
        latitude: 30.74,
        longitude: 76.77,
      );

      expect(loc.isMystery, isFalse);
      expect(loc.mysteryHint, isNull);
    });

    test('fromMap and toMap preserve mysteryHint', () {
      final map = {
        'id': 'mystery-test',
        'name': 'Enigmatic Fountain',
        'category': 'mystery',
        'description': 'A fountain whose origin is unknown.',
        'latitude': 30.751,
        'longitude': 76.802,
        'difficulty': 'moderate',
        'xp_reward': 150,
        'discovered_at': null,
        'neighborhood': 'Sector 1',
        'city': 'Chandigarh',
        'district': 'Chandigarh',
        'region': 'Punjab',
        'country': 'India',
        'image_url': 'https://example.com/photo.jpg',
        'mystery_hint': 'Follow the stream under the archway',
      };

      final location = ExploreLocation.fromMap(map);
      expect(location.isMystery, isTrue);
      expect(location.category, LocationCategory.mystery);
      expect(location.mysteryHint, 'Follow the stream under the archway');

      final serialized = location.toMap();
      expect(serialized['mystery_hint'], 'Follow the stream under the archway');
      expect(serialized['category'], 'mystery');
    });

    test(
      'LocationCategory.values contains mystery with correct label and icon',
      () {
        expect(
          LocationCategory.values.contains(LocationCategory.mystery),
          isTrue,
        );
        expect(LocationCategory.mystery.label, 'Mystery');
        expect(LocationCategory.mystery.name, 'mystery');
      },
    );
  });

  group('Mystery masking', () {
    const mystery = ExploreLocation(
      id: 'wiki-mystery-rock-garden',
      name: 'Rock Garden of Chandigarh',
      category: LocationCategory.mystery,
      description: 'Sculpture garden.',
      latitude: 30.7525,
      longitude: 76.8067,
      mysteryHint: 'Recycled ceramic sculptures.',
    );
    // The ordinary seed copy, about 60 m away.
    const twin = ExploreLocation(
      id: 'wiki-23911325',
      name: 'Rock Garden of Chandigarh',
      category: LocationCategory.heritage,
      description: 'Sculpture garden.',
      latitude: 30.7525,
      longitude: 76.8073,
    );

    test('name stays secret until a counted trip reaches it', () {
      expect(mystery.isHiddenMystery(const {}), isTrue);
      expect(mystery.nameFor(const {}), ExploreLocation.mysteryName);
      expect(mystery.isHiddenMystery({mystery.id}), isFalse);
      expect(mystery.nameFor({mystery.id}), 'Rock Garden of Chandigarh');
    });

    test('ordinary places are never masked', () {
      expect(twin.isHiddenMystery(const {}), isFalse);
      expect(twin.nameFor(const {}), twin.name);
    });

    test('drops an ordinary copy of a mystery nearby', () {
      final shown = ExploreLocation.withoutMysteryTwins([mystery, twin]);
      expect(shown.map((p) => p.id), [mystery.id]);
    });

    test('keeps a same-name place far away, and places with other names', () {
      const farTwin = ExploreLocation(
        id: 'far',
        name: 'rock garden of chandigarh!',
        category: LocationCategory.heritage,
        description: '',
        latitude: 28.61,
        longitude: 77.20,
      );
      const other = ExploreLocation(
        id: 'other',
        name: 'Sukhna Lake',
        category: LocationCategory.lake,
        description: '',
        latitude: 30.7525,
        longitude: 76.8070,
      );
      final shown = ExploreLocation.withoutMysteryTwins([
        mystery,
        farTwin,
        other,
      ]);
      expect(shown.map((p) => p.id), [mystery.id, 'far', 'other']);
    });
  });
}
