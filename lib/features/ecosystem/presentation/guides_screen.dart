import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../domain/guide.dart';

// Mock data for demonstration
final _mockGuides = [
  Guide(
    id: 'g1',
    name: 'Tenzing N.',
    bio: 'Experienced mountaineer and local flora expert. 10+ years guiding in the Himalayas.',
    photoUrl: 'https://i.pravatar.cc/150?u=tenzing',
    rating: 4.9,
    reviewsCount: 124,
    specialties: ['Mountaineering', 'Botany', 'High Altitude'],
    hourlyRate: 25.0,
  ),
  Guide(
    id: 'g2',
    name: 'Sarah J.',
    bio: 'Wilderness first responder and avid bird watcher. Great with families and beginners.',
    photoUrl: 'https://i.pravatar.cc/150?u=sarah',
    rating: 4.7,
    reviewsCount: 89,
    specialties: ['Bird Watching', 'Family Treks', 'First Aid'],
    hourlyRate: 18.0,
  ),
  Guide(
    id: 'g3',
    name: 'Raj K.',
    bio: 'Cultural historian and heritage walk specialist. Speaks 4 languages fluently.',
    photoUrl: 'https://i.pravatar.cc/150?u=raj',
    rating: 4.8,
    reviewsCount: 201,
    specialties: ['Heritage', 'History', 'City Walks'],
    hourlyRate: 20.0,
    isAvailable: false,
  ),
];

class GuidesScreen extends StatelessWidget {
  const GuidesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Guides')),
      body: ListView.builder(
        padding: AppSpacing.page,
        itemCount: _mockGuides.length,
        itemBuilder: (context, index) {
          final guide = _mockGuides[index];
          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: SoftCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: Image.network(
                          guide.photoUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              AppAvatar(initial: guide.name, size: 60),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              guide.name,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: AppTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _InfoPill(
                                  icon: Icons.star_rounded,
                                  label:
                                      '${guide.rating} (${guide.reviewsCount})',
                                  color: AppTheme.amberText,
                                ),
                                Text(
                                  '\$${guide.hourlyRate.toStringAsFixed(2)} / hour',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    guide.bio,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in guide.specialties)
                        _InfoPill(label: s, color: AppTheme.forest),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: guide.isAvailable
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Booking flow requires Payment integration.',
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: Text(
                        guide.isAvailable
                            ? 'Book Guide'
                            : 'Currently Unavailable',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small tinted pill used for ratings and specialty tags.
class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppTheme.amber),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
