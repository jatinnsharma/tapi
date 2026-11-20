import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../data/offline_pack_store.dart';
import '../domain/tile_math.dart';

/// "Download offline map" for a city: estimate first, then progress, then
/// ready (with Delete). Hidden when offline maps aren't set up (no key).
class OfflinePackCard extends StatefulWidget {
  const OfflinePackCard({
    super.key,
    required this.cityId,
    required this.cityName,
    required this.center,
    this.store,
  });

  final String cityId;
  final String cityName;
  final LatLng center;

  /// For tests; the shared store otherwise.
  final OfflinePackStore? store;

  @override
  State<OfflinePackCard> createState() => _OfflinePackCardState();
}

class _OfflinePackCardState extends State<OfflinePackCard> {
  OfflinePackStore get _store => widget.store ?? OfflinePackStore.instance;

  PackInfo? _pack;
  PackProgress? _progress;
  bool _cancel = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_store.available) _refresh();
  }

  Future<void> _refresh() async {
    final pack = await _store.info(widget.cityId);
    if (mounted) setState(() => _pack = pack);
  }

  Future<void> _download() async {
    setState(() {
      _cancel = false;
      _error = null;
      _progress = (done: 0, total: 1);
    });
    try {
      await for (final p in _store.download(
        cityId: widget.cityId,
        cityName: widget.cityName,
        center: widget.center,
        cancelled: () => _cancel,
      )) {
        if (mounted) setState(() => _progress = p);
      }
    } on PackStorageFullException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (_) {
      if (mounted) setState(() => _error = 'The download stopped. Try again.');
    }
    if (mounted) setState(() => _progress = null);
    await _refresh();
  }

  Future<void> _delete() async {
    await _store.delete(widget.cityId);
    await _refresh();
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).ceil()} MB';

  @override
  Widget build(BuildContext context) {
    if (!_store.available) return const SizedBox.shrink();
    final pack = _pack;
    final progress = _progress;

    final Widget body;
    if (progress != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Downloading the map of ${widget.cityName}… '
            '${progress.done} of ${progress.total} tiles',
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.total == 0 ? null : progress.done / progress.total,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _cancel = true),
              child: const Text('Stop'),
            ),
          ),
        ],
      );
    } else if (pack != null && pack.complete) {
      body = Row(
        children: [
          const Icon(Icons.offline_pin, color: AppTheme.forest),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline map ready · ${_mb(pack.bytes)}\n'
              'Used when there is no signal.',
            ),
          ),
          TextButton(onPressed: _delete, child: const Text('Delete')),
        ],
      );
    } else {
      final estimate = packTiles(widget.center).length * averageTileBytes;
      body = Row(
        children: [
          const Icon(Icons.download_for_offline_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pack == null
                  ? 'Offline map of ${widget.cityName} · about ${_mb(estimate)}'
                  : 'Offline map partly downloaded '
                        '(${pack.tileCount} of ${pack.totalTiles} tiles)',
            ),
          ),
          FilledButton(
            onPressed: _download,
            child: Text(pack == null ? 'Download' : 'Resume'),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
