import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';

class EcosystemScreen extends StatelessWidget {
  const EcosystemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <_FeatureTile>[
      _FeatureTile(
        title: 'Local Guides',
        subtitle: 'Hire verified local experts for your next adventure',
        icon: Icons.person_pin_rounded,
        gradient: const [Color(0xFF8FA8E8), Color(0xFF3E4A9A)],
        onTap: () => context.go('/ecosystem/guides'),
      ),
      _FeatureTile(
        title: 'Events & Meetups',
        subtitle: 'Join community events and group treks',
        icon: Icons.event_rounded,
        gradient: const [Color(0xFFE59A78), Color(0xFFA9492F)],
        onTap: () => context.go('/ecosystem/events'),
      ),
      _FeatureTile(
        title: 'Gear Rental',
        subtitle: 'Rent tents, sleeping bags, and trekking poles',
        icon: Icons.backpack_rounded,
        gradient: const [Color(0xFFF7B267), Color(0xFFE8743B)],
        onTap: () => context.go('/ecosystem/gear'),
      ),
      _FeatureTile(
        title: 'Accommodation',
        subtitle: 'Book campsites, homestays, and lodges',
        icon: Icons.house_rounded,
        gradient: const [Color(0xFF1E8F5F), Color(0xFF0F3D2B)],
        onTap: () => context.go('/ecosystem/accommodation'),
      ),
      _FeatureTile(
        title: 'Transport',
        subtitle: 'Arrange shuttles to trailheads',
        icon: Icons.directions_bus_rounded,
        gradient: const [Color(0xFF5CC4B2), Color(0xFF1E7A73)],
        onTap: () => context.go('/ecosystem/transport'),
      ),
      _FeatureTile(
        title: 'Creator Mode',
        subtitle: 'Monetize your routes and earn rewards',
        icon: Icons.monetization_on_rounded,
        gradient: const [Color(0xFFFFD27A), AppTheme.amber],
        onTap: () => context.go('/ecosystem/creator-mode'),
      ),
      _FeatureTile(
        title: 'Explorer Rewards',
        subtitle: 'Redeem your earned points',
        icon: Icons.card_giftcard_rounded,
        gradient: const [Color(0xFFE88FA8), Color(0xFFA43A5C)],
        onTap: () => context.go('/ecosystem/rewards'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Ecosystem & Marketplace')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          FadeSlideIn(
            child: HeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MetaPill(
                    label: 'Marketplace',
                    icon: Icons.storefront_rounded,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Everything for your next trail',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Guides, gear, stays, rides and rewards, all in one place.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          const SectionHeader(
            title: 'Explore',
            padding: EdgeInsets.only(top: 22, bottom: 12),
          ),
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FadeSlideIn(
                delay: Duration(milliseconds: 60 + i * 40),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tiles[i]),
                      const SizedBox(width: 14),
                      Expanded(
                        child: i + 1 < tiles.length
                            ? tiles[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: SoftCard(
        radius: 26,
        padding: const EdgeInsets.all(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
