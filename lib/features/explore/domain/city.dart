import 'package:latlong2/latlong.dart';

class City {
  final String id;
  final String name;
  final String state;
  final double latitude;
  final double longitude;
  final String blurb;
  final String imageUrl;
  final String category;

  const City({
    required this.id,
    required this.name,
    required this.state,
    required this.latitude,
    required this.longitude,
    required this.blurb,
    required this.imageUrl,
    this.category = 'heritage',
  });

  LatLng get location => LatLng(latitude, longitude);

  factory City.fromJson(Map<String, dynamic> json) => City(
    id: json['id'] as String,
    name: json['name'] as String,
    state: json['state'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    blurb: json['blurb'] as String,
    imageUrl: json['imageUrl'] as String,
    category: json['category'] as String? ?? 'heritage',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'state': state,
    'latitude': latitude,
    'longitude': longitude,
    'blurb': blurb,
    'imageUrl': imageUrl,
    'category': category,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is City && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'City($name, $state)';
}
