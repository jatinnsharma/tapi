class Accommodation {
  final String id;
  final String name;
  final String type; // e.g. Campsite, Homestay, Lodge
  final String locationName;
  final String imageUrl;
  final double nightlyRate;
  final double rating;
  final int reviewsCount;
  final List<String> amenities;

  const Accommodation({
    required this.id,
    required this.name,
    required this.type,
    required this.locationName,
    required this.imageUrl,
    required this.nightlyRate,
    required this.rating,
    required this.reviewsCount,
    required this.amenities,
  });
}
