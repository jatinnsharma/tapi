class EcosystemEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String locationName;
  final String imageUrl;
  final int currentAttendees;
  final int maxAttendees;
  final double price;
  final String organizerName;

  const EcosystemEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.locationName,
    required this.imageUrl,
    required this.currentAttendees,
    required this.maxAttendees,
    required this.price,
    required this.organizerName,
  });
}
