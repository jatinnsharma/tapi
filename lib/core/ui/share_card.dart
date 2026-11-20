import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_components.dart';

/// Share cards are laid out at this width, so every phone exports the same
/// image (3× = 1080 px wide).
const shareCardWidth = 360.0;
const shareCardPixelRatio = 3.0;

/// Renders the [RepaintBoundary] under [boundaryKey] to a PNG and opens the
/// phone's share sheet with it. Throws if it can't render.
Future<void> shareBoundaryAsImage(
  GlobalKey boundaryKey, {
  required String fileName,
  String? text,
  String? subject,
  double pixelRatio = shareCardPixelRatio,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Could not render the image.');

  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
      subject: subject,
    ),
  );
}

/// The one way to share something as a picture: a preview of [card] at a
/// fixed width, **Share image** (the phone's share sheet) and, when
/// [copyText] is given, **Copy text**.
Future<void> showShareCardSheet(
  BuildContext context, {
  required String title,
  required Widget card,
  required String fileName,
  String? shareText,
  String? copyText,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ShareCardSheet(
      title: title,
      card: card,
      fileName: fileName,
      shareText: shareText,
      copyText: copyText,
    ),
  );
}

class _ShareCardSheet extends StatefulWidget {
  const _ShareCardSheet({
    required this.title,
    required this.card,
    required this.fileName,
    this.shareText,
    this.copyText,
  });

  final String title;
  final Widget card;
  final String fileName;
  final String? shareText;
  final String? copyText;

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;
  String? _error;

  Future<void> _share() async {
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      await shareBoundaryAsImage(
        _boundaryKey,
        fileName: widget.fileName,
        text: widget.shareText,
        subject: widget.title,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t create the image. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copyText!));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            // The card is laid out at a fixed width and scaled to fit the
            // phone, so the exported image is the same everywhere.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: shareCardWidth,
                child: RepaintBoundary(key: _boundaryKey, child: widget.card),
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: StatusBanner(kind: StatusKind.error, title: _error!),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                if (widget.copyText != null) ...[
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Copy text',
                      icon: Icons.copy_rounded,
                      onPressed: _copy,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: AppButton(
                    label: 'Share image',
                    icon: Icons.ios_share_rounded,
                    loading: _sharing,
                    onPressed: _share,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
