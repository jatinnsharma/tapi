import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/google_drive.dart';
import '../../auth/application/auth_service.dart';
import '../../auth/application/display_name_provider.dart';
import '../../planner/data/saved_trips_repository.dart';
import '../data/album_cloud_repository.dart';
import '../data/album_queue_repository.dart';
import '../data/drive_auth.dart';
import '../data/drive_client.dart';
import '../data/photo_processing.dart';
import '../domain/album_photo.dart';

/// What the uploader needs to know about a trip.
typedef AlbumTrip = ({String title, bool inCloud});

/// Who is uploading.
typedef AlbumUploaderIdentity = ({String uid, String name});

/// Works through the phone's album queue: makes the small copies (no
/// location inside), uploads them to the uploader's Google Drive, shares
/// them by link, and adds the photo to the trip's shared album. Every step
/// can be repeated safely, so a retry after a dropped connection or a
/// closed app never makes a second copy.
class AlbumUploader {
  AlbumUploader({
    required this.queue,
    required this.cloud,
    required this.auth,
    required this.driveFor,
    required this.tripInfo,
    required this.identity,
    this.makeCopies = makeAlbumCopies,
    this.folders,
    DateTime Function()? clock,
    this.configured = true,
  }) : _clock = clock ?? DateTime.now;

  final AlbumQueueRepository queue;
  final AlbumCloud? cloud;
  final DriveAuth auth;

  /// A Drive client that gets its token from [auth].
  final DriveClient Function(Future<String> Function() token) driveFor;
  final Future<AlbumTrip?> Function(String tripId) tripInfo;
  final AlbumUploaderIdentity? Function() identity;
  final Future<AlbumCopies> Function(String path) makeCopies;

  /// Remembers each trip's Drive folder (null: keep it in memory only).
  final AlbumFolderStore? folders;
  final DateTime Function() _clock;

  /// Whether this build has Drive set up ([driveAlbumConfigured]).
  final bool configured;

  Future<void>? _current;
  bool _again = false;
  final _folderCache = <String, String>{};

  /// Adds a photo to a trip's album and starts uploading it.
  Future<QueuedPhoto> add({
    required String tripId,
    required String filePath,
    required DateTime takenAt,
    String? memoryId,
    double? latitude,
    double? longitude,
    bool includeLocation = false,
  }) async {
    final added = await queue.add(
      QueuedPhoto(
        id: const Uuid().v4(),
        tripId: tripId,
        memoryId: memoryId,
        filePath: filePath,
        takenAt: takenAt,
        latitude: latitude,
        longitude: longitude,
        includeLocation: includeLocation,
        status: UploadStatus.waiting,
      ),
    );
    unawaited(drain());
    return added;
  }

  /// Tries a failed photo again now.
  Future<void> retry(String id) async {
    final photo = await queue.byId(id);
    if (photo == null) return;
    await queue.save(
      photo.copyWith(
        status: UploadStatus.waiting,
        attempts: 0,
        clearNextTry: true,
        clearError: true,
      ),
    );
    await drain();
  }

  /// Removes one of your photos from the album: the shared record, your
  /// Drive copies (when Drive is connected) and the queue entry. The
  /// original stays in your Memories. Returns false when the Drive copies
  /// couldn't be deleted (Drive not connected).
  Future<bool> remove(QueuedPhoto photo) async {
    if (photo.status == UploadStatus.shared) {
      await cloud?.delete(photo.tripId, photo.id);
    }
    var driveCleaned = true;
    final ids = [?photo.thumbFileId, ?photo.viewFileId];
    if (ids.isNotEmpty) {
      try {
        final token = await auth.token();
        if (token == null) {
          driveCleaned = false;
        } else {
          final drive = driveFor(() async => token);
          for (final id in ids) {
            await drive.delete(id);
          }
        }
      } catch (_) {
        driveCleaned = false;
      }
    }
    await queue.remove(photo.id);
    return driveCleaned;
  }

  /// Uploads everything that's due. Safe to call often: a call while one is
  /// running makes it go round once more, and both callers get the same
  /// future, which completes when the queue is done.
  Future<void> drain() {
    final running = _current;
    if (running != null) {
      _again = true;
      return running;
    }
    return _current = _run().whenComplete(() => _current = null);
  }

  Future<void> _run() async {
    do {
      _again = false;
      for (final photo in await queue.due(_clock())) {
        await _process(photo);
      }
    } while (_again);
  }

  Future<void> _process(QueuedPhoto photo) async {
    final trip = await tripInfo(photo.tripId);
    final me = identity();
    final shareable =
        configured &&
        cloud != null &&
        me != null &&
        trip != null &&
        trip.inCloud;
    if (!shareable) {
      if (photo.status != UploadStatus.local) {
        await queue.save(
          photo.copyWith(status: UploadStatus.local, clearError: true),
        );
      }
      return;
    }

    String? token;
    try {
      token = await auth.token();
    } catch (_) {
      token = null;
    }
    if (token == null) {
      await queue.save(
        photo.copyWith(
          status: UploadStatus.waiting,
          lastError: 'Connect Google Drive to upload.',
        ),
      );
      return;
    }

    final drive = driveFor(() async => token!);
    var current = photo.copyWith(
      status: UploadStatus.uploading,
      clearError: true,
    );
    await queue.save(current);
    try {
      if (current.thumbFileId == null || current.viewFileId == null) {
        final copies = await makeCopies(current.filePath);
        final folder = await _folderFor(drive, photo.tripId, trip.title);
        if (current.thumbFileId == null) {
          final id = await drive.uploadJpeg(
            folderId: folder,
            name: '${current.id}-thumb.jpg',
            bytes: copies.thumb,
          );
          current = current.copyWith(thumbFileId: id);
          await queue.save(current);
        }
        if (current.viewFileId == null) {
          final id = await drive.uploadJpeg(
            folderId: folder,
            name: '${current.id}.jpg',
            bytes: copies.view,
          );
          current = current.copyWith(viewFileId: id);
          await queue.save(current);
        }
      }
      await drive.shareByLink(current.thumbFileId!);
      await drive.shareByLink(current.viewFileId!);
      await cloud!.put(
        photo.tripId,
        AlbumPhoto(
          id: current.id,
          uploaderUid: me.uid,
          uploaderName: me.name,
          takenAt: current.takenAt,
          thumbFileId: current.thumbFileId!,
          viewFileId: current.viewFileId!,
          latitude: current.includeLocation ? current.latitude : null,
          longitude: current.includeLocation ? current.longitude : null,
        ),
      );
      await queue.save(
        current.copyWith(
          status: UploadStatus.shared,
          attempts: 0,
          clearNextTry: true,
          clearError: true,
        ),
      );
    } on DriveAuthException {
      await auth.invalidate(token);
      await queue.save(
        current.copyWith(
          status: UploadStatus.waiting,
          lastError: 'Connect Google Drive again to upload.',
        ),
      );
    } on FileSystemException {
      await queue.save(
        current.copyWith(
          status: UploadStatus.failed,
          lastError: 'This photo is no longer on the phone.',
        ),
      );
    } on FormatException {
      await queue.save(
        current.copyWith(
          status: UploadStatus.failed,
          lastError: 'This file can\'t be read as a photo.',
        ),
      );
    } catch (e) {
      final attempts = current.attempts + 1;
      final temporary =
          e is DriveOfflineException || e is DriveRateLimitException;
      final giveUp = !temporary && attempts >= maxAutoAttempts;
      await queue.save(
        current.copyWith(
          status: giveUp ? UploadStatus.failed : UploadStatus.waiting,
          attempts: attempts,
          nextTryAt: _clock().add(retryDelay(attempts)),
          lastError: e is DriveException ? e.message : 'Upload failed.',
        ),
      );
    }
  }

  Future<String> _folderFor(
    DriveClient drive,
    String tripId,
    String title,
  ) async {
    final cached = _folderCache[tripId];
    if (cached != null) return cached;
    final stored = await folders?.get(tripId);
    if (stored != null && await drive.folderExists(stored)) {
      return _folderCache[tripId] = stored;
    }
    final created = await drive.createFolder('Tabi · $title');
    await folders?.set(tripId, created);
    return _folderCache[tripId] = created;
  }
}

/// Each trip's Drive folder id, remembered on the phone.
class AlbumFolderStore {
  static String _key(String tripId) => 'album_drive_folder_$tripId';

  Future<String?> get(String tripId) async =>
      (await SharedPreferences.getInstance()).getString(_key(tripId));

  Future<void> set(String tripId, String folderId) async =>
      (await SharedPreferences.getInstance()).setString(_key(tripId), folderId);
}

final albumUploaderProvider = Provider<AlbumUploader>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  return AlbumUploader(
    queue: ref.watch(albumQueueRepositoryProvider),
    cloud: ref.watch(albumCloudProvider),
    auth: ref.watch(driveAuthProvider),
    driveFor: (token) => DriveClient(dio, token),
    folders: AlbumFolderStore(),
    configured: ref.watch(driveConfiguredProvider),
    tripInfo: (tripId) async {
      final trips = await ref.read(savedTripsListProvider.future);
      final plan = trips.where((t) => t.id == tripId).firstOrNull;
      if (plan == null) return null;
      return (title: plan.title, inCloud: plan.cloudSynced);
    },
    identity: () {
      final user = ref.read(authStateProvider).value;
      if (user == null) return null;
      return (uid: user.uid, name: ref.read(displayNameProvider) ?? 'Explorer');
    },
  );
});
