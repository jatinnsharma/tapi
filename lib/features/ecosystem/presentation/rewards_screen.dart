import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explorer Rewards')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          FadeSlideIn(
            child: HeroCard(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MetaPill(
                    label: 'Your Balance',
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: AppTheme.amber,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.toll_rounded,
                          color: AppTheme.ink,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '1,250',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 50,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Explorer Coins',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader(
            title: 'Redeem Rewards',
            padding: EdgeInsets.only(top: 24, bottom: 12),
          ),
          const _RewardItem(
            title: '10% off Next Gear Rental',
            cost: 500,
            icon: Icons.backpack_rounded,
            gradient: [Color(0xFFF7B267), Color(0xFFE8743B)],
          ),
          const _RewardItem(
            title: 'Free Trail Shuttle Pass',
            cost: 1200,
            icon: Icons.directions_bus_rounded,
            gradient: [Color(0xFF5CC4B2), Color(0xFF1E7A73)],
          ),
          const _RewardItem(
            title: '\$20 Guide Discount',
            cost: 2000,
            icon: Icons.person_rounded,
            gradient: [Color(0xFF8FA8E8), Color(0xFF3E4A9A)],
          ),
          const _RewardItem(
            title: 'Premium App Badge',
            cost: 3000,
            icon: Icons.military_tech_rounded,
            gradient: [Color(0xFF1E8F5F), AppTheme.forest],
          ),
        ],
      ),
    );
  }
}

class _RewardItem extends StatelessWidget {
  const _RewardItem({
    required this.title,
    required this.cost,
    required this.icon,
    required this.gradient,
  });

  final String title;
  final int cost;
  final IconData icon;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.toll_rounded,
                      size: 15,
                      color: AppTheme.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$cost Coins',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.amberText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rewards redemption coming soon.'),
                ),
              );
            },
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
  }
}
