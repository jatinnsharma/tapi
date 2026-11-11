import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/map/person_marker.dart';
import 'package:real_world_exploration/features/profile/application/rank_style_service.dart';
import 'package:real_world_exploration/features/profile/domain/rank_style.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      rankStyleProvider.overrideWith(
        (ref) async => StyleState(totalXp: 0, equipped: rankStyles.first),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets('shows the person\'s initial', (tester) async {
    await _pump(tester, const PersonMarker(initial: 'jatin'));
    await tester.pumpAndSettle();
    expect(find.text('J'), findsOneWidget);
    expect(find.bySemanticsLabel('You are here'), findsOneWidget);
  });

  testWidgets('without a name it shows a person icon', (tester) async {
    await _pump(tester, const PersonMarker(initial: ''));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('fits its marker box', (tester) async {
    await _pump(
      tester,
      SizedBox.fromSize(
        size: personMarkerSize,
        child: const PersonMarker(initial: 'A'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('the marker points at the spot from above', () {
    const here = LatLng(30.73, 76.77);
    final m = personMarker(here);
    expect(m.point, here);
    expect(m.alignment, Alignment.topCenter);
    expect(startMarker(here).alignment, Alignment.topCenter);
  });

  testWidgets('the start pin reads Start', (tester) async {
    await _pump(tester, const StartPin());
    expect(find.text('Start'), findsOneWidget);
    expect(find.bySemanticsLabel('Trip start'), findsOneWidget);
  });
}
