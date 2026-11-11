import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';

class CreatorModeScreen extends StatelessWidget {
  const CreatorModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Creator Mode')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          FadeSlideIn(
            child: HeroCard(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppTheme.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.monetization_on_rounded,
                      size: 36,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Monetize Your Routes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Turn your favourite routes into premium content. Earn royalties whenever other explorers purchase or subscribe to your routes.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  AmberPillButton(
                    label: 'Become a Creator',
                    icon: Icons.rocket_launch_rounded,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Creator payouts require Payment/Stripe Connect integration.',
                          ),
                        ),
                      );
                    },
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
