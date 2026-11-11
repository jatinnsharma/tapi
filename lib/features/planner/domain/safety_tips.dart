import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';

class IndiaSafetyInfo {
  const IndiaSafetyInfo({
    required this.title,
    required this.number,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String number;
  final String subtitle;
  final IconData icon;
}

const emergencyHelplines = [
  IndiaSafetyInfo(
    title: 'National Emergency',
    number: '112',
    subtitle:
        'All-in-one emergency service across India (Police, Fire, Medical)',
    icon: Icons.emergency_outlined,
  ),
  IndiaSafetyInfo(
    title: '24x7 Tourist Helpline',
    number: '1363',
    subtitle:
        'Toll-free multi-lingual tourist assistance by Ministry of Tourism',
    icon: Icons.support_agent_outlined,
  ),
  IndiaSafetyInfo(
    title: 'Women Helpline',
    number: '1091',
    subtitle: 'Dedicated 24x7 safety & support helpline for female travelers',
    icon: Icons.shield_outlined,
  ),
  IndiaSafetyInfo(
    title: 'Medical Ambulance',
    number: '108',
    subtitle: 'Free emergency medical ambulance response service',
    icon: Icons.medical_services_outlined,
  ),
];

const travelEtiquetteTips = [
  (
    'Spiritual & Temple Etiquette',
    'Remove footwear before entering temples, gurudwaras, or mosques. Cover shoulders and knees. Photography inside inner sanctums is often prohibited.',
    Icons.temple_buddhist_outlined,
  ),
  (
    'Hydration & Street Food',
    'Always drink packaged seal-checked water or filtered water. For street food, choose stalls with high local turnover where food is served piping hot.',
    Icons.water_drop_outlined,
  ),
  (
    'Transport & Local Bazaars',
    'Use app-based cabs (Uber/Ola) or prepaid taxi counters at airports and railway stations. In local markets, polite bargaining is normal and expected.',
    Icons.local_taxi_outlined,
  ),
  (
    'Best Seasons by Region',
    'Himalayas & Ladakh: May to October. Plains, Rajasthan & South India: October to March. Western Ghats & Monsoon: July to September.',
    Icons.calendar_today_outlined,
  ),
];

Future<void> showSafetyTipsModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _SafetyTipsSheet(),
  );
}

class _SafetyTipsSheet extends StatelessWidget {
  const _SafetyTipsSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                const Icon(Icons.security, color: AppTheme.forest, size: 24),
                const SizedBox(width: 10),
                const Text(
                  'India Travel & Safety Guide',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Emergency Helplines',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 10),
                ...emergencyHelplines.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.forest.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.icon,
                              color: AppTheme.forest,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.amber.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Dial ${item.number}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: AppTheme.amberText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppTheme.inkMuted,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                const Text(
                  'Local Travel Etiquette & Advice',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 10),
                ...travelEtiquetteTips.map((tip) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cream,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(tip.$3, color: AppTheme.primary, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tip.$1,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tip.$2,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.ink,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
