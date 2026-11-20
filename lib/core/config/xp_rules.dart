/// XP a place pays, by kind. The server (`functions/lib/evaluate_trip.js`,
/// `PLACE_XP`) uses the same table to judge trips; `test/xp_rules_test.dart`
/// keeps the two equal.
const placeXpByCategory = {
  'heritage': 80,
  'nature': 70,
  'lake': 60,
  'photography': 60,
  'viewpoint': 70,
  'hiddenGem': 110,
  'city': 50,
  'trek': 100,
  'mountain': 100,
  'waterfall': 90,
  'camping': 80,
  'food': 50,
  'mystery': 110,
};

/// What a place pays when its kind isn't in the table.
const defaultPlaceXp = 50;

/// No place pays less or more than this, whatever it claims (a deep link's
/// `destXp`, an AI suggestion's number, an edited database row).
const minPlaceXp = 50;
const maxPlaceXp = 110;

/// [xp] held within [minPlaceXp]..[maxPlaceXp].
int clampPlaceXp(int xp) => xp.clamp(minPlaceXp, maxPlaceXp);
