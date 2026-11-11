import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/memories/presentation/camera_screen.dart';

void main() {
  cameraOrderTests();

  Future<void> pumpLayout(WidgetTester tester, {required Size screen}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Capture Memory')),
          // The same structure the camera screen uses.
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: CoverPreview(
                  aspectRatio: 3 / 4,
                  child: Container(
                    key: const Key('preview'),
                    color: Colors.grey,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: FloatingActionButton.large(
                    key: const Key('shutter'),
                    onPressed: () {},
                    child: const Icon(Icons.camera_alt),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('the preview fills the whole body, not a corner', (tester) async {
    await pumpLayout(tester, screen: const Size(400, 800));
    final body = tester.getRect(find.byType(Stack).first);
    final clip = tester.getRect(find.byType(ClipRect).first);
    expect(clip.width, body.width);
    expect(clip.height, body.height);
    expect(body.width, 400);
    expect(body.height, greaterThan(700));
  });

  testWidgets('the capture button sits at the bottom centre', (tester) async {
    await pumpLayout(tester, screen: const Size(400, 800));
    final shutter = tester.getCenter(find.byKey(const Key('shutter')));
    expect(shutter.dx, closeTo(200, 1));
    expect(shutter.dy, greaterThan(650));
  });

  testWidgets('a wide or a tall screen is covered without bars', (
    tester,
  ) async {
    for (final size in const [Size(400, 900), Size(800, 500), Size(360, 640)]) {
      await pumpLayout(tester, screen: size);
      final clip = tester.getRect(find.byType(ClipRect).first);
      expect(clip.width, size.width);
      expect(clip.height, greaterThan(size.height * 0.7));
    }
  });
}

CameraDescription _cam(String name, CameraLensDirection d) =>
    CameraDescription(name: name, lensDirection: d, sensorOrientation: 90);

void cameraOrderTests() {
  group('Choosing cameras', () {
    test('the back camera comes first, then the front', () {
      final sorted = sortCameras([
        _cam('front', CameraLensDirection.front),
        _cam('back', CameraLensDirection.back),
      ]);
      expect(sorted.map((c) => c.name), ['back', 'front']);
    });

    test('several back lenses still flip back <-> front', () {
      final sorted = sortCameras([
        _cam('wide', CameraLensDirection.back),
        _cam('ultra', CameraLensDirection.back),
        _cam('tele', CameraLensDirection.back),
        _cam('selfie', CameraLensDirection.front),
      ]);
      expect(sorted.map((c) => c.name), ['wide', 'selfie']);
    });

    test('a phone with one camera has nothing to flip to', () {
      expect(
        sortCameras([_cam('only', CameraLensDirection.back)]),
        hasLength(1),
      );
      expect(
        sortCameras([_cam('only', CameraLensDirection.front)]),
        hasLength(1),
      );
    });

    test('no cameras gives an empty list', () {
      expect(sortCameras(const []), isEmpty);
    });
  });
}
