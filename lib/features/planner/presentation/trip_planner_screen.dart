import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/ui/friendly_error.dart';
import '../../explore/presentation/widgets/city_picker_modal.dart';
import '../data/saved_trips_repository.dart';
import '../data/trip_planner_service.dart';
import '../domain/planner_input.dart';
import '../../preferences/application/preferences_service.dart';
import '../../preferences/domain/preference_mapping.dart';

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

  /// Bumped on every run and on Cancel: a result from an older run is
  /// dropped (not saved), so Cancel never leaves a stray trip behind.
  int _run = 0;

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
    _cityIdFor = widget.initialCityId == null
        ? null
        : widget.initialDestination;
    // Rebuild as the destination is typed (enables Plan, shows clear).
    _destinationCtrl.addListener(_onDestinationChanged);
    _applyPreferences();
  }

  /// Starts the form from the user's exploration preferences (who they go
  /// with, pace from difficulty, interests). Fields without a preference
  /// keep their defaults.
  Future<void> _applyPreferences() async {
    try {
      final prefs = await ref.read(userPreferencesProvider.future);
      if (!mounted) return;
      setState(() {
        _companion = companionFor(prefs) ?? _companion;
        _pace = paceFor(prefs) ?? _pace;
        final interests = plannerInterestsFor(prefs);
        if (interests != null) {
          _selectedInterests
            ..clear()
            ..addAll(interests);
        }
      });
    } catch (_) {
      // No saved preferences: keep the defaults.
    }
  }

  /// The destination text [_cityId] was picked for. If the user then types a
  /// different destination, the city no longer applies.
  String? _cityIdFor;

  /// [_cityId] if it still matches the destination [text], else null, so a
  /// plan is never grounded on a city the user has typed over.
  String? _cityIdMatching(String text) =>
      cityIdForDestination(cityId: _cityId, pickedFor: _cityIdFor, text: text);

  void _onDestinationChanged() => setState(() {});

  @override
  void dispose() {
    _destinationCtrl.removeListener(_onDestinationChanged);
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
        _cityIdFor = city.name;
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
    if (dest.isEmpty) return;

    final run = ++_run;
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final input = PlannerInput(
        destination: dest,
        cityId: _cityIdMatching(dest),
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
      // Each step has its own time limit; this is the last safety net so
      // the progress screen can never stay forever.
      final generated = await service
          .generatePlan(input)
          .timeout(const Duration(minutes: 3));
      if (!mounted || run != _run) return; // Cancelled.

      // Saved on this phone at once; backed up in the background when signed
      // in.
      final plan = await ref
          .read(savedTripsListProvider.notifier)
          .save(generated);

      if (!mounted) return;

      // Replace the form with the trip: Back then goes to where planning
      // started, and the form can't be submitted again by accident.
      context.pushReplacement('/trips/${plan.id}');
    } on TimeoutException {
      if (!mounted || run != _run) return;
      setState(() {
        _errorMessage =
            'This is taking too long. Check your internet connection and '
            'try again.';
      });
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _errorMessage = 'Couldn\'t plan this trip. ${friendlyError(e)}';
      });
    } finally {
      if (mounted && run == _run) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _cancelGeneration() => setState(() {
    _run++;
    _isGenerating = false;
  });

  /// One line for the collapsed "Tailor it" section.
  String get _tailorSummary => [
    _pace.label,
    _budget.label,
    if (_selectedInterests.isNotEmpty) _selectedInterests.join(', '),
    if (_originCtrl.text.trim().isNotEmpty) 'from ${_originCtrl.text.trim()}',
    if (_language == 'hi') 'हिंदी',
  ].join(' · ');

  void _back() {
    if (_isGenerating) {
      _cancelGeneration();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/trips');
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destinationCtrl.text.trim();
    return PopScope(
      // Back while planning cancels instead of leaving.
      canPop: !_isGenerating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelGeneration();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan a trip'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _back,
          ),
          actions: [
            if (!_isGenerating)
              AppIconButton(
                icon: Icons.luggage_outlined,
                tooltip: 'My trips',
                onPressed: () => context.go('/trips'),
              ),
          ],
        ),
        body: _isGenerating
            ? _PlanningProgress(
                destination: destination,
                onCancel: _cancelGeneration,
              )
            : _buildForm(context),
        bottomNavigationBar: _isGenerating
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: AppButton(
                    label: 'Plan my trip',
                    icon: Icons.auto_awesome,
                    expand: true,
                    onPressed: destination.isEmpty ? null : _generateItinerary,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.textSecondary);
    final dateFormat = DateFormat('EEE, d MMM');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (_errorMessage != null) ...[
          StatusBanner(
            kind: StatusKind.error,
            title: 'Trip not planned',
            message: _errorMessage,
            actionLabel: 'Try again',
            onAction: _generateItinerary,
          ),
          const SizedBox(height: 16),
        ],
        const _Label('Where to?'),
        TextField(
          controller: _destinationCtrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'A city or place in India',
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: _destinationCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () {
                      _destinationCtrl.clear();
                      _cityId = null;
                      _cityIdFor = null;
                    },
                  ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton.tertiary(
            label: 'Choose from popular cities',
            icon: Icons.travel_explore,
            onPressed: _pickCity,
          ),
        ),
        const SizedBox(height: 12),
        const _Label('How many days?'),
        Row(
          children: [
            AppIconButton(
              icon: Icons.remove_circle_outline,
              tooltip: 'Fewer days',
              onPressed: _daysCount > 1
                  ? () => setState(() => _daysCount--)
                  : null,
            ),
            SizedBox(
              width: 80,
              child: Text(
                '$_daysCount ${_daysCount == 1 ? 'day' : 'days'}',
                textAlign: TextAlign.center,
                style: text.titleMedium,
              ),
            ),
            AppIconButton(
              icon: Icons.add_circle_outline,
              tooltip: 'More days',
              onPressed: _daysCount < maxTripDays
                  ? () => setState(() => _daysCount++)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Label('When? (optional)'),
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                icon: Icons.event_outlined,
                label: _startDate == null
                    ? 'Pick a start date'
                    : '${dateFormat.format(_startDate!)} – '
                          '${dateFormat.format(_startDate!.add(Duration(days: _daysCount - 1)))}',
                onPressed: _pickStartDate,
              ),
            ),
            if (_startDate != null)
              AppIconButton(
                icon: Icons.clear,
                tooltip: 'Clear date',
                onPressed: () => setState(() => _startDate = null),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Dates add a weather forecast and a packing list.', style: muted),
        const SizedBox(height: 20),
        const _Label("Who's going?"),
        _Choices<TripCompanion>(
          values: TripCompanion.values,
          selected: _companion,
          label: (c) => c.label,
          description: (c) => c.description,
          onSelected: (c) => setState(() => _companion = c),
        ),
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('Tailor it', style: text.titleMedium),
            subtitle: Text(
              _tailorSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
            children: [
              const _Label('Pace'),
              _Choices<TripPace>(
                values: TripPace.values,
                selected: _pace,
                label: (p) => p.label,
                description: (p) => p.description,
                onSelected: (p) => setState(() => _pace = p),
              ),
              const SizedBox(height: 16),
              const _Label('Budget'),
              _Choices<TripBudget>(
                values: TripBudget.values,
                selected: _budget,
                label: (b) => b.label,
                description: (b) => b.description,
                onSelected: (b) => setState(() => _budget = b),
              ),
              const SizedBox(height: 16),
              const _Label('Interests'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final interest in _availableInterests)
                    FilterChip(
                      label: Text(interest),
                      selected: _selectedInterests.contains(interest),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _selectedInterests.add(interest);
                        } else {
                          _selectedInterests.remove(interest);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _Label('Travelling from (optional)'),
              TextField(
                controller: _originCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'e.g. New Delhi, Bengaluru',
                  prefixIcon: Icon(Icons.flight_takeoff),
                ),
              ),
              const SizedBox(height: 16),
              const _Label('Plan language'),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('English'),
                    selected: _language == 'en',
                    onSelected: (_) => setState(() => _language = 'en'),
                  ),
                  ChoiceChip(
                    label: const Text('हिंदी (Hindi)'),
                    selected: _language == 'hi',
                    onSelected: (_) => setState(() => _language = 'hi'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

/// The longest trip the planner makes.
const maxTripDays = 10;

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Single choice as chips, with the selected option's one-line description
/// underneath, so every group explains itself the same way.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.description,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final String Function(T) description;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          description(selected),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.of(context).textSecondary),
        ),
      ],
    );
  }
}

/// Full-screen progress while the plan is made (it can take a minute or
/// two): what's happening now, and Cancel.
class _PlanningProgress extends StatefulWidget {
  const _PlanningProgress({required this.destination, required this.onCancel});

  final String destination;
  final VoidCallback onCancel;

  @override
  State<_PlanningProgress> createState() => _PlanningProgressState();
}

class _PlanningProgressState extends State<_PlanningProgress> {
  static const _stepEvery = Duration(seconds: 6);
  late final Timer _timer;
  int _step = 0;

  List<String> get _steps => [
    'Finding the best places in ${widget.destination}…',
    'Checking opening hours…',
    'Working out routes between stops…',
    'Adding places to eat…',
    'Almost there…',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_stepEvery, (_) {
      if (_step < _steps.length - 1) setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              'Planning ${widget.destination}',
              textAlign: TextAlign.center,
              style: text.headlineSmall,
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: AppMotion.base,
                child: Text(
                  _steps[_step],
                  key: ValueKey(_step),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This can take a minute or two.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 32),
            AppButton.secondary(label: 'Cancel', onPressed: widget.onCancel),
          ],
        ),
      ),
    );
  }
}

/// The catalog city to plan around: [cityId] only while the destination
/// [text] still matches the name it was picked for ([pickedFor]), ignoring
/// case and surrounding spaces. Typing a different destination drops it, so
/// the plan isn't grounded on the old city.
String? cityIdForDestination({
  required String? cityId,
  required String? pickedFor,
  required String text,
}) {
  if (cityId == null || pickedFor == null) return null;
  return pickedFor.trim().toLowerCase() == text.trim().toLowerCase()
      ? cityId
      : null;
}
