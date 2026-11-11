import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../domain/accommodation.dart';

final _mockAccommodations = [
  Accommodation(
    id: 'a1',
    name: 'Pine Valley Eco-Lodge',
    type: 'Lodge',
    locationName: 'Pine Valley Trailhead',
    imageUrl: 'https://images.unsplash.com/photo-1510798831971-661eb04b3739?auto=format&fit=crop&w=600&q=80',
    nightlyRate: 85.0,
    rating: 4.9,
    reviewsCount: 312,
    amenities: ['Wi-Fi', 'Breakfast', 'Hot Shower'],
  ),
  Accommodation(
    id: 'a2',
    name: 'Riverbend Campsite',
    type: 'Campsite',
    locationName: 'Lower Falls Route',
    imageUrl: 'https://images.unsplash.com/photo-1537565266751-34ad61ae0169?auto=format&fit=crop&w=600&q=80',
    nightlyRate: 20.0,
    rating: 4.5,
    reviewsCount: 156,
    amenities: ['Fire Pit', 'Restrooms', 'Pet Friendly'],
  ),
];

class AccommodationScreen extends StatelessWidget {
  const AccommodationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accommodation')),
      body: ListView.builder(
        padding: AppSpacing.page,
        itemCount: _mockAccommodations.length,
        itemBuilder: (context, index) {
          final acc = _mockAccommodations[index];
          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: SoftCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: EdgeInsets.zero,
              radius: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            acc.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFF1E8F5F), AppTheme.forest],
                                ),
                              ),
                              child: Icon(
                                Icons.house_rounded,
                                color: Colors.white70,
                                size: 40,
                              ),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0x80061A12)],
                                stops: [0.4, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: MetaPill(
                              label: acc.type,
                              background: AppTheme.forest.withValues(
                                alpha: 0.78,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: MetaPill(
                              label: '\$${acc.nightlyRate.toStringAsFixed(0)}',
                              background: AppTheme.amber,
                              foreground: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc.name,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${acc.type} • ${acc.locationName}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: AppTheme.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${acc.rating} (${acc.reviewsCount} reviews)',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final a in acc.amenities)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.forest.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  a,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.forest,
                                  ),
                                ),
                              ),
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
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Booking requires Payment setup.',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Book Now'),
                          ),
                        ),
                      ],
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
