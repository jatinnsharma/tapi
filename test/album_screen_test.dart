import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/album/application/album_uploader.dart';
import 'package:real_world_exploration/features/album/data/album_cloud_repository.dart';
import 'package:real_world_exploration/features/album/data/album_queue_repository.dart';
import 'package:real_world_exploration/features/album/data/drive_auth.dart';
import 'package:real_world_exploration/features/album/domain/album_item.dart';
import 'package:real_world_exploration/features/album/domain/album_photo.dart';
import 'package:real_world_exploration/features/album/presentation/share_trip_photos_sheet.dart';
import 'package:real_world_exploration/features/album/presentation/trip_album_screen.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Trips extends SavedTripsNotifier {
  _Trips(this.trips);
  final List<TripPlan> trips;
  @override
  Future<List<TripPlan>> build() async => trips;
}

class _NoopUploader extends AlbumUploader {
  _NoopUploader()
    : super(
        queue: AlbumQueueRepository(DatabaseService()),
        cloud: null,
        auth: GoogleDriveAuth(),
        driveFor: (_) => throw UnimplementedError(),
        tripInfo: (_) async => null,
        identity: () => null,
      );
  @override
  Future<void> drain() async {}
}

QueuedPhoto _mine(
  String id,
  UploadStatus status, {
  int day = 1,
  DateTime? sharedOutAt,
}) => QueuedPhoto(
  id: id,
  tripId: 't1',
  filePath: '/nope/$id.jpg',
  takenAt: DateTime(2026, 11, day, 9),
  status: status,
  sharedOutAt: sharedOutAt,
);

AlbumPhoto _theirs(String id, {int day = 2}) => AlbumPhoto(
  id: id,
  uploaderUid: 'bob',
  uploaderName: 'Bob',
  takenAt: DateTime(2026, 11, day, 10),
  thumbFileId: 'thumb-$id',
  viewFileId: 'view-$id',
);

final _trip = TripPlan(
  id: 't1',
  title: 'Varanasi',
  destination: 'Varanasi',
  daysCount: 2,
  createdAt: DateTime(2026),
  days: const [],
  ownerUid: 'me',
  memberUids: const ['me', 'bob', 'cara'],
  cloudSynced: true,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<QueuedPhoto> mine,
  List<AlbumPhoto> shared = const [],
  bool driveConnected = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(true),
        driveConfiguredProvider.overrideWithValue(true),
        authStateProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        savedTripsListProvider.overrideWith(() => _Trips([_trip])),
        tripQueueProvider.overrideWith((ref, _) => Stream.value(mine)),
        sharedAlbumProvider.overrideWith((ref, _) => Stream.value(shared)),
        driveConnectedProvider.overrideWith((ref) async => driveConnected),
        albumUploaderProvider.overrideWithValue(_NoopUploader()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const TripAlbumScreen(tripId: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('merging the album', () {
    test('your shared photo appears once; newest first', () {
      final items = mergeAlbum(
        shared: [_theirs('b1', day: 2), _theirs('m1', day: 1)],
        mine: [
          _mine('m1', UploadStatus.shared, day: 1),
          _mine('m2', UploadStatus.waiting, day: 3),
        ],
      );
      expect(items.map((i) => i.id), ['m2', 'b1', 'm1']);
      expect(items.last.isMine, isTrue, reason: 'drawn from the phone');
      expect(items.first.status, UploadStatus.waiting);
    });

    test('the header sums up what is still on its way', () {
      expect(
        queueSummary([
          _mine('a', UploadStatus.waiting),
          _mine('b', UploadStatus.waiting),
          _mine('c', UploadStatus.uploading),
          _mine('d', UploadStatus.shared),
        ]),
        '1 uploading · 2 waiting',
      );
      expect(queueSummary([_mine('d', UploadStatus.shared)]), isNull);
    });
  });

  group('share sheet', () {
    test('starts with the photos not shared yet', () {
      final photos = [
        _mine('a', UploadStatus.shared, sharedOutAt: DateTime(2026)),
        _mine('b', UploadStatus.local),
      ];
      expect(initialShareSelection(photos), {'b'});
    });

    test('everything shared before: all are picked', () {
      final photos = [
        _mine('a', UploadStatus.shared, sharedOutAt: DateTime(2026)),
      ];
      expect(initialShareSelection(photos), {'a'});
    });

    test('caption', () {
      expect(defaultShareCaption('Goa', 1), 'Goa · 1 photo');
      expect(defaultShareCaption('Goa', 12), 'Goa · 12 photos');
    });
  });

  testWidgets('your photos show their status; others show who took them', (
    tester,
  ) async {
    await _pump(
      tester,
      mine: [
        _mine('m1', UploadStatus.waiting),
        _mine('m2', UploadStatus.failed),
      ],
      shared: [_theirs('b1')],
    );
    expect(find.text('Varanasi album'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('1 waiting · 1 failed'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Photo by Bob')), findsOneWidget);
    expect(find.text('Add photos'), findsOneWidget);
    expect(find.text('Shared with 3 people on this trip'), findsOneWidget);
  });

  testWidgets('Drive not connected: a banner with Connect', (tester) async {
    await _pump(
      tester,
      mine: [_mine('m1', UploadStatus.waiting)],
      driveConnected: false,
    );
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('an empty album invites you to add photos', (tester) async {
    await _pump(tester, mine: const []);
    expect(find.textContaining('No photos yet'), findsOneWidget);
    expect(File('/nope').existsSync(), isFalse);
  });
}
