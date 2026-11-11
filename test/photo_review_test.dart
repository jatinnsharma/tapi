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

  @override
  Future<int> createCameraWithSettings(
    CameraDescription camera,
    MediaSettings? mediaSettings,
  ) async {
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
    await tester.tap(find.byIcon(Icons.camera_alt));
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
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake'));
    await _io(tester);

    expect(find.text('Capture Memory'), findsOneWidget); // still on the camera
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
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _io(tester);
    expect(find.text('Capture Memory'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // the phone's back button
    await _io(tester);
    expect(find.text('Capture Memory'), findsOneWidget);
    expect(popped, false);
  });

  testWidgets('you can retake and then keep the second photo', (tester) async {
    final c = await openCamera(tester);
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake'));
    await _io(tester);
    await tester.tap(find.byIcon(Icons.camera_alt));
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
    await tester.tap(find.byIcon(Icons.camera_alt));
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
}
