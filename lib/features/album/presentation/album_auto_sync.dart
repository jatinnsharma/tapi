import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/album_uploader.dart';

/// Resumes album uploads when the app starts and whenever it comes back to
/// the foreground, so photos taken offline go up once there's a connection.
class AlbumAutoSync extends ConsumerStatefulWidget {
  const AlbumAutoSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AlbumAutoSync> createState() => _AlbumAutoSyncState();
}

class _AlbumAutoSyncState extends ConsumerState<AlbumAutoSync> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _drain);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  void _drain() {
    // Best effort: the queue keeps anything that fails for the next time.
    ref.read(albumUploaderProvider).drain().catchError((Object _) {});
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
