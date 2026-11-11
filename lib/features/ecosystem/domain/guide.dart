class Guide {
  final String id;
  final String name;
  final String bio;
  final String photoUrl;
  final double rating;
  final int reviewsCount;
  final List<String> specialties;
  final double hourlyRate;
  final bool isAvailable;

  const Guide({
    required this.id,
    required this.name,
    required this.bio,
    required this.photoUrl,
    required this.rating,
    required this.reviewsCount,
    required this.specialties,
    required this.hourlyRate,
    this.isAvailable = true,
  });
}
