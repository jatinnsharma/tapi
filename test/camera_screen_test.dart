// Runs the real CameraScreen against a pretend camera and measures what ends
// up on screen.
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:real_world_exploration/features/memories/presentation/camera_screen.dart';

class _FakeCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  _FakeCamera({
    required this.cameras,
    this.previewWidth = 1280,
    this.previewHeight = 720,
  });

  final List<CameraDescription> cameras;
  final double previewWidth;
  final double previewHeight;
  final opened = <CameraLensDirection>[];
  final disposed = <int>[];
  final _initialized = <int, StreamController<CameraInitializedEvent>>{};
  var _nextId = 0;
  final _lens = <int, CameraLensDirection>{};

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription camera,
    MediaSettings? mediaSettings,
  ) async {
    final id = _nextId++;
    opened.add(camera.lensDirection);
    _lens[id] = camera.lensDirection;
    _initialized[id] = StreamController<CameraInitializedEvent>.broadcast();
    return id;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized[cameraId]!.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>.broadcast().stream; // never errors

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
          previewWidth,
          previewHeight,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      ),
    );
  }

  @override
  Widget buildPreview(int cameraId) => Container(
    key: ValueKey('preview-${_lens[cameraId]!.name}'),
    color: Colors.blueGrey,
  );

  @override
  Future<void> dispose(int cameraId) async => disposed.add(cameraId);

  final zooms = <double>[];
  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;
  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 8;
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async => zooms.add(zoom);
}

CameraDescription _cam(String name, CameraLensDirection d) =>
    CameraDescription(name: name, lensDirection: d, sensorOrientation: 90);

Future<void> _open(
  WidgetTester tester,
  _FakeCamera fake, {
  Size size = const Size(400, 800),
  bool proofMode = false,
}) async {
  CameraPlatform.instance = fake;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: CameraScreen(proofMode: proofMode)),
    ),
  );
  await tester.pumpAndSettle();
}

final _both = [
  _cam('front', CameraLensDirection.front),
  _cam('back', CameraLensDirection.back),
];

void main() {
  boxRatioTests();

  testWidgets('opens on the back camera', (tester) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);
    expect(fake.opened, [CameraLensDirection.back]);
  });

  testWidgets('the preview fills the whole screen, edge to edge', (
    tester,
  ) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);

    final preview = tester.getRect(find.byKey(const ValueKey('preview-back')));
    final viewport = tester.getRect(find.byType(ClipRect).first);
    // The preview is cropped to the viewport, never smaller than it.
    expect(preview.width, greaterThanOrEqualTo(viewport.width - 0.5));
    expect(preview.height, greaterThanOrEqualTo(viewport.height - 0.5));
    // And the viewport is the whole body: full width, nearly full height.
    expect(viewport.width, 400);
    expect(viewport.height, 800);
  });

  testWidgets('it fills the screen when the sensor reports a tall preview', (
    tester,
  ) async {
    final fake = _FakeCamera(
      cameras: _both,
      previewWidth: 720,
      previewHeight: 1280,
    );
    await _open(tester, fake);
    final preview = tester.getRect(find.byKey(const ValueKey('preview-back')));
    final viewport = tester.getRect(find.byType(ClipRect).first);
    expect(preview.width, greaterThanOrEqualTo(viewport.width - 0.5));
    expect(preview.height, greaterThanOrEqualTo(viewport.height - 0.5));
  });

  testWidgets('the shutter is a large round button at the bottom centre', (
    tester,
  ) async {
    await _open(tester, _FakeCamera(cameras: _both));
    final shutter = find.byKey(const Key('shutter'));
    expect(tester.getSize(shutter).width, greaterThanOrEqualTo(76));
    final center = tester.getCenter(shutter);
    expect(center.dx, closeTo(200, 1));
    expect(center.dy, greaterThan(650));
  });

  testWidgets('the flip button is at the right, same row as the shutter', (
    tester,
  ) async {
    await _open(tester, _FakeCamera(cameras: _both));
    final flip = tester.getCenter(find.byIcon(Icons.cameraswitch_rounded));
    final shutter = tester.getCenter(find.byKey(const Key('shutter')));
    expect(flip.dx, greaterThan(300));
    expect(flip.dy, closeTo(shutter.dy, 12));
  });

  testWidgets('flipping opens the front camera, then the back again', (
    tester,
  ) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);

    await tester.tap(find.byIcon(Icons.cameraswitch_rounded));
    await tester.pumpAndSettle();
    expect(fake.opened, [CameraLensDirection.back, CameraLensDirection.front]);
    expect(find.byKey(const ValueKey('preview-front')), findsOneWidget);
    expect(fake.disposed, contains(0)); // the first camera was released

    await tester.tap(find.byIcon(Icons.cameraswitch_rounded));
    await tester.pumpAndSettle();
    expect(fake.opened.last, CameraLensDirection.back);
    expect(find.byKey(const ValueKey('preview-back')), findsOneWidget);
  });

  testWidgets('the front preview fills the screen too', (tester) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);
    await tester.tap(find.byIcon(Icons.cameraswitch_rounded));
    await tester.pumpAndSettle();
    final preview = tester.getRect(find.byKey(const ValueKey('preview-front')));
    expect(preview.width, greaterThanOrEqualTo(399.5));
    expect(preview.height, greaterThanOrEqualTo(700));
  });

  testWidgets('a phone with one camera has no flip button', (tester) async {
    await _open(
      tester,
      _FakeCamera(cameras: [_cam('back', CameraLensDirection.back)]),
    );
    expect(find.byIcon(Icons.cameraswitch_rounded), findsNothing);
  });

  testWidgets('proof mode hides the gallery, keeps the flip, and says why', (
    tester,
  ) async {
    await _open(tester, _FakeCamera(cameras: _both), proofMode: true);
    expect(find.text('Verification photo · location on'), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
    expect(find.byIcon(Icons.cameraswitch_rounded), findsOneWidget);
  });

  testWidgets('it also works in a short landscape window', (tester) async {
    await _open(
      tester,
      _FakeCamera(cameras: _both),
      size: const Size(800, 400),
    );
    final preview = tester.getRect(find.byKey(const ValueKey('preview-back')));
    final viewport = tester.getRect(find.byType(ClipRect).first);
    expect(preview.width, greaterThanOrEqualTo(viewport.width - 0.5));
    expect(preview.height, greaterThanOrEqualTo(viewport.height - 0.5));
  });
  testWidgets('every camera control is labelled and big enough', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _FakeCamera(cameras: _both));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('2× zooms in, 1× back out', (tester) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);
    await tester.tap(find.bySemanticsLabel('Zoom 2×'));
    await tester.pump();
    expect(fake.zooms.last, 2);
    expect(find.text('2.0×'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Zoom 1×'));
    await tester.pump();
    expect(fake.zooms.last, 1);
  });

  testWidgets('pinching zooms', (tester) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);
    final a = await tester.startGesture(const Offset(150, 400));
    final b = await tester.startGesture(const Offset(250, 400));
    await tester.pump();
    await a.moveTo(const Offset(100, 400));
    await b.moveTo(const Offset(300, 400));
    await tester.pump();
    await a.up();
    await b.up();
    // Let the double-tap detector's short wait run out.
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.zooms, isNotEmpty);
    // The pinch starts counting once the fingers have moved a little.
    expect(fake.zooms.last, greaterThan(1.2));
  });

  testWidgets('double-tapping the picture flips the camera', (tester) async {
    final fake = _FakeCamera(cameras: _both);
    await _open(tester, fake);
    await tester.tap(find.byKey(const ValueKey('preview-back')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('preview-back')));
    await tester.pumpAndSettle();
    expect(fake.opened.last, CameraLensDirection.front);
  });

  testWidgets('proof mode takes photos only', (tester) async {
    await _open(tester, _FakeCamera(cameras: _both), proofMode: true);
    expect(find.text('VIDEO'), findsNothing);
    expect(find.text('Tap for photo'), findsOneWidget);
  });
}

void boxRatioTests() {
  CameraValue value(Size? size, DeviceOrientation o) =>
      CameraValue.uninitialized(
        _cam('b', CameraLensDirection.back),
      ).copyWith(isInitialized: true, previewSize: size, deviceOrientation: o);

  group('The shape of the camera box', () {
    test('upright phone, landscape sensor: a tall box', () {
      expect(
        previewBoxRatio(
          value(const Size(1280, 720), DeviceOrientation.portraitUp),
        ),
        closeTo(9 / 16, 0.001),
      );
    });
    test('phone on its side: a wide box', () {
      for (final o in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]) {
        expect(
          previewBoxRatio(value(const Size(1280, 720), o)),
          closeTo(16 / 9, 0.001),
        );
      }
    });
    test('upside-down counts as upright', () {
      expect(
        previewBoxRatio(
          value(const Size(1280, 720), DeviceOrientation.portraitDown),
        ),
        closeTo(9 / 16, 0.001),
      );
    });
    test('an unknown or broken size falls back to a sane box', () {
      expect(previewBoxRatio(value(null, DeviceOrientation.portraitUp)), 3 / 4);
      expect(
        previewBoxRatio(value(Size.zero, DeviceOrientation.portraitUp)),
        3 / 4,
      );
    });
  });
}
