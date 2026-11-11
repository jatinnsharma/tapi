class GearItem {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final double dailyRate;
  final String providerName;
  final double providerRating;

  const GearItem({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.dailyRate,
    required this.providerName,
    required this.providerRating,
  });
}
