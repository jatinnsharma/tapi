import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/ui/confirm_destructive.dart';
import 'package:real_world_exploration/features/safety/application/emergency_service.dart';
import 'package:real_world_exploration/features/safety/domain/emergency_contact.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<bool?> ask(WidgetTester tester, String tap) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmDestructive(
              context,
              title: 'Delete group?',
              message: 'Gone for everyone.',
              confirmLabel: 'Delete group',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Gone for everyone.'), findsOneWidget);
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('confirming returns true', (tester) async {
    expect(await ask(tester, 'Delete group'), isTrue);
  });

  testWidgets('cancelling returns false', (tester) async {
    expect(await ask(tester, 'Cancel'), isFalse);
  });

  testWidgets('the undo snack bar calls back', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUndoSnackBar(
                context,
                message: 'Assi Ghat removed',
                onUndo: () => undone = true,
              ),
              child: const Text('remove'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    expect(undone, isTrue);
  });

  test('a removed contact comes back where it was', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(emergencyContactsProvider.notifier);
    await container.read(emergencyContactsProvider.future);
    for (final n in ['A', 'B', 'C']) {
      await notifier.save(
        EmergencyContact(
          name: n,
          phone: '98000000$n'.replaceAll(RegExp('[A-C]'), '1'),
        ),
      );
    }
    final b = container.read(emergencyContactsProvider).value![1];
    await notifier.remove(1);
    await notifier.restore(1, b);
    expect(
      container.read(emergencyContactsProvider).value!.map((c) => c.name),
      ['A', 'B', 'C'],
    );
  });
}
