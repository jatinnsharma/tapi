import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../locations/domain/location.dart';
import '../../../locations/presentation/place_sheet.dart';
import '../../data/city_repository.dart';
import '../../data/place_search_service.dart';
import '../../data/recent_searches.dart';
import '../../domain/city.dart';
import '../../domain/search_ranking.dart';
import '../../domain/search_result.dart';

class ExploreSearchBar extends ConsumerWidget {
  const ExploreSearchBar({super.key});

  void _openSearchModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SearchSheet(
        onSelectResult: (result) {
          Navigator.of(sheetContext).pop();
          openSearchResult(context, result);
        },
        onPlanTrip: (result) {
          Navigator.of(sheetContext).pop();
          context.push(
            Uri(
              path: '/trip-planner',
              queryParameters: {
                'destination': result.title,
                if (result.city != null) 'cityId': result.city!.id,
              },
            ).toString(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Search places and cities in India',
      child: GestureDetector(
        onTap: () => _openSearchModal(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppTheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search places, cities in India...',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.cream,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'All India',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.forest,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A city opens its page; a place opens its details (photos, how far, Start
/// a trip), rather than starting a trip straight away.
void openSearchResult(BuildContext context, SearchResult result) {
  if (result.isCity && result.city != null) {
    context.push('/city/${result.city!.id}');
  } else {
    showPlaceSheet(
      context,
      place: result.toExploreLocation(),
      distanceKm: result.distanceKm,
    );
  }
}

/// Destinations suggested before the user types, by catalog name.
const _popularDestinations = [
  'Varanasi',
  'North Goa',
  'Jaipur',
  'Manali',
  'Rishikesh',
  'Udaipur',
  'Leh',
  'Munnar',
  'Agra',
  'Darjeeling & Kalimpong',
  'Amritsar',
  'Hampi',
];

class SearchSheet extends ConsumerStatefulWidget {
  const SearchSheet({
    super.key,
    required this.onSelectResult,
    required this.onPlanTrip,
  });

  final ValueChanged<SearchResult> onSelectResult;
  final ValueChanged<SearchResult> onPlanTrip;

  @override
  ConsumerState<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<SearchSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  /// Bumped on every new query, so a slow answer for an older query can't
  /// replace the results for what's typed now.
  int _generation = 0;

  List<SearchResult> _local = const [];
  List<SearchResult> _online = const [];
  bool _onlineLoading = false;
  bool _onlineUnavailable = false;
  bool _searchedEverywhere = false;

  List<SearchResult> _recent = const [];
  List<City> _popular = const [];
  LatLng? _near;

  /// Pause after typing before searching online.
  static const _onlineDelay = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    _loadStart();
  }

  Future<void> _loadStart() async {
    final recent = await ref.read(recentSearchesProvider).load();
    final cities = await ref.read(cityRepositoryProvider).getCities();
    final byName = {for (final c in cities) c.name: c};
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _popular = [for (final n in _popularDestinations) ?byName[n]];
    });
    // Best effort and never blocking: results get distances once known.
    try {
      final here = await ref
          .read(locationServiceProvider)
          .getCurrentLocation(acceptRecent: true)
          .timeout(const Duration(seconds: 5));
      if (!mounted || here == null) return;
      setState(() {
        _near = here;
        _local = [for (final r in _local) r.withDistanceFrom(here)];
        _online = [for (final r in _online) r.withDistanceFrom(here)];
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String get _query => _ctrl.text.trim();

  void _onChanged() {
    _debounce?.cancel();
    final q = _query;
    final generation = ++_generation;
    if (q.isEmpty) {
      setState(() {
        _local = const [];
        _online = const [];
        _onlineLoading = false;
        _onlineUnavailable = false;
        _searchedEverywhere = false;
      });
      return;
    }
    setState(() => _searchedEverywhere = false);

    // On the phone: instant.
    ref.read(placeSearchServiceProvider).searchLocal(q, near: _near).then((r) {
      if (mounted && generation == _generation) setState(() => _local = r);
    });

    // Online: after a short pause in typing.
    if (q.length < 2) {
      setState(() {
        _online = const [];
        _onlineLoading = false;
      });
      return;
    }
    setState(() => _onlineLoading = true);
    _debounce = Timer(_onlineDelay, () => _searchOnline(q, generation));
  }

  Future<void> _searchOnline(String q, int generation) async {
    final service = ref.read(placeSearchServiceProvider);
    try {
      final results = await service.searchOnline(q, near: _near);
      if (!mounted || generation != _generation) return;
      setState(() {
        _online = results;
        _onlineLoading = false;
        _onlineUnavailable = false;
      });
    } on SearchUnavailableException {
      if (!mounted || generation != _generation) return;
      setState(() {
        _online = const [];
        _onlineLoading = false;
        _onlineUnavailable = true;
      });
    }
  }

  /// The keyboard's search key: search online now, and if that finds
  /// nothing, try the other search service too.
  Future<void> _submit() async {
    final q = _query;
    if (q.isEmpty) return;
    _debounce?.cancel();
    final generation = _generation;
    setState(() => _onlineLoading = true);
    await _searchOnline(q, generation);
    if (!mounted || generation != _generation) return;
    if (_merged.isEmpty || _online.isEmpty) await _searchEverywhere();
  }

  Future<void> _searchEverywhere() async {
    final q = _query;
    final generation = _generation;
    setState(() {
      _onlineLoading = true;
      _searchedEverywhere = true;
    });
    try {
      final more = await ref
          .read(placeSearchServiceProvider)
          .searchNominatim(q, near: _near);
      if (!mounted || generation != _generation) return;
      setState(() {
        _online = PlaceSearchService.mergeResults(_online, more);
        _onlineLoading = false;
        _onlineUnavailable = false;
      });
    } on SearchUnavailableException {
      if (!mounted || generation != _generation) return;
      setState(() {
        _onlineLoading = false;
        _onlineUnavailable = true;
      });
    }
  }

  List<SearchResult> get _merged =>
      PlaceSearchService.mergeResults(_local, _online);

  Future<void> _select(SearchResult result) async {
    unawaited(ref.read(recentSearchesProvider).add(result));
    widget.onSelectResult(result);
  }

  Future<void> _removeRecent(SearchResult result) async {
    final updated = await ref.read(recentSearchesProvider).remove(result);
    if (mounted) setState(() => _recent = updated);
  }

  Future<void> _clearRecent() async {
    await ref.read(recentSearchesProvider).clear();
    if (mounted) setState(() => _recent = const []);
  }

  @override
  Widget build(BuildContext context) {
    // Material (not a decorated box), so result rows show their tap ripple.
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'City, temple, fort, lake, address…',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear',
                          onPressed: _ctrl.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.cream,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // A thin bar while online results are coming.
            SizedBox(
              height: 2,
              child: _onlineLoading && _query.isNotEmpty
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            Expanded(child: _query.isEmpty ? _buildStart() : _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildStart() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: _SectionTitle('Recent')),
              TextButton(
                onPressed: _clearRecent,
                child: const Text('Clear all'),
              ),
            ],
          ),
          for (final r in _recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1F3F4),
                child: Icon(Icons.history, color: AppTheme.inkMuted),
              ),
              title: Text(
                r.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                r.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove from recent',
                onPressed: () => _removeRecent(r),
              ),
              onTap: () => _select(r.withDistanceFrom(_near)),
            ),
          const SizedBox(height: 12),
        ],
        if (_popular.isNotEmpty) ...[
          const _SectionTitle('Popular destinations'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _popular)
                ActionChip(
                  avatar: const Icon(Icons.location_city_rounded, size: 18),
                  label: Text(c.name),
                  onPressed: () => _select(
                    SearchResult(
                      title: c.name,
                      subtitle: c.state,
                      location: c.location,
                      type: SearchResultType.city,
                      city: c,
                      kind: 'City',
                      state: c.state,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        const Text(
          'Try a city ("Banaras" works too), a landmark like "Hawa Mahal", or a '
          'kind of place like "fort" or "lake": places near you come first.',
          style: TextStyle(color: AppTheme.inkMuted, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final results = _merged;
    final waiting = _onlineLoading && results.isEmpty;

    if (results.isEmpty && !waiting) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.travel_explore, size: 48, color: AppTheme.inkMuted),
          const SizedBox(height: 12),
          Text(
            'No matches for "$_query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _onlineUnavailable
                ? "You seem to be offline, so only cities and places saved on "
                      'this phone were searched.'
                : 'Check the spelling, or try a nearby city or a shorter name.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.inkMuted, height: 1.4),
          ),
          if (!_searchedEverywhere && _query.length >= 3) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.public),
                label: const Text('Search everywhere'),
                onPressed: _searchEverywhere,
              ),
            ),
          ],
        ],
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_onlineUnavailable)
          const _Notice(
            icon: Icons.cloud_off_rounded,
            text: "Offline: showing cities and places saved on this phone.",
          ),
        for (final r in results)
          _ResultTile(
            result: r,
            query: _query,
            onTap: () => _select(r),
            onPlan: r.isCity ? () => widget.onPlanTrip(r) : null,
          ),
        if (_onlineLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Searching more places…',
                  style: TextStyle(color: AppTheme.inkMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppTheme.ink,
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F3F4),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.inkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppTheme.inkMuted)),
        ),
      ],
    ),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.query,
    required this.onTap,
    this.onPlan,
  });

  final SearchResult result;
  final String query;
  final VoidCallback onTap;
  final VoidCallback? onPlan;

  String? get _distance {
    final km = result.distanceKm;
    if (km == null) return null;
    if (km < 1) return '${(km * 1000 / 10).round() * 10} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  @override
  Widget build(BuildContext context) {
    final style = result.isCity
        ? (icon: Icons.location_city_rounded, color: AppTheme.primary)
        : (icon: result.category.icon, color: result.category.color);
    final saved = result.savedPlace != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: 0.13),
          shape: BoxShape.circle,
        ),
        child: Icon(style.icon, color: style.color, size: 22),
      ),
      title: _Highlighted(text: result.title, query: query),
      subtitle: Text(
        [if (saved) 'Saved place', result.subtitle].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_distance != null)
            Text(
              _distance!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkMuted,
              ),
            ),
          if (onPlan != null)
            InkWell(
              onTap: onPlan,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: AppTheme.primary),
                    SizedBox(width: 3),
                    Text(
                      'Plan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The title with the typed part in bold.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});
  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontWeight: FontWeight.w500,
      color: AppTheme.ink,
      fontSize: 15,
    );
    final range = matchRange(query, text);
    if (range == null) {
      return Text(
        text,
        style: base.copyWith(fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, range.start)),
          TextSpan(
            text: text.substring(range.start, range.end),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: text.substring(range.end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
