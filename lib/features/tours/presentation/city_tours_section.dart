import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_service.dart';
import '../data/tour_repository.dart';
import '../domain/curated_tour.dart';
import 'tour_detail_screen.dart';

/// "Community tours" on a city's page. Hidden when signed out or without
/// Firebase, and when the city has none.
class CityToursSection extends ConsumerWidget {
  const CityToursSection({super.key, required this.cityId});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(firebaseReadyProvider) &&
        ref.watch(authStateProvider).value != null;
    if (!signedIn) return const SizedBox.shrink();

    final tours = ref.watch(cityToursProvider(cityId)).value;
    if (tours == null || tours.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Community tours',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tours.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _TourCard(tours[i]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard(this.tour);

  final CuratedTour tour;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TourDetailScreen(tour: tour)),
      ),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tour_outlined, color: AppTheme.forest),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tour.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${tour.stops.length} stops · '
              '${tour.stopToStopKm.toStringAsFixed(1)} km',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
            ),
            Text(
              'by ${tour.creatorName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
