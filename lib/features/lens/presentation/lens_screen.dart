import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../data/lens_service.dart';
import '../domain/lens_answer.dart';

/// Opens the Sightseer Lens, optionally near a named place.
Future<void> showLens(BuildContext context, {String? near}) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => LensScreen(near: near)));
}

/// "What am I looking at?": photograph a monument, carving or inscription
/// and get what it is, its story and details to look for, read aloud on
/// request.
class LensScreen extends ConsumerStatefulWidget {
  const LensScreen({super.key, this.near});

  /// The place the user is at, to help identify the photo.
  final String? near;

  @override
  ConsumerState<LensScreen> createState() => _LensScreenState();
}

class _LensScreenState extends ConsumerState<LensScreen> {
  final _tts = FlutterTts();
  Uint8List? _photo;
  LensAnswer? _answer;
  String? _error;
  bool _working = false;
  bool _speaking = false;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _snap() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _photo = bytes;
      _answer = null;
      _error = null;
      _working = true;
    });
    try {
      final here = await ref
          .read(locationServiceProvider)
          .getCurrentLocation(acceptRecent: true);
      final answer = await ref
          .read(lensServiceProvider)
          .identify(
            bytes,
            latitude: here?.latitude,
            longitude: here?.longitude,
            near: widget.near,
          );
      if (mounted) setState(() => _answer = answer);
    } on LensException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _listen(LensAnswer answer) async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    await _tts.setLanguage('en-IN');
    await _tts.speak(answer.narration);
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return Scaffold(
      appBar: AppBar(title: const Text('Sightseer Lens')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(_photo!, height: 240, fit: BoxFit.cover),
            )
          else
            const EmptyStateCard(
              icon: Icons.center_focus_strong_outlined,
              title: 'What am I looking at?',
              message:
                  'Photograph a monument, carving, painting or inscription. '
                  'The lens tells you what it is, its story, and what to look '
                  'for.',
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working ? null : _snap,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_photo == null ? 'Take a photo' : 'Try another'),
          ),
          const SizedBox(height: 16),
          if (_working) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (answer != null) ...[
            Text(
              answer.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            if (answer.style != null || answer.era != null)
              Text(
                [?answer.style, ?answer.era].join(' · '),
                style: const TextStyle(color: AppTheme.inkMuted),
              ),
            if (answer.isUnsure)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Not sure about this one: treat it as a guess.',
                  style: TextStyle(
                    color: AppTheme.amberText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(answer.summary, style: const TextStyle(height: 1.45)),
            if (answer.details.isNotEmpty) ...[
              const SectionHeader(
                title: 'Look for',
                padding: EdgeInsets.only(top: 18, bottom: 8),
              ),
              for (final d in answer.details)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.search, color: AppTheme.forest),
                  title: Text(d),
                ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _listen(answer),
              icon: Icon(_speaking ? Icons.stop : Icons.volume_up_outlined),
              label: Text(_speaking ? 'Stop' : 'Listen'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Identified by AI from your photo; it can be wrong.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
