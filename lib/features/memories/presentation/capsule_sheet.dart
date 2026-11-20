import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/memories_api.dart';
import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_service.dart';
import '../data/shared_memory_service.dart';
import '../domain/memory_model.dart';
import '../domain/shared_memory.dart';
import 'voice_recorder_widget.dart';

/// Plays an audio capsule someone left, with a Report button.
Future<void> showCapsuleSheet(BuildContext context, SharedMemory capsule) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _CapsuleSheet(capsule),
  );
}

class _CapsuleSheet extends ConsumerStatefulWidget {
  const _CapsuleSheet(this.capsule);

  final SharedMemory capsule;

  @override
  ConsumerState<_CapsuleSheet> createState() => _CapsuleSheetState();
}

class _CapsuleSheetState extends ConsumerState<_CapsuleSheet> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    try {
      await _player.play(UrlSource(widget.capsule.url));
      setState(() => _playing = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play the capsule.')),
      );
    }
  }

  Future<void> _report() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sharedMemoryServiceProvider).report(widget.capsule.id);
      setState(() => _reported = true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks. We will review it.')),
      );
    } on SharingException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.capsule;
    final mine = ref.watch(authStateProvider).value?.uid == c.uid;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.headphones, color: AppTheme.forest),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.caption ?? 'Audio capsule',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Left here by ${c.displayName}',
              style: const TextStyle(color: AppTheme.inkMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'Pause' : 'Listen'),
              ),
            ),
            if (!mine)
              TextButton.icon(
                onPressed: _reported ? null : _report,
                icon: const Icon(Icons.flag_outlined),
                label: Text(_reported ? 'Reported' : 'Report this capsule'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Records a voice note here and leaves it as an audio capsule for
/// explorers who pass by. Explains (in a snack bar) when it can't.
Future<void> leaveAudioCapsule(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final user = ref.read(firebaseReadyProvider)
      ? ref.read(authStateProvider).value
      : null;
  if (user == null) return say('Sign in to leave audio capsules.');
  if (memoriesApiUrl.isEmpty) {
    return say("Audio capsules aren't available in this version yet.");
  }

  final note = await showVoiceRecorderSheet(context);
  if (note == null || !context.mounted) return;
  final details = await showDialog<({String caption, MemoryVisibility who})>(
    context: context,
    builder: (_) => const _CapsuleDetailsDialog(),
  );
  if (details == null) return;

  try {
    await ref
        .read(sharedMemoryServiceProvider)
        .leaveCapsule(
          memory: note,
          uid: user.uid,
          fallbackName: user.email?.split('@').first ?? 'Explorer',
          visibility: details.who,
          caption: details.caption.isEmpty ? null : details.caption,
        );
    say('Capsule left here. Explorers nearby will hear about it.');
  } on SharingException catch (e) {
    say(e.message);
  }
}

class _CapsuleDetailsDialog extends StatefulWidget {
  const _CapsuleDetailsDialog();

  @override
  State<_CapsuleDetailsDialog> createState() => _CapsuleDetailsDialogState();
}

class _CapsuleDetailsDialogState extends State<_CapsuleDetailsDialog> {
  final _caption = TextEditingController();
  MemoryVisibility _who = MemoryVisibility.public;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leave a capsule here'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _caption,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. The secret ghat of Assi',
            ),
          ),
          SegmentedButton<MemoryVisibility>(
            segments: const [
              ButtonSegment(
                value: MemoryVisibility.public,
                label: Text('Everyone'),
              ),
              ButtonSegment(
                value: MemoryVisibility.friends,
                label: Text('Friends'),
              ),
            ],
            selected: {_who},
            onSelectionChanged: (s) => setState(() => _who = s.single),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop((caption: _caption.text.trim(), who: _who)),
          child: const Text('Leave it'),
        ),
      ],
    );
  }
}
