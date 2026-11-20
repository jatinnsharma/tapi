import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/lens/data/lens_service.dart';
import 'package:real_world_exploration/features/lens/domain/lens_answer.dart';
import 'package:real_world_exploration/features/lens/presentation/lens_screen.dart';

class _NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final answer = LensAnswer.fromJson({
    'name': 'Nataraja bronze',
    'style': 'Chola',
    'era': '11th century',
    'summary': 'Shiva as the cosmic dancer.',
    'details': ['The ring of fire', 'The dwarf underfoot'],
    'confidence': 'high',
  });

  test('reads the server answer', () {
    expect(answer.name, 'Nataraja bronze');
    expect(answer.details, hasLength(2));
    expect(answer.isUnsure, isFalse);
    expect(LensAnswer.fromJson({'name': 'x', 'summary': 'y'}).isUnsure, isTrue);
  });

  test('narration reads name, style, story and details', () {
    expect(
      answer.narration,
      'Nataraja bronze. Chola, 11th century. Shiva as the cosmic dancer. '
      'Look for: The ring of fire; The dwarf underfoot.',
    );
  });

  test('without a server address the lens says it is not set up', () {
    // MEMORIES_API_URL is not defined in tests.
    final service = LensService(Dio(), _NoAuth());
    expect(
      () => service.identify(Uint8List(10)),
      throwsA(
        isA<LensException>().having(
          (e) => e.message,
          'm',
          contains("isn't available"),
        ),
      ),
    );
  });

  testWidgets('starts by explaining what the lens does', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LensScreen(near: 'Assi Ghat')),
      ),
    );
    expect(find.text('What am I looking at?'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
  });
}
