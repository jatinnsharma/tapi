import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/google_drive.dart';
import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/media_shell.dart';
import '../../../core/ui/confirm_destructive.dart';
import '../../../core/ui/friendly_error.dart';
import '../../auth/application/auth_service.dart';
import '../../memories/data/memory_repository.dart';
import '../../memories/domain/memory_model.dart';
import '../../memories/presentation/camera_screen.dart';
import '../../planner/data/saved_trips_repository.dart';
import '../../planner/domain/trip_plan.dart';
import '../application/album_uploader.dart';
import '../data/album_cloud_repository.dart';
import '../data/album_queue_repository.dart';
import '../data/drive_auth.dart';
import '../domain/album_item.dart';
import '../domain/album_photo.dart';
import 'share_trip_photos_sheet.dart';

/// A trip's shared album: everyone's photos, with who took them and when,
/// and where when the uploader chose to show it. Your own photos show their
/// upload status (On this phone / Waiting / Uploading / Shared / Failed).
class TripAlbumScreen extends ConsumerStatefulWidget {
  const TripAlbumScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripAlbumScreen> createState() => _TripAlbumScreenState();
}

class _TripAlbumScreenState extends ConsumerState<TripAlbumScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _drain();
    // While the album is open, keep trying (retries become due).
    _tick = Timer.periodic(const Duration(seconds: 45), (_) => _drain());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _drain() =>
      ref.read(albumUploaderProvider).drain().catchError((Object _) {});

  Future<void> _connectDrive() async {
    try {
      await ref.read(driveAuthProvider).token(interactive: true);
      ref.invalidate(driveConnectedProvider);
      _drain();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t connect Google Drive. ${friendlyError(e)}'),
        ),
      );
    }
  }

  Future<void> _addPhotos() async {
    final picked = await showModalBottomSheet<_AddChoice>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _AddSheet(),
    );
    if (picked == null || !mounted) return;
    final uploader = ref.read(albumUploaderProvider);
    var memories = <Memory>[];
    if (picked.camera) {
      final shot = await Navigator.of(
        context,
      ).push<Memory>(MaterialPageRoute(builder: (_) => const CameraScreen()));
      if (shot != null) memories = [shot];
    } else {
      memories =
          await showModalBottomSheet<List<Memory>>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => const _MemoryPicker(),
          ) ??
          const [];
    }
    for (final m in memories) {
      await uploader.add(
        tripId: widget.tripId,
        memoryId: m.id,
        filePath: m.filePath,
        takenAt: m.timestamp,
        latitude: m.latitude,
        longitude: m.longitude,
        includeLocation: picked.includeLocation,
      );
    }
    if (memories.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${memories.length} '
            '${memories.length == 1 ? 'photo' : 'photos'} added to the album',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(savedTripsListProvider).value;
    final plan = trips?.where((t) => t.id == widget.tripId).firstOrNull;
    if (trips != null && plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: GateCard(
          icon: Icons.photo_library_outlined,
          title: 'Trip not found',
          message: 'It may have been deleted, or its owner stopped sharing it.',
          actionLabel: 'Go to Trips',
          onAction: () => context.go('/trips'),
        ),
      );
    }

    final mine = ref.watch(tripQueueProvider(widget.tripId)).value ?? const [];
    final shared = plan?.cloudSynced == true
        ? ref.watch(sharedAlbumProvider(widget.tripId)).value ?? const []
        : const <AlbumPhoto>[];
    final items = mergeAlbum(shared: shared, mine: mine);
    final summary = queueSummary(mine);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(plan == null ? 'Album' : '${plan.title} album'),
        actions: [
          AppIconButton(
            icon: Icons.ios_share_rounded,
            tooltip: 'Share photos',
            onPressed: plan == null
                ? null
                : () => showShareTripPhotosSheet(
                    context,
                    tripTitle: plan.title,
                    photos: mine,
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPhotos,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add photos'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (plan != null) _AlbumStatus(plan: plan, onConnect: _connectDrive),
          if (summary != null) ...[
            const SizedBox(height: 8),
            Text(
              summary,
              style: text.labelLarge?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'No photos yet. Add some, and everyone on the trip will see '
                'them here.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _AlbumTile(
                  item: items[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlbumPhotoViewer(
                        item: items[i],
                        tripId: widget.tripId,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line on where the album stands: on this phone only, Drive to
/// connect, or shared with the trip.
class _AlbumStatus extends ConsumerWidget {
  const _AlbumStatus({required this.plan, required this.onConnect});

  final TripPlan plan;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(driveConfiguredProvider) ||
        !ref.watch(firebaseReadyProvider)) {
      return const StatusBanner(
        kind: StatusKind.info,
        title: 'Album on this phone',
        message:
            'Shared albums aren\'t set up in this version. Your photos stay '
            'on this phone, and you can still share them.',
      );
    }
    if (ref.watch(authStateProvider).value == null) {
      return StatusBanner(
        kind: StatusKind.info,
        title: 'Sign in to share the album',
        message: 'Your photos stay on this phone until you sign in.',
        actionLabel: 'Sign in',
        onAction: () => context.push('/login'),
      );
    }
    if (!plan.cloudSynced) {
      return const StatusBanner(
        kind: StatusKind.info,
        title: 'Waiting for the trip to back up',
        message: 'Photos upload once this trip is saved to your account.',
      );
    }
    final connection = ref.watch(driveConnectedProvider);
    // Still checking: say nothing rather than flash "Connect".
    if (!connection.hasValue) return const SizedBox.shrink();
    if (connection.value != true) {
      return StatusBanner(
        kind: StatusKind.warning,
        title: 'Connect Google Drive',
        message:
            'Your photos are stored in your own Google Drive and shared '
            'with this trip by link.',
        actionLabel: 'Connect',
        onAction: onConnect,
      );
    }
    final members = plan.memberUids.length;
    return StatusBanner(
      kind: StatusKind.success,
      title: members > 1
          ? 'Shared with $members people on this trip'
          : 'Shared album',
      message:
          'Photos are stored in each person\'s Google Drive. Anyone with a '
          'photo\'s link can open it; only trip members see the links.',
    );
  }
}

IconData _statusIcon(UploadStatus s) => switch (s) {
  UploadStatus.local => Icons.smartphone_outlined,
  UploadStatus.waiting => Icons.schedule_rounded,
  UploadStatus.uploading => Icons.cloud_upload_outlined,
  UploadStatus.shared => Icons.cloud_done_outlined,
  UploadStatus.failed => Icons.error_outline_rounded,
};

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.item, required this.onTap});

  final AlbumItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = item.status;
    final who = item.shared?.uploaderName ?? 'You';
    final when = DateFormat('d MMM').format(item.takenAt);
    final px = (160 * MediaQuery.devicePixelRatioOf(context)).round();
    final mine = item.mine;
    final Widget image = mine != null
        ? Image.file(
            File(mine.filePath),
            fit: BoxFit.cover,
            cacheWidth: px,
            errorBuilder: (_, _, _) => _broken(colors),
          )
        : Image.network(
            driveFileUrl(item.shared!.thumbFileId).toString(),
            fit: BoxFit.cover,
            cacheWidth: px,
            errorBuilder: (_, _, _) => _broken(colors),
          );
    return Semantics(
      button: true,
      label:
          'Photo by $who, $when'
          '${status != null && status != UploadStatus.shared ? ', ${status.label}' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (status != null && status != UploadStatus.shared)
              Positioned(
                left: 6,
                bottom: 6,
                child: Tag(
                  status.label,
                  icon: _statusIcon(status),
                  tone: TagTone.onImage,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _broken(AppColors colors) => ColoredBox(
    color: colors.surfaceMuted,
    child: Icon(Icons.broken_image_outlined, color: colors.textSecondary),
  );
}

/// One album photo full screen: who took it, when, where (if shared), and
/// for your own photos the upload status, Retry and Remove.
class AlbumPhotoViewer extends ConsumerWidget {
  const AlbumPhotoViewer({super.key, required this.item, required this.tripId});

  final AlbumItem item;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = item.shared;
    final mine = item.mine;
    // Your own: follow live status changes from the queue.
    final live = mine == null
        ? null
        : (ref.watch(tripQueueProvider(tripId)).value ?? const [])
              .where((q) => q.id == mine.id)
              .firstOrNull;
    final status = (live ?? mine)?.status;
    final who = shared?.uploaderName ?? 'You';
    final when = DateFormat('d MMM y · h:mm a').format(item.takenAt);
    final lat =
        shared?.latitude ??
        (mine?.includeLocation == true ? mine?.latitude : null);
    final lng =
        shared?.longitude ??
        (mine?.includeLocation == true ? mine?.longitude : null);

    return MediaShell(
      title: '$who · $when',
      body: InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: mine != null
              ? Image.file(File(mine.filePath), fit: BoxFit.contain)
              : Image.network(
                  driveFileUrl(shared!.viewFileId).toString(),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const CircularProgressIndicator(color: mediaOnColor),
                  errorBuilder: (_, _, _) => const Text(
                    'Couldn\'t load this photo. Check your connection.',
                    style: TextStyle(color: mediaOnColorMuted),
                  ),
                ),
        ),
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null) ...[
            Row(
              children: [
                Icon(_statusIcon(status), size: 18, color: mediaOnColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [status.label, ?(live ?? mine)?.lastError].join(' · '),
                    style: const TextStyle(color: mediaOnColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              if (lat != null && lng != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Where'),
                ),
              if (status == UploadStatus.failed ||
                  status == UploadStatus.waiting)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(albumUploaderProvider).retry(mine!.id),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              if (mine != null)
                OutlinedButton.icon(
                  onPressed: () => _remove(context, ref, live ?? mine),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    QueuedPhoto photo,
  ) async {
    final ok = await confirmDestructive(
      context,
      title: 'Remove from the album?',
      message:
          'Everyone on the trip stops seeing it. The photo stays in your '
          'Memories.',
      confirmLabel: 'Remove',
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final cleaned = await ref.read(albumUploaderProvider).remove(photo);
    navigator.pop();
    if (!cleaned) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Removed. Its copies are still in your Google Drive folder.',
          ),
        ),
      );
    }
  }
}

typedef _AddChoice = ({bool camera, bool includeLocation});

/// Camera or Memories, and whether to show where photos were taken.
class _AddSheet extends StatefulWidget {
  const _AddSheet();

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  bool _location = false;

  @override
  Widget build(BuildContext context) {
    void pick(bool camera) =>
        Navigator.of(context).pop((camera: camera, includeLocation: _location));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: 'Take a photo',
            onTap: () => pick(true),
          ),
          AppListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: 'Choose from Memories',
            onTap: () => pick(false),
          ),
          SwitchListTile(
            title: const Text('Show where they were taken'),
            subtitle: const Text('Off: the album never shows the place.'),
            value: _location,
            onChanged: (v) => setState(() => _location = v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Pick photos from your Memories to add (newest first).
class _MemoryPicker extends ConsumerStatefulWidget {
  const _MemoryPicker();

  @override
  ConsumerState<_MemoryPicker> createState() => _MemoryPickerState();
}

class _MemoryPickerState extends ConsumerState<_MemoryPicker> {
  final _picked = <String>{};
  List<Memory>? _photos;

  @override
  void initState() {
    super.initState();
    ref.read(memoryRepositoryProvider).getAll(limit: 300).then((all) {
      if (!mounted) return;
      setState(
        () => _photos = all.where((m) => m.type == MemoryType.photo).toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Choose photos', style: text.titleLarge),
        ),
        if (photos == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (photos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No photos in your Memories yet.'),
          )
        else
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final m = photos[i];
                final on = _picked.contains(m.id);
                return Semantics(
                  button: true,
                  selected: on,
                  label: 'Photo, ${DateFormat('d MMM').format(m.timestamp)}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => setState(
                      () => on ? _picked.remove(m.id) : _picked.add(m.id),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(m.filePath),
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                        if (on)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: AppButton(
              label: _picked.isEmpty ? 'Add' : 'Add ${_picked.length}',
              expand: true,
              onPressed: _picked.isEmpty || photos == null
                  ? null
                  : () => Navigator.of(context).pop([
                      for (final m in photos)
                        if (_picked.contains(m.id)) m,
                    ]),
            ),
          ),
        ),
      ],
    );
  }
}
