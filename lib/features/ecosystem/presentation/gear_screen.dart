import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../domain/gear.dart';

final _mockGear = [
  GearItem(
    id: 'gear1',
    name: '4-Season Alpine Tent',
    category: 'Tents',
    imageUrl: 'https://images.unsplash.com/photo-1517823382902-f58c46014457?auto=format&fit=crop&w=400&q=80',
    dailyRate: 15.0,
    providerName: 'Himalayan Gear Co.',
    providerRating: 4.8,
  ),
  GearItem(
    id: 'gear2',
    name: 'Zero-Degree Sleeping Bag',
    category: 'Sleeping',
    imageUrl: 'https://images.unsplash.com/photo-1534887372990-25e24395e8eb?auto=format&fit=crop&w=400&q=80',
    dailyRate: 8.0,
    providerName: 'Adventure Rentals',
    providerRating: 4.5,
  ),
  GearItem(
    id: 'gear3',
    name: 'Carbon Fiber Trekking Poles',
    category: 'Accessories',
    imageUrl: 'https://images.unsplash.com/photo-1523306806530-332a6886e927?auto=format&fit=crop&w=400&q=80',
    dailyRate: 5.0,
    providerName: 'Trek Essentials',
    providerRating: 4.9,
  ),
];

class GearScreen extends StatelessWidget {
  const GearScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gear Rental')),
      body: GridView.builder(
        padding: AppSpacing.page,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisExtent: 290,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: _mockGear.length,
        itemBuilder: (context, index) {
          final gear = _mockGear[index];
          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: PressableScale(
              child: SoftCard(
                padding: EdgeInsets.zero,
                radius: 26,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              gear.imageUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF1E8F5F),
                                      AppTheme.forest,
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.backpack_rounded,
                                  color: Colors.white70,
                                  size: 36,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              left: 10,
                              child: MetaPill(
                                label: gear.category,
                                background: AppTheme.forest.withValues(
                                  alpha: 0.78,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gear.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '\$${gear.dailyRate.toStringAsFixed(0)}/day',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: AppTheme.amber,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    gear.providerRating.toString(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
