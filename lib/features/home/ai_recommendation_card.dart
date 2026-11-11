import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ai_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../../core/theme/glass.dart';
import '../ai/application/ai_places_service.dart';
import '../locations/domain/location.dart';
import '../locations/presentation/place_sheet.dart';
import '../preferences/application/preferences_service.dart';

class AiRecommendationCard extends ConsumerStatefulWidget {
  const AiRecommendationCard({super.key, required this.nearbyLocations});

  final List<ExploreLocation> nearbyLocations;

  @override
  ConsumerState<AiRecommendationCard> createState() =>
      _AiRecommendationCardState();
}

class _AiRecommendationCardState extends ConsumerState<AiRecommendationCard> {
  String? _recommendation;
  bool _isLoading = false;
  String? _error;

  Future<void> _fetchRecommendation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final aiService = ref.read(aiPlacesServiceProvider);
      final prefs = ref.read(userPreferencesProvider).value;

      final rec = await aiService.getHomeRecommendation(
        nearby: widget.nearbyLocations,
        preferences: prefs,
      );

      if (mounted) {
        setState(() {
          _recommendation = rec;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// The nearby place the AI's text recommends, if it names one. Picks the
  /// longest matching name so "Sukhna Lake Viewpoint" wins over "Sukhna Lake".
  ExploreLocation? _mentionedPlace(String text) {
    final lower = text.toLowerCase();
    ExploreLocation? best;
    for (final place in widget.nearbyLocations) {
      final name = place.name.toLowerCase();
      if (name.length < 4 || !lower.contains(name)) continue;
      if (best == null || name.length > best.name.length) best = place;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final aiReady = ref.watch(aiReadyProvider);

    if (!aiReady) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      margin: const EdgeInsets.symmetric(vertical: 16),
      radius: 28,
      tint: AppTheme.emerald,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.emerald, AppTheme.forest],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppTheme.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI Explore Next',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (_recommendation != null && !_isLoading)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppTheme.forest,
                  onPressed: _fetchRecommendation,
                  tooltip: 'Get another recommendation',
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const _RecommendationSkeleton()
          else if (_error != null)
            Text(
              'Could not load recommendation: $_error',
              style: TextStyle(color: Colors.red.shade700, height: 1.35),
            )
          else if (_recommendation != null) ...[
            Text(
              _recommendation!,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: AppTheme.ink,
              ),
            ),
            if (_mentionedPlace(_recommendation!) case final place?) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => showPlaceSheet(context, place: place),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  'Go to ${place.name}',
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _fetchRecommendation,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Ask AI for a recommendation'),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shimmering text-line placeholders shown while the recommendation loads.
class _RecommendationSkeleton extends StatelessWidget {
  const _RecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 14),
          SizedBox(height: 10),
          SkeletonBox(width: 160, height: 14),
        ],
      ),
    );
  }
}
