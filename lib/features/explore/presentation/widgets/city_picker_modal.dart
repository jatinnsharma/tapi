import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/city_repository.dart';
import '../../domain/city.dart';

Future<City?> showCityPickerModal(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<City>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _CityPickerSheet(),
  );
}

class _CityPickerSheet extends ConsumerStatefulWidget {
  const _CityPickerSheet();

  @override
  ConsumerState<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends ConsumerState<_CityPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<City> _cities = [];
  List<City> _filtered = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCities();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    final repo = ref.read(cityRepositoryProvider);
    final all = await repo.getCities();
    if (!mounted) return;
    setState(() {
      _cities = all;
      _filtered = all;
      _isLoading = false;
    });
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _cities;
      } else {
        _filtered = _cities.where((c) {
          return c.name.toLowerCase().contains(q) ||
              c.state.toLowerCase().contains(q) ||
              c.category.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Select City in India',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    ref.read(selectedCityProvider.notifier).clear();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Reset to GPS'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search city or state (e.g. Varanasi, Goa)...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.inkMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.cream,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? const Center(child: Text('No cities match your search'))
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final city = _filtered[index];
                      final isSelected =
                          ref.watch(selectedCityProvider)?.id == city.id;

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            city.imageUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 44,
                                  height: 44,
                                  color: AppTheme.sage,
                                  child: const Icon(
                                    Icons.location_city,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                          ),
                        ),
                        title: Text(
                          city.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected ? AppTheme.primary : AppTheme.ink,
                          ),
                        ),
                        subtitle: Text(
                          '${city.state} · ${city.category.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppTheme.primary,
                              )
                            : const Icon(
                                Icons.chevron_right,
                                color: AppTheme.inkMuted,
                                size: 20,
                              ),
                        onTap: () {
                          ref.read(selectedCityProvider.notifier).select(city);
                          Navigator.of(context).pop(city);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
