import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../application/emergency_service.dart';

/// How long SOS must be held, so a pocket or a stray tap can't send it.
const sosHoldDuration = Duration(seconds: 2);

/// A red SOS button that sends the alert after being held for
/// [sosHoldDuration]. A ring fills while it is held; letting go early
/// cancels.
class SosHoldButton extends ConsumerStatefulWidget {
  const SosHoldButton({super.key, this.size = 132});

  final double size;

  @override
  ConsumerState<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends ConsumerState<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: sosHoldDuration,
  )..addStatusListener(_onStatus);

  bool _sending = false;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    HapticFeedback.heavyImpact();
    _hold.reset();
    _send();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await sendSos(context, ref);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      button: true,
      label:
          'SOS. Press and hold for 2 seconds to alert your emergency '
          'contacts.',
      onLongPress: _send,
      child: GestureDetector(
        onLongPressStart: (_) {
          if (_sending) return;
          HapticFeedback.mediumImpact();
          _hold.forward(from: 0);
        },
        onLongPressEnd: (_) {
          if (!_hold.isCompleted) _hold.reverse();
        },
        onLongPressCancel: () => _hold.reverse(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _hold,
                builder: (context, _) => SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    value: _hold.value,
                    strokeWidth: 6,
                    color: Colors.red.shade900,
                    backgroundColor: Colors.red.withValues(alpha: 0.18),
                  ),
                ),
              ),
              Container(
                width: size - 20,
                height: size - 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.shade700,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _sending
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'Hold 2 s',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds the SOS message with the best location the phone has, then opens
/// the SMS app addressed to every emergency contact. With no contacts (or no
/// SMS app), offers to share the message another way or call 112.
Future<void> sendSos(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  // A position from the last few minutes is good enough and comes at once;
  // otherwise a fresh fix is tried for up to 10 s.
  final position = await ref
      .read(locationServiceProvider)
      .getCurrentLocation(acceptRecent: true);
  final message = sosMessage(position: position, now: now, fixTime: now);
  final contacts = await ref.read(emergencyContactsProvider.future);
  if (!context.mounted) return;

  if (contacts.isNotEmpty) {
    final opened = await launchUrl(
      sosSmsUri([for (final c in contacts) c.phone], message),
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
    if (opened) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) =>
        _SosFallbackSheet(message: message, hasContacts: contacts.isNotEmpty),
  );
}

class _SosFallbackSheet extends StatelessWidget {
  const _SosFallbackSheet({required this.message, required this.hasContacts});

  final String message;
  final bool hasContacts;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasContacts
                  ? 'Could not open your messages app'
                  : 'No emergency contacts yet',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: AppTheme.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => launchUrl(dialUri('112')),
              icon: const Icon(Icons.call),
              label: const Text('Call 112'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: message, subject: 'Emergency'),
              ),
              icon: const Icon(Icons.share),
              label: const Text('Send the message another way'),
            ),
            if (!hasContacts) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/safety');
                },
                child: const Text('Add emergency contacts'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
