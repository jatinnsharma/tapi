import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';

class TransportOption {
  final String id;
  final String providerName;
  final String routeName;
  final String vehicleType;
  final double fare;
  final String departureTime;
  final double rating;

  const TransportOption({
    required this.id,
    required this.providerName,
    required this.routeName,
    required this.vehicleType,
    required this.fare,
    required this.departureTime,
    required this.rating,
  });
}

final _mockTransport = [
  TransportOption(
    id: 't1',
    providerName: 'Mountain Express',
    routeName: 'City Center to Sunrise Peak Trailhead',
    vehicleType: '4x4 Jeep',
    fare: 12.0,
    departureTime: '6:00 AM',
    rating: 4.6,
  ),
  TransportOption(
    id: 't2',
    providerName: 'Valley Shuttles',
    routeName: 'City Center to Lower Falls Base',
    vehicleType: 'Minibus',
    fare: 5.0,
    departureTime: 'Hourly (8 AM - 4 PM)',
    rating: 4.2,
  ),
];

class TransportScreen extends StatelessWidget {
  const TransportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transport')),
      body: ListView.builder(
        padding: AppSpacing.page,
        itemCount: _mockTransport.length,
        itemBuilder: (context, index) {
          final option = _mockTransport[index];
          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: SoftCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF5CC4B2), Color(0xFF1E7A73)],
                          ),
                        ),
                        child: const Icon(
                          Icons.directions_bus_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          option.routeName,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '\$${option.fare.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _MetaItem(
                        icon: Icons.local_shipping_rounded,
                        text: option.vehicleType,
                      ),
                      _MetaItem(
                        icon: Icons.schedule_rounded,
                        text: option.departureTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: AppTheme.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${option.rating} • ${option.providerName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Booking requires Payment setup.'),
                            ),
                          );
                        },
                        child: const Text('Book Ticket'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryGreen),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}
