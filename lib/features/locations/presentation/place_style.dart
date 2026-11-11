import 'package:flutter/material.dart';

import '../domain/location.dart';

/// Visual treatment of a place card per category: top-to-bottom gradient
/// stops used when a place has no photo.
extension LocationCategoryStyle on LocationCategory {
  List<Color> get gradient {
    switch (this) {
      case LocationCategory.trek:
        return const [Color(0xFF6FAEDD), Color(0xFF2A5E8C)];
      case LocationCategory.photography:
        return const [Color(0xFFF2A65E), Color(0xFFD9602A)];
      case LocationCategory.food:
        return const [Color(0xFF5CC4B2), Color(0xFF1E7A73)];
      case LocationCategory.camping:
        return const [Color(0xFFEBBE6A), Color(0xFFB9772B)];
      case LocationCategory.waterfall:
        return const [Color(0xFF6FD0E0), Color(0xFF1F7F9A)];
      case LocationCategory.lake:
        return const [Color(0xFF7FA8E8), Color(0xFF2F4F9E)];
      case LocationCategory.heritage:
        return const [Color(0xFFE59A78), Color(0xFFA9492F)];
      case LocationCategory.hiddenGem:
        return const [Color(0xFFC79AE0), Color(0xFF6D3F93)];
      case LocationCategory.viewpoint:
        return const [Color(0xFF8CCB9B), Color(0xFF2A7A57)];
      case LocationCategory.mountain:
        return const [Color(0xFFB4A58F), Color(0xFF5D4E3F)];
      case LocationCategory.city:
        return const [Color(0xFF9AA8E6), Color(0xFF3E4A9A)];
      case LocationCategory.nature:
        return const [Color(0xFF9ED48A), Color(0xFF2F7A3A)];
      case LocationCategory.mystery:
        return const [Color(0xFF8E2DE2), Color(0xFF4A00E0)];
    }
  }

  /// Short label for chips and card subtitles.
  String get shortLabel {
    switch (this) {
      case LocationCategory.photography:
        return 'Photo';
      case LocationCategory.food:
        return 'Café';
      case LocationCategory.hiddenGem:
        return 'Gem';
      case LocationCategory.mystery:
        return 'Mystery';
      default:
        return label;
    }
  }
}
