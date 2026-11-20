import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../application/onboarding_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      icon: Icons.explore_rounded,
      iconColor: AppTheme.primaryGreen,
      title: 'Welcome to Tabi',
      subtitle: 'Turn every step into an adventure',
      description: 'Discover hidden gardens, scenic walking trails, local markets, and heritage viewpoints across India. Step outside and explore wherever you are on foot.',
    ),
    _OnboardingPageData(
      icon: Icons.camera_alt_rounded,
      iconColor: AppTheme.amberText,
      title: 'How XP Works',
      subtitle: 'Real walking & authentic visits',
      description: 'Earn XP by walking genuine distances to real places. When you arrive, snap a live camera photo at the location to verify your visit, level up your rank, and collect badges.',
    ),
    _OnboardingPageData(
      icon: Icons.location_on_rounded,
      iconColor: AppTheme.emerald,
      title: 'Why Location Matters',
      subtitle: 'Private, local GPS tracking',
      description: 'Tabi uses your location while exploring to trace your walking path, reveal undiscovered places nearby, and verify your place check-ins. Your trip routes stay private on your phone.',
    ),
  ];

  bool _finishing = false;

  /// Ends onboarding. Location is asked only when the user finished the
  /// explanation ([askLocation]); "Skip" means "not now", so it doesn't
  /// spring the system prompt on them (the app asks again when it needs it).
  /// A second tap while finishing is ignored, and a failed permission
  /// request never leaves the user stuck here.
  Future<void> _finishOnboarding({bool askLocation = true}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(onboardingCompletedProvider.notifier).completeOnboarding();
    if (askLocation) {
      try {
        await ref.read(locationServiceProvider).requestPermission();
      } catch (_) {
        // The app asks again where it needs location.
      }
    }
    if (mounted) context.go('/explore');
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final last = _currentPage == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextButton(
                  onPressed: _finishing
                      ? null
                      : () => _finishOnboarding(askLocation: false),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  // Scrolls on small phones with large text instead of
                  // overflowing.
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: page.iconColor.withValues(alpha: 0.12),
                            ),
                            child: Icon(
                              page.icon,
                              size: 68,
                              color: page.iconColor,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Semantics(
                            header: true,
                            child: Text(
                              page.title,
                              textAlign: TextAlign.center,
                              style: text.headlineMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            page.subtitle,
                            textAlign: TextAlign.center,
                            style: text.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            page.description,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
              child: Column(
                children: [
                  Semantics(
                    label: 'Page ${_currentPage + 1} of ${_pages.length}',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: AppMotion.base,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? Theme.of(context).colorScheme.primary
                                : colors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: last
                        ? 'Enable Location & Start Exploring'
                        : 'Continue',
                    expand: true,
                    loading: _finishing,
                    onPressed: _nextPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;
}
