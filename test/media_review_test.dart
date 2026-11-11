// Videos and gallery photos are reviewed before they become memories, and
// discarding never deletes a file that belongs to the user's gallery.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/features/memories/data/memory_repository.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/memories/presentation/memory_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// A pretend phone camera and gallery: each call hands out the next queued
/// file (nothing queued = the user backed out).
class _Picker extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  final videos = <XFile?>[];
  final photos = <List<XFile>>[];
  var videoCalls = 0;
  ImageSource? lastVideoSource;

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoCalls++;
    lastVideoSource = source;
    return videos.isEmpty ? null : videos.removeAt(0);
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => photos.isEmpty ? [] : photos.removeAt(0);
}

class _Gps extends LocationService {
  @override
  Future<LatLng?> getCurrentLocation({
    bool acceptRecent = false,
    Duration recentFor = const Duration(minutes: 10),
  }) async => const LatLng(30.7525, 76.8101);
}

void main() {
  late Directory tmp;
  late _Picker picker;
  int? saved;
  late ProviderContainer container;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('rwe_media');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  File file(String name) {
    final dir = Directory.systemTemp.createTempSync('pick');
    return File('${dir.path}/$name')..writeAsBytesSync(_png);
  }

  Future<void> open(WidgetTester tester) async {
    picker = _Picker();
    ImagePickerPlatform.instance = picker;
    saved = null;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(_Gps())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async =>
                      saved = await showAddMemorySheet(context),
                  child: const Text('add'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
  }

  /// Waits in real time (file and database work) until [done], then settles.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapAndWait(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<Memory>> memories(WidgetTester tester) async =>
      (await tester.runAsync(
        () => container.read(memoryRepositoryProvider).getAll(),
      )) ??
      [];

  group('Recording a video', () {
    testWidgets('it is shown for review and not saved yet', (tester) async {
      await open(tester);
      picker.videos.add(XFile(file('rec.mp4').path));
      await tapAndWait(tester, find.text('Record a video'));

      expect(find.text('Review video'), findsOneWidget);
      expect(find.text('Record again'), findsOneWidget);
      expect(find.text('Use video'), findsOneWidget);
      expect(picker.lastVideoSource, ImageSource.camera);
      expect(saved, isNull);
    });

    testWidgets('Record again deletes the take and records again', (
      tester,
    ) async {
      await open(tester);
      final first = file('take1.mp4');
      final second = file('take2.mp4');
      picker.videos.addAll([XFile(first.path), XFile(second.path)]);
      await tapAndWait(tester, find.text('Record a video'));
      await tapAndWait(tester, find.text('Record again'));

      expect(picker.videoCalls, 2);
      expect(first.existsSync(), false); // the discarded take is gone
      expect(second.existsSync(), true);
      expect(find.text('Review video'), findsOneWidget); // reviewing take 2
    });

    testWidgets('closing the review discards the recording', (tester) async {
      await open(tester);
      final rec = file('rec.mp4');
      picker.videos.add(XFile(rec.path));
      await tapAndWait(tester, find.text('Record a video'));
      await tapAndWait(tester, find.byIcon(Icons.close_rounded));

      expect(rec.existsSync(), false);
      expect(find.text('Review video'), findsNothing);
      expect(await memories(tester), isEmpty);
    });

    testWidgets('Use video saves it with the time and place of the recording', (
      tester,
    ) async {
      await open(tester);
      final before = DateTime.now();
      picker.videos.add(XFile(file('rec.mp4').path));
      await tapAndWait(tester, find.text('Record a video'));
      await tester.binding.delayed(const Duration(seconds: 20)); // a long look
      await tester.tap(find.text('Use video'));
      await until(tester, () => saved != null);

      expect(saved, 1);
      final all = await memories(tester);
      expect(all, hasLength(1));
      final m = all.single;
      expect(m.type, MemoryType.video);
      expect(File(m.filePath).existsSync(), true);
      expect(m.latitude, 30.7525);
      expect(m.timestamp.difference(before).inSeconds.abs(), lessThan(5));
    });

    testWidgets('backing out of the recorder does nothing', (tester) async {
      await open(tester);
      await tapAndWait(tester, find.text('Record a video'));
      expect(find.text('Review video'), findsNothing);
      expect(find.text('Add a memory'), findsOneWidget); // still on the sheet
    });
  });

  group('A video from the gallery', () {
    testWidgets('cancelling never deletes the original', (tester) async {
      await open(tester);
      final original = file('holiday.mp4');
      picker.videos.add(XFile(original.path));
      await tapAndWait(tester, find.text('Video from gallery'));
      expect(find.text('Choose another'), findsOneWidget);
      await tapAndWait(tester, find.byIcon(Icons.close_rounded));
      expect(original.existsSync(), true);
    });

    testWidgets('Choose another keeps the first original and asks again', (
      tester,
    ) async {
      await open(tester);
      final a = file('a.mp4');
      final b = file('b.mp4');
      picker.videos.addAll([XFile(a.path), XFile(b.path)]);
      await tapAndWait(tester, find.text('Video from gallery'));
      await tapAndWait(tester, find.text('Choose another'));
      expect(picker.videoCalls, 2);
      expect(a.existsSync(), true);
      expect(b.existsSync(), true);
    });
  });

  group('Photos from the gallery', () {
    testWidgets('reviewed together; removing one leaves the rest', (
      tester,
    ) async {
      await open(tester);
      final files = [for (var i = 0; i < 3; i++) file('p$i.png')];
      final already = (await memories(tester)).length;
      picker.photos.add([for (final f in files) XFile(f.path)]);
      await tapAndWait(tester, find.text('Photos from gallery'));

      expect(find.text('Review photos (1/3)'), findsOneWidget);
      expect(find.text('Use 3 photos'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove this photo'));
      await tester.pumpAndSettle();
      expect(find.text('Use 2 photos'), findsOneWidget);

      await tester.tap(find.text('Use 2 photos'));
      await until(tester, () => saved != null);
      expect(saved, 2);
      expect(await memories(tester), hasLength(already + 2));
      // The user's own files are untouched, including the removed one.
      for (final f in files) {
        expect(f.existsSync(), true);
      }
    });

    testWidgets('a single photo reads "Use photo"', (tester) async {
      await open(tester);
      picker.photos.add([XFile(file('one.png').path)]);
      await tapAndWait(tester, find.text('Photos from gallery'));
      expect(find.text('Review photo'), findsOneWidget);
      expect(find.text('Use photo'), findsOneWidget);
      expect(find.byTooltip('Remove this photo'), findsNothing);
    });

    testWidgets('cancelling saves nothing and keeps the originals', (
      tester,
    ) async {
      await open(tester);
      final f = file('keep.png');
      picker.photos.add([XFile(f.path)]);
      await tapAndWait(tester, find.text('Photos from gallery'));
      await tapAndWait(tester, find.byIcon(Icons.close_rounded));
      expect(f.existsSync(), true);
      expect(saved, isNull);
    });
  });
}
