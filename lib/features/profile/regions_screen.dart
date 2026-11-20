import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_components.dart';
import '../../core/theme/app_theme.dart';
import '../locations/data/location_repository.dart';
import '../locations/domain/location.dart';
import 'profile_screen.dart';

typedef RegionGroups = List<({String title, List<RegionProgress> regions})>;

final regionGroupsProvider = FutureProvider.autoDispose<RegionGroups>((
  ref,
) async {
  final repository = ref.watch(locationRepositoryProvider);
  return [
    (title: 'Cities', regions: await repository.getCityCompletion()),
    (
      title: 'Neighbourhoods',
      regions: await repository.getNeighborhoodCompletion(),
    ),
    (title: 'Districts', regions: await repository.getDistrictCompletion()),
    (title: 'States', regions: await repository.getRegionCompletion()),
    (title: 'Countries', regions: await repository.getCountryCompletion()),
  ];
});

/// The groups to show: regions you've started, most explored first, and
/// the ones you haven't when [showAll]. Empty groups are dropped.
RegionGroups visibleRegionGroups(RegionGroups groups, {required bool showAll}) {
  return [
    for (final g in groups)
      if ((showAll ? g.regions : g.regions.where((r) => r.discovered > 0))
              .toList()
          case final regions when regions.isNotEmpty)
        (
          title: g.title,
          regions: [...regions]..sort((a, b) => b.percent.compareTo(a.percent)),
        ),
  ];
}

/// Every region you've explored, grouped by level (cities, neighbourhoods,
/// districts, states, countries).
class RegionsScreen extends ConsumerStatefulWidget {
  const RegionsScreen({super.key});

  @override
  ConsumerState<RegionsScreen> createState() => _RegionsScreenState();
}

class _RegionsScreenState extends ConsumerState<RegionsScreen> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(regionGroupsProvider);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Regions')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(regionGroupsProvider),
        ),
        data: (groups) {
          final shown = visibleRegionGroups(groups, showAll: _showAll);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show places not started'),
                value: _showAll,
                onChanged: (v) => setState(() => _showAll = v),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Nothing explored yet. Places you discover fill in here.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              for (final group in shown) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text(
                    group.title.toUpperCase(),
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                for (final region in group.regions)
                  RegionProgressRow(progress: region),
              ],
            ],
          );
        },
      ),
    );
  }
}
