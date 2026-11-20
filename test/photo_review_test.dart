// Taking a photo shows a review screen; only an accepted photo is saved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/features/memories/data/memory_repository.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/memories/presentation/camera_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// A 1x1 PNG.
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

class _FakeCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  _FakeCamera(this.shotsDir);
  final String shotsDir;
  final shots = <String>[];
  final _initialized = <int, StreamController<CameraInitializedEvent>>{};

  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  /// Highest frame rate this pretend phone films at.
  int maxFps = 240;

  /// Every camera opened: its frame rate (null: default) and sound.
  final opened = <({int? fps, bool audio})>[];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription camera,
    MediaSettings? mediaSettings,
  ) async {
    final fps = mediaSettings?.fps;
    if (fps != null && fps > maxFps) {
      throw CameraException('fps', 'Unsupported frame rate $fps.');
    }
    opened.add((fps: fps, audio: mediaSettings?.enableAudio ?? true));
    _initialized[0] = StreamController<CameraInitializedEvent>.broadcast();
    return 0;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) =>
      _initialized[id]!.stream;
  @override
  Stream<CameraErrorEvent> onCameraError(int id) =>
      StreamController<CameraErrorEvent>.broadcast().stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    scheduleMicrotask(
      () => _initialized[cameraId]!.add(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      ),
    );
  }

  @override
  Widget buildPreview(int cameraId) => Container(color: Colors.blueGrey);

  @override
  Future<XFile> takePicture(int cameraId) async {
    final path = '$shotsDir/shot_${shots.length}.png';
    File(path).writeAsBytesSync(_png);
    shots.add(path);
    return XFile(path);
  }

  /// Videos "recorded" (the fake writes a small file on stop).
  final videos = <String>[];
  var recording = false;

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    recording = true;
  }

  var pauses = 0;
  var resumes = 0;

  @override
  Future<void> pauseVideoRecording(int cameraId) async => pauses++;

  @override
  Future<void> resumeVideoRecording(int cameraId) async => resumes++;

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    recording = false;
    final path = '$shotsDir/clip_${videos.length}.mp4';
    File(path).writeAsBytesSync([0, 0, 0, 24]);
    videos.add(path);
    return XFile(path);
  }

  @override
  Future<void> dispose(int cameraId) async {}
}

class _Gps extends LocationService {
  @override
  Future<LatLng?> getCurrentLocation({
    bool acceptRecent = false,
    Duration recentFor = const Duration(minutes: 10),
  }) async => const LatLng(30.7525, 76.8101);
}

/// Lets real file and database work finish, then settles the screen.
Future<void> _io(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pumpAndSettle();
}

/// Waits (in real time) until [done] is true, then settles the screen.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  late _FakeCamera camera;
  Memory? result;
  var popped = false;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('rwe_review');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> openCamera(WidgetTester tester) async {
    // Own folder per test: Windows won't delete a file an earlier test still shows.
    camera = _FakeCamera(Directory.systemTemp.createTempSync('shots').path);
    CameraPlatform.instance = camera;
    result = null;
    popped = false;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
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
                  onPressed: () async {
                    result = await Navigator.of(context).push<Memory>(
                      MaterialPageRoute(builder: (_) => const CameraScreen()),
                    );
                    popped = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('taking a photo shows it for review, nothing saved yet', (
    tester,
  ) async {
    final c = await openCamera(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();

    expect(find.text('Review photo'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Use photo'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(popped, false);
    await tester.runAsync(() async {
      expect(await c.read(memoryRepositoryProvider).getAll(), isEmpty);
    });
  });

  testWidgets('Retake goes back to the camera and discards the photo', (
    tester,
  ) async {
    final c = await openCamera(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake'));
    await _io(tester);

    expect(
      find.byKey(const Key('shutter')),
      findsOneWidget,
    ); // still on the camera
    expect(popped, false);
    await tester.runAsync(() async {
      expect(await c.read(memoryRepositoryProvider).getAll(), isEmpty);
      // The delete is real file work: give it up to 3 s.
      final shot = File(camera.shots.single);
      for (var i = 0; i < 30 && shot.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(shot.existsSync(), false);
    });
  });

  testWidgets('the close button and back also retake', (tester) async {
    await openCamera(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _io(tester);
    expect(find.byKey(const Key('shutter')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // the phone's back button
    await _io(tester);
    expect(find.byKey(const Key('shutter')), findsOneWidget);
    expect(popped, false);
  });

  testWidgets('you can retake and then keep the second photo', (tester) async {
    final c = await openCamera(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake'));
    await _io(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use photo'));
    await _until(tester, () => popped);

    expect(popped, true);
    expect(result, isNotNull);
    expect(result!.type, MemoryType.photo);
    expect(File(result!.filePath).existsSync(), true);
    await tester.runAsync(() async {
      expect(await c.read(memoryRepositoryProvider).getAll(), hasLength(1));
    });
  });

  testWidgets('the saved photo carries the time and place of the shutter', (
    tester,
  ) async {
    await openCamera(tester);
    final before = DateTime.now();
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pumpAndSettle();
    final after = DateTime.now();
    // A long look at the photo must not change when it counts as taken.
    await tester.binding.delayed(const Duration(seconds: 30));
    await tester.tap(find.text('Use photo'));
    await _until(tester, () => popped);

    final taken = result!.timestamp;
    expect(taken.isBefore(before), false);
    expect(taken.isAfter(after), false);
    expect(result!.latitude, 30.7525);
    expect(result!.longitude, 76.8101);
  });

  group('Video', () {
    testWidgets('holding the button records; letting go shows the review', (
      tester,
    ) async {
      await openCamera(tester);
      expect(find.text('Tap for photo · hold for video'), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('shutter'))),
      );
      await tester.pump(const Duration(milliseconds: 700)); // long press
      await tester.pump(const Duration(milliseconds: 300));
      expect(camera.recording, isTrue);
      expect(find.text('Release to stop'), findsOneWidget);
      expect(find.textContaining('/ 1:00'), findsOneWidget);
      await gesture.up();
      await _io(tester);
      expect(camera.recording, isFalse);
      expect(find.text('Review video'), findsOneWidget);
      expect(find.text('Record again'), findsOneWidget);
      expect(find.text('Use video'), findsOneWidget);
    });

    testWidgets('Video mode: tap to start, tap to stop, then keep it', (
      tester,
    ) async {
      final c = await openCamera(tester);
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      expect(find.text('Tap to start recording'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shutter')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(camera.recording, isTrue);
      expect(find.text('Tap to stop'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shutter')));
      await _io(tester);
      await tester.tap(find.text('Use video'));
      await _until(tester, () => popped);

      expect(result!.type, MemoryType.video);
      expect(result!.durationSeconds, greaterThanOrEqualTo(1));
      expect(result!.latitude, 30.7525, reason: 'where it was recorded');
      await tester.runAsync(() async {
        final all = await c.read(memoryRepositoryProvider).getAll();
        expect(all.where((m) => m.id == result!.id), hasLength(1));
      });
    });

    testWidgets('Record again throws the clip away and stays on the camera', (
      tester,
    ) async {
      final c = await openCamera(tester);
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('shutter')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('shutter')));
      await _io(tester);
      await tester.tap(find.text('Record again'));
      await _io(tester);

      expect(find.byKey(const Key('shutter')), findsOneWidget);
      expect(popped, isFalse);
      await tester.runAsync(() async {
        final all = await c.read(memoryRepositoryProvider).getAll();
        // Earlier tests in this file saved photos and one video; this
        // recording added nothing.
        expect(
          all.where((m) => m.filePath.contains(camera.videos.single)),
          isEmpty,
        );
        final clip = File(camera.videos.single);
        for (var i = 0; i < 30 && clip.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(clip.existsSync(), isFalse);
      });
    });

    testWidgets('the self-timer counts down before the photo', (tester) async {
      await openCamera(tester);
      await tester.tap(find.byTooltip('Timer: off'));
      await tester.pump();
      expect(find.byTooltip('Timer: 3 seconds'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shutter')));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(camera.shots, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await _io(tester);
      expect(camera.shots, hasLength(1));
      expect(find.text('Review photo'), findsOneWidget);
    });
  });

  group('Longer videos, pause and slow motion', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 11, 19, 10);
      cameraClock = () => now;
    });
    tearDown(() => cameraClock = DateTime.now);

    Future<void> advance(WidgetTester tester, Duration d) async {
      now = now.add(d);
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('Video mode allows 10 minutes; pauses do not count', (
      tester,
    ) async {
      await openCamera(tester);
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('shutter')));
      await tester.pump();
      await advance(tester, const Duration(seconds: 5));
      expect(find.text('0:05 / 10:00'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(camera.pauses, 1);
      await advance(tester, const Duration(seconds: 30));
      expect(find.text('Paused · 0:05 / 10:00'), findsOneWidget);
      expect(find.text('Paused · tap to stop'), findsOneWidget);

      await tester.tap(find.byTooltip('Resume'));
      await tester.pump();
      expect(camera.resumes, 1);
      await advance(tester, const Duration(seconds: 3));
      expect(find.text('0:08 / 10:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shutter')));
      await _io(tester);
      await tester.tap(find.text('Use video'));
      await _until(tester, () => popped);
      expect(result!.durationSeconds, 8);
      expect(result!.playbackSpeed, isNull);
    });

    testWidgets('slow motion films at 120 fps without sound, plays at ¼', (
      tester,
    ) async {
      await openCamera(tester);
      await tester.tap(find.text('SLOW-MO'));
      await tester.pumpAndSettle();
      expect(camera.opened.last, (fps: 120, audio: false));
      expect(find.textContaining('¼ speed, no sound'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shutter')));
      await tester.pump();
      await advance(tester, const Duration(seconds: 2));
      expect(find.text('Slow-mo · 0:02 / 1:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shutter')));
      await _io(tester);
      expect(find.text('Review slow motion'), findsOneWidget);
      await tester.tap(find.text('Use video'));
      await _until(tester, () => popped);
      expect(result!.playbackSpeed, 0.25);
      expect(result!.isSlowMotion, isTrue);
      expect(result!.durationSeconds, 8, reason: '2 s filmed plays for 8 s');
    });

    testWidgets('a phone that only reaches 60 fps gets ½-speed slow motion', (
      tester,
    ) async {
      await openCamera(tester);
      camera.maxFps = 60;
      await tester.tap(find.text('SLOW-MO'));
      await tester.pumpAndSettle();
      expect(camera.opened.last.fps, 60);
      expect(find.textContaining('½ speed'), findsOneWidget);
    });

    testWidgets(
      'no fast frame rate at all: back to normal video, with a note',
      (tester) async {
        await openCamera(tester);
        camera.maxFps = 30;
        await tester.tap(find.text('SLOW-MO'));
        await tester.pumpAndSettle();
        expect(
          find.text('Slow motion isn\'t available on this phone.'),
          findsOneWidget,
        );
        expect(camera.opened.last.fps, isNull);
        expect(find.text('Tap to start recording'), findsOneWidget);
      },
    );

    testWidgets('back in Video mode, sound is on again', (tester) async {
      await openCamera(tester);
      await tester.tap(find.text('SLOW-MO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VIDEO'));
      await tester.pumpAndSettle();
      expect(camera.opened.last, (fps: null, audio: true));
    });
  });
}
