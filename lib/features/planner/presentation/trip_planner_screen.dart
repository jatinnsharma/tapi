import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../explore/presentation/widgets/city_picker_modal.dart';
import '../data/saved_trips_repository.dart';
import '../data/trip_planner_service.dart';
import '../domain/planner_input.dart';
import '../domain/safety_tips.dart';
import 'itinerary_detail_screen.dart';

class TripPlannerScreen extends ConsumerStatefulWidget {
  const TripPlannerScreen({
    super.key,
    this.initialDestination,
    this.initialCityId,
  });

  final String? initialDestination;
  final String? initialCityId;

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  late final TextEditingController _destinationCtrl;
  final TextEditingController _originCtrl = TextEditingController();
  String? _cityId;

  int _daysCount = 3;
  TripCompanion _companion = TripCompanion.friends;
  TripPace _pace = TripPace.moderate;
  TripBudget _budget = TripBudget.moderate;
  final Set<String> _selectedInterests = {'Heritage', 'Street Food'};
  String _language = 'en'; // 'en' or 'hi'
  DateTime? _startDate;

  bool _isGenerating = false;
  String? _errorMessage;

  static const _availableInterests = [
    'Heritage',
    'Spiritual',
    'Street Food',
    'Nature & Views',
    'Photography',
    'Local Bazaars',
    'Cafes',
    'Adventure',
  ];

  @override
  void initState() {
    super.initState();
    _destinationCtrl = TextEditingController(
      text: widget.initialDestination ?? '',
    );
    _cityId = widget.initialCityId;
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _originCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCity() async {
    final city = await showCityPickerModal(context, ref);
    if (city != null) {
      setState(() {
        _destinationCtrl.text = city.name;
        _cityId = city.id;
      });
    }
  }

  Future<void> _pickStartDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      helpText: 'First day of the trip',
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _generateItinerary() async {
    final dest = _destinationCtrl.text.trim();
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination in India')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final input = PlannerInput(
        destination: dest,
        cityId: _cityId,
        daysCount: _daysCount,
        companion: _companion,
        pace: _pace,
        budget: _budget,
        interests: _selectedInterests.toList(),
        travelingFrom: _originCtrl.text.trim().isEmpty
            ? null
            : _originCtrl.text.trim(),
        language: _language,
        startDate: _startDate,
      );

      final service = ref.read(tripPlannerServiceProvider);
      // Each step has its own time limit; this is the last safety net so the
      // button can never spin forever.
      final generated = await service
          .generatePlan(input)
          .timeout(const Duration(minutes: 3));

      // Saved on this phone at once; backed up in the background when signed
      // in.
      final plan = await ref
          .read(savedTripsListProvider.notifier)
          .save(generated);

      if (!mounted) return;

      // Navigate to Itinerary Detail Screen
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ItineraryDetailScreen(plan: plan),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'This is taking too long. Check your internet connection and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not generate itinerary. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Trip Planner'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/explore');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Safety & Helplines',
            onPressed: () => showSafetyTipsModal(context),
          ),
          TextButton.icon(
            icon: const Icon(Icons.bookmark_outline, size: 20),
            label: const Text('My Trips'),
            onPressed: () => context.push('/my-trips'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Hero Intro Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppTheme.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.forest.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: AppTheme.amber, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'India Itinerary Generator',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Personalized day-by-day plans grounded in real landmarks, authentic eateries, and step-by-step maps.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Destination Input
            const Text(
              'Destination',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _destinationCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Varanasi, Manali, Jaipur, Goa',
                      prefixIcon: const Icon(
                        Icons.location_on,
                        color: AppTheme.primary,
                      ),
                      suffixIcon: _destinationCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() {
                                  _destinationCtrl.clear();
                                  _cityId = null;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.travel_explore),
                  tooltip: 'Pick from 165 Indian cities',
                  onPressed: _pickCity,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Number of days
            const Text(
              'Trip Duration',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [1, 2, 3, 4, 5, 7, 10].map((days) {
                  final isSelected = _daysCount == days;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$days ${days == 1 ? 'Day' : 'Days'}'),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _daysCount = days),
                      selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                      labelStyle: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected ? AppTheme.forest : AppTheme.ink,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Travel dates
            const Text(
              'When Are You Going? (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _startDate == null
                          ? 'Pick a start date'
                          : '${DateFormat('EEE, d MMM').format(_startDate!)} – '
                                '${DateFormat('EEE, d MMM').format(_startDate!.add(Duration(days: _daysCount - 1)))}',
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _pickStartDate,
                  ),
                ),
                if (_startDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear date',
                    onPressed: () => setState(() => _startDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Dates add a weather forecast and a packing list for the season.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkMuted),
            ),
            const SizedBox(height: 20),

            // Who's going
            const Text(
              "Who's Going?",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TripCompanion.values.map((c) {
                final isSelected = _companion == c;
                return ChoiceChip(
                  label: Text('${c.label} · ${c.description}'),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _companion = c),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? AppTheme.forest : AppTheme.ink,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Trip Pace
            const Text(
              'Pacing',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: TripPace.values.map((p) {
                final isSelected = _pace == p;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Center(
                        child: Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected ? AppTheme.forest : AppTheme.ink,
                          ),
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _pace = p),
                      selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Budget
            const Text(
              'Budget',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: TripBudget.values.map((b) {
                final isSelected = _budget == b;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Center(
                        child: Text(
                          b.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected ? AppTheme.forest : AppTheme.ink,
                          ),
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _budget = b),
                      selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Interests
            const Text(
              'Interests & Focus',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableInterests.map((interest) {
                final isSelected = _selectedInterests.contains(interest);
                return FilterChip(
                  label: Text(interest),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedInterests.add(interest);
                      } else {
                        _selectedInterests.remove(interest);
                      }
                    });
                  },
                  selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                  checkmarkColor: AppTheme.forest,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? AppTheme.forest : AppTheme.ink,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Optional Starting city
            const Text(
              'Traveling From (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _originCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. New Delhi, Bengaluru, Chandigarh',
                prefixIcon: Icon(
                  Icons.flight_takeoff,
                  color: AppTheme.inkMuted,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Language Selection (Task 19)
            const Text(
              'Itinerary Language',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('English'),
                  selected: _language == 'en',
                  onSelected: (_) => setState(() => _language = 'en'),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('हिंदी (Hindi)'),
                  selected: _language == 'hi',
                  onSelected: (_) => setState(() => _language = 'hi'),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                ),
              ],
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Generate Button
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateItinerary,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 22),
                label: Text(
                  _isGenerating
                      ? 'Crafting Your India Itinerary...'
                      : 'Generate Itinerary',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.forest,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
