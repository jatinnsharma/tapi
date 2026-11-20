import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/album/application/album_uploader.dart';
import 'package:real_world_exploration/features/album/data/album_cloud_repository.dart';
import 'package:real_world_exploration/features/album/data/album_queue_repository.dart';
import 'package:real_world_exploration/features/album/data/drive_auth.dart';
import 'package:real_world_exploration/features/album/data/drive_client.dart';
import 'package:real_world_exploration/features/album/data/photo_processing.dart';
import 'package:real_world_exploration/features/album/domain/album_photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Auth implements DriveAuth {
  String? current = 'tok';
  final invalidated = <String>[];
  @override
  Future<String?> token({bool interactive = false}) async => current;

  /// A rejected token is gone until the user connects Drive again.
  @override
  Future<void> invalidate(String token) async {
    invalidated.add(token);
    current = null;
  }

  @override
  Future<void> disconnect() async => current = null;
}

class _Drive implements DriveClient {
  final uploads = <String>[];
  final shared = <String>[];
  final deleted = <String>[];
  var folders = 0;

  /// Throw this on the next upload (once).
  Exception? failNextUpload;

  @override
  Future<String> createFolder(String name) async => 'folder${++folders}';
  @override
  Future<bool> folderExists(String id) async => true;
  @override
  Future<String> uploadJpeg({
    required String folderId,
    required String name,
    required Uint8List bytes,
  }) async {
    final fail = failNextUpload;
    if (fail != null) {
      failNextUpload = null;
      throw fail;
    }
    uploads.add(name);
    return 'file-$name';
  }

  @override
  Future<void> shareByLink(String fileId) async => shared.add(fileId);
  @override
  Future<void> delete(String fileId) async => deleted.add(fileId);
}

class _Cloud implements AlbumCloud {
  final records = <String, AlbumPhoto>{};
  @override
  Stream<List<AlbumPhoto>> watch(String tripId) =>
      Stream.value(records.values.toList());
  @override
  Future<void> put(String tripId, AlbumPhoto photo) async =>
      records[photo.id] = photo;
  @override
  Future<void> delete(String tripId, String photoId) async =>
      records.remove(photoId);
}

Uint8List _jpegWithGps(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(30, 120, 80));
  image.exif.gpsIfd.gpsLatitude = 25.31;
  image.exif.gpsIfd.gpsLongitude = 83.01;
  return img.encodeJpg(image);
}

void main() {
  group('album copies', () {
    test('the source photo really has a location (sanity check)', () {
      final exif = img.decodeJpgExif(_jpegWithGps(64, 48));
      expect(exif?.gpsIfd.hasGPSLatitude, isTrue);
    });

    test('are resized and carry no location', () {
      final copies = makeAlbumCopiesSync(_jpegWithGps(3000, 2000));
      final view = img.decodeJpg(copies.view)!;
      final thumb = img.decodeJpg(copies.thumb)!;
      expect(view.width, albumViewSize);
      expect(view.height, closeTo(2048 * 2 / 3, 1));
      expect(thumb.width, albumThumbSize);
      for (final bytes in [copies.view, copies.thumb]) {
        final exif = img.decodeJpgExif(bytes);
        expect(exif?.gpsIfd.hasGPSLatitude ?? false, isFalse);
      }
    });

    test('small photos are not enlarged', () {
      final copies = makeAlbumCopiesSync(_jpegWithGps(300, 200));
      expect(img.decodeJpg(copies.view)!.width, 300);
    });
  });

  group('uploader', () {
    late AlbumQueueRepository queue;
    late _Auth auth;
    late _Drive drive;
    late _Cloud cloud;
    late DateTime now;
    AlbumTrip? trip;
    AlbumUploaderIdentity? me;
    var missingFiles = <String>{};

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = Directory.systemTemp.createTempSync('rwe_album');
      await databaseFactoryFfi.setDatabasesPath(dir.path);
      queue = AlbumQueueRepository(DatabaseService());
      auth = _Auth();
      drive = _Drive();
      cloud = _Cloud();
      now = DateTime(2026, 11, 19, 10);
      trip = (title: 'Varanasi', inCloud: true);
      me = (uid: 'me', name: 'Asha');
      missingFiles = {};
    });

    AlbumUploader uploader() => AlbumUploader(
      queue: queue,
      cloud: cloud,
      auth: auth,
      driveFor: (_) => drive,
      tripInfo: (_) async => trip,
      identity: () => me,
      clock: () => now,
      makeCopies: (path) async {
        if (missingFiles.contains(path)) {
          throw FileSystemException('gone', path);
        }
        return AlbumCopies(
          view: Uint8List.fromList([1]),
          thumb: Uint8List.fromList([2]),
        );
      },
    );

    Future<QueuedPhoto> addAndDrain(
      AlbumUploader u, {
      String path = '/p/1.jpg',
      bool includeLocation = false,
    }) async {
      final added = await u.add(
        tripId: 't1',
        filePath: path,
        takenAt: DateTime(2026, 11, 18, 9),
        memoryId: path,
        latitude: 25.3,
        longitude: 83.0,
        includeLocation: includeLocation,
      );
      await u.drain();
      return (await queue.byId(added.id))!;
    }

    test(
      'uploads both copies, shares them by link, adds it to the album',
      () async {
        final u = uploader();
        final photo = await addAndDrain(u);
        expect(photo.status, UploadStatus.shared);
        expect(drive.uploads, ['${photo.id}-thumb.jpg', '${photo.id}.jpg']);
        expect(drive.shared, hasLength(2));
        final record = cloud.records[photo.id]!;
        expect(record.uploaderName, 'Asha');
        // Location is off unless the uploader chose to include it.
        expect(record.hasLocation, isFalse);

        await u.drain();
        expect(drive.uploads, hasLength(2), reason: 'shared ones stay shared');
      },
    );

    test('includes where it was taken only when asked', () async {
      final photo = await addAndDrain(uploader(), includeLocation: true);
      expect(cloud.records[photo.id]!.latitude, 25.3);
    });

    test('the same photo added twice is one album photo', () async {
      final u = uploader();
      final a = await addAndDrain(u);
      final b = await addAndDrain(u);
      expect(b.id, a.id);
      expect(cloud.records, hasLength(1));
    });

    test('a trip that is not backed up stays on this phone', () async {
      trip = (title: 'Varanasi', inCloud: false);
      final photo = await addAndDrain(uploader());
      expect(photo.status, UploadStatus.local);
      expect(drive.uploads, isEmpty);
    });

    test('signed out: on this phone only', () async {
      me = null;
      final photo = await addAndDrain(uploader());
      expect(photo.status, UploadStatus.local);
    });

    test('Drive not connected: waiting, with a reason', () async {
      auth.current = null;
      final photo = await addAndDrain(uploader());
      expect(photo.status, UploadStatus.waiting);
      expect(photo.lastError, contains('Connect Google Drive'));
    });

    test(
      'offline mid-way: waits, then finishes without a second copy',
      () async {
        // The thumbnail goes up, then the connection drops on the photo.
        var calls = 0;
        final flaky = _FlakyDrive(drive, () => ++calls == 2);
        final u2 = AlbumUploader(
          queue: queue,
          cloud: cloud,
          auth: auth,
          driveFor: (_) => flaky,
          tripInfo: (_) async => trip,
          identity: () => me,
          clock: () => now,
          makeCopies: (_) async => AlbumCopies(
            view: Uint8List.fromList([1]),
            thumb: Uint8List.fromList([2]),
          ),
        );
        final added = await u2.add(
          tripId: 't1',
          filePath: '/p/1.jpg',
          takenAt: DateTime(2026, 11, 18),
        );
        await u2.drain();
        var photo = (await queue.byId(added.id))!;
        expect(photo.status, UploadStatus.waiting);
        expect(photo.thumbFileId, isNotNull, reason: 'kept for the retry');
        expect(photo.nextTryAt, now.add(retryDelay(1)));

        // Not due yet: nothing happens.
        await u2.drain();
        expect(drive.uploads, hasLength(1));

        now = now.add(const Duration(minutes: 5));
        await u2.drain();
        photo = (await queue.byId(added.id))!;
        expect(photo.status, UploadStatus.shared);
        expect(
          drive.uploads.where((n) => n.endsWith('-thumb.jpg')),
          hasLength(1),
          reason: 'the thumbnail is not uploaded twice',
        );
      },
    );

    test('Drive rejecting the token asks to reconnect', () async {
      drive.failNextUpload = const DriveAuthException();
      final photo = await addAndDrain(uploader());
      expect(photo.status, UploadStatus.waiting);
      expect(photo.lastError, contains('Connect Google Drive'));
      expect(auth.invalidated, ['tok']);
    });

    test('a deleted file fails for good, with a reason', () async {
      missingFiles = {'/p/gone.jpg'};
      final photo = await addAndDrain(uploader(), path: '/p/gone.jpg');
      expect(photo.status, UploadStatus.failed);
      expect(photo.lastError, contains('no longer on the phone'));
    });

    test(
      'removing a shared photo removes the record and Drive copies',
      () async {
        final u = uploader();
        final photo = await addAndDrain(u);
        expect(await u.remove(photo), isTrue);
        expect(cloud.records, isEmpty);
        expect(drive.deleted, [photo.thumbFileId, photo.viewFileId]);
        expect(await queue.byId(photo.id), isNull);
      },
    );
  });

  group('Drive errors', () {
    DioException err(int? status, [Object? data]) => DioException(
      requestOptions: RequestOptions(),
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(),
              statusCode: status,
              data: data,
            ),
    );

    test('map to what the queue should do', () {
      expect(DriveClient.mapDioError(err(null)), isA<DriveOfflineException>());
      expect(DriveClient.mapDioError(err(401)), isA<DriveAuthException>());
      expect(DriveClient.mapDioError(err(429)), isA<DriveRateLimitException>());
      expect(
        DriveClient.mapDioError(err(403, {'reason': 'userRateLimitExceeded'})),
        isA<DriveRateLimitException>(),
      );
      expect(
        DriveClient.mapDioError(err(403, 'storageQuotaExceeded')).message,
        contains('full'),
      );
      expect(DriveClient.mapDioError(err(503)), isA<DriveRateLimitException>());
    });

    test('retry waits grow and stop at an hour', () {
      expect(retryDelay(0), const Duration(seconds: 30));
      expect(retryDelay(1), const Duration(minutes: 1));
      expect(retryDelay(20), const Duration(hours: 1));
    });
  });
}

/// Wraps [_Drive], dropping the connection on one upload.
class _FlakyDrive implements DriveClient {
  _FlakyDrive(this.inner, this.dropNow);
  final _Drive inner;
  final bool Function() dropNow;

  @override
  Future<String> createFolder(String name) => inner.createFolder(name);
  @override
  Future<bool> folderExists(String id) => inner.folderExists(id);
  @override
  Future<String> uploadJpeg({
    required String folderId,
    required String name,
    required Uint8List bytes,
  }) {
    if (dropNow()) throw const DriveOfflineException();
    return inner.uploadJpeg(folderId: folderId, name: name, bytes: bytes);
  }

  @override
  Future<void> shareByLink(String fileId) => inner.shareByLink(fileId);
  @override
  Future<void> delete(String fileId) => inner.delete(fileId);
}
