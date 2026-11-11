import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../domain/event.dart';

final _mockEvents = [
  EcosystemEvent(
    id: 'e1',
    title: 'Sunrise Peak Group Climb',
    description: 'Join 20 other enthusiasts for a guided morning ascent of Sunrise Peak. Gear provided.',
    date: DateTime.now().add(const Duration(days: 3)),
    locationName: 'Sunrise Peak Base Camp',
    imageUrl: 'https://images.unsplash.com/photo-1522345229156-f0891d4e0e4f?auto=format&fit=crop&w=600&q=80',
    currentAttendees: 15,
    maxAttendees: 20,
    price: 45.0,
    organizerName: 'Himalayan Guides',
  ),
  EcosystemEvent(
    id: 'e2',
    title: 'Heritage Photography Walk',
    description: 'A slow-paced walk through the old city focusing on architecture and street photography.',
    date: DateTime.now().add(const Duration(days: 7)),
    locationName: 'Old City Gates',
    imageUrl: 'https://images.unsplash.com/photo-1516394468694-8ee770a84e3d?auto=format&fit=crop&w=600&q=80',
    currentAttendees: 8,
    maxAttendees: 15,
    price: 25.0,
    organizerName: 'Culture Treks',
  ),
];

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events & Meetups')),
      body: ListView.builder(
        padding: AppSpacing.page,
        itemCount: _mockEvents.length,
        itemBuilder: (context, index) {
          final event = _mockEvents[index];
          final isFull = event.currentAttendees >= event.maxAttendees;
          final fill = event.maxAttendees == 0
              ? 0.0
              : (event.currentAttendees / event.maxAttendees).clamp(0.0, 1.0);

          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: SoftCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: EdgeInsets.zero,
              radius: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            event.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFE59A78),
                                    Color(0xFFA9492F),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.event_rounded,
                                color: Colors.white70,
                                size: 40,
                              ),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0x80061A12)],
                                stops: [0.4, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: MetaPill(
                              label: DateFormat('MMM d').format(event.date),
                              icon: Icons.calendar_today_rounded,
                              background: AppTheme.forest.withValues(
                                alpha: 0.78,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: MetaPill(
                              label: '\$${event.price.toStringAsFixed(0)}',
                              background: AppTheme.amber,
                              foreground: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _MetaLine(
                          icon: Icons.schedule_rounded,
                          text: DateFormat('MMM d, yyyy • h:mm a')
                              .format(event.date),
                        ),
                        const SizedBox(height: 4),
                        _MetaLine(
                          icon: Icons.location_on_rounded,
                          text: event.locationName,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          event.description,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${event.currentAttendees}/${event.maxAttendees} joined',
                              style: TextStyle(
                                color: isFull
                                    ? Colors.red.shade700
                                    : AppTheme.primaryGreen,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'By ${event.organizerName}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: fill,
                            minHeight: 8,
                            backgroundColor: AppTheme.primaryGreen.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              isFull ? Colors.red.shade400 : AppTheme.amber,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: isFull
                                ? null
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Registration requires Payment setup.',
                                        ),
                                      ),
                                    );
                                  },
                            child: Text(isFull ? 'Event Full' : 'Register Now'),
                          ),
                        ),
                      ],
                    ),
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

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryGreen),
        const SizedBox(width: 6),
        Expanded(
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
