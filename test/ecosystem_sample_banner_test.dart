import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/ecosystem/presentation/ecosystem_screen.dart';
import 'package:real_world_exploration/features/ecosystem/presentation/sample_data_banner.dart';

void main() {
  testWidgets('the ecosystem hub says its listings are samples', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EcosystemScreen()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SampleDataBanner), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('sample data')), findsOneWidget);
  });
}
