import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../application/passport_service.dart';
import '../domain/passport_stamp.dart';
import 'stamp_view.dart';

/// Parchment behind the stamps.
const _paper = Color(0xFFF6EEDC);

/// `/passport-stamps`: one stamp per city where a counted trip reached a
/// place.
class PassportBookScreen extends ConsumerWidget {
  const PassportBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stampsAsync = ref.watch(passportStampsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Passport stamps')),
      body: stampsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          padding: AppSpacing.page,
          children: const [
            EmptyStateCard(
              icon: Icons.error_outline,
              title: 'Could not open your passport',
              message: 'Please try again in a moment.',
            ),
          ],
        ),
        data: (stamps) => stamps.isEmpty
            ? ListView(
                padding: AppSpacing.page,
                children: const [
                  EmptyStateCard(
                    icon: Icons.approval_outlined,
                    title: 'No stamps yet',
                    message:
                        'Reach a place on a trip (with the live photo) and '
                        'that city stamps your passport.',
                  ),
                ],
              )
            : ListView(
                padding: AppSpacing.page,
                children: [
                  Text(
                    '${stamps.length} ${stamps.length == 1 ? 'city' : 'cities'} '
                    'stamped',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _paper,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    // As many 180 px columns as fit: 2 on phones, more on
                    // tablets, so stamps never float in huge cells.
                    child: GridView.extent(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final stamp in stamps)
                          InkWell(
                            borderRadius: BorderRadius.circular(80),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _StampDetailScreen(stamp),
                              ),
                            ),
                            child: Center(
                              child: StampView(stamp: stamp, size: 140),
                            ),
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

class _StampDetailScreen extends StatefulWidget {
  const _StampDetailScreen(this.stamp);

  final PassportStamp stamp;

  @override
  State<_StampDetailScreen> createState() => _StampDetailScreenState();
}

class _StampDetailScreenState extends State<_StampDetailScreen> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not render the image.');

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'stamp-${widget.stamp.city.id}.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: 'My ${widget.stamp.city.name} stamp · explored with Tabi',
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create the image. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stamp = widget.stamp;
    return Scaffold(
      appBar: AppBar(title: Text(stamp.city.name)),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  StampView(stamp: stamp, size: 220),
                  const SizedBox(height: 16),
                  Text(
                    '${stamp.city.name}, ${stamp.city.state}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  Text(
                    'Stamped ${DateFormat.yMMMMd().format(stamp.earnedAt)} · '
                    '${stamp.serialLabel}',
                    style: const TextStyle(color: AppTheme.inkMuted),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tabi Explorer Passport',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title:
                '${stamp.placeNames.length} '
                '${stamp.placeNames.length == 1 ? 'place' : 'places'} reached',
          ),
          for (final name in stamp.placeNames)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(name),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sharing ? null : _share,
        backgroundColor: AppTheme.forest,
        foregroundColor: Colors.white,
        icon: _sharing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.ios_share),
        label: const Text('Share stamp'),
      ),
    );
  }
}
