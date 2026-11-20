import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/safety/application/emergency_service.dart';
import 'package:real_world_exploration/features/safety/domain/emergency_contact.dart';
import 'package:real_world_exploration/features/safety/domain/emergency_helplines.dart';
import 'package:real_world_exploration/features/safety/presentation/safety_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SOS message', () {
    final now = DateTime(2026, 11, 17, 18, 5);

    test('carries a map link and the coordinates', () {
      final text = sosMessage(
        position: const LatLng(25.317652, 82.973914),
        now: now,
        fixTime: now,
      );
      expect(text, startsWith('EMERGENCY! I need help. My location:'));
      expect(
        text,
        contains(
          'https://www.openstreetmap.org/?mlat=25.31765&mlon=82.97391'
          '#map=17/25.31765/82.97391',
        ),
      );
      expect(text, contains('18:05, 17 Nov'));
    });

    test('says how old an old fix is', () {
      final text = sosMessage(
        position: const LatLng(25.3, 82.9),
        now: now,
        fixTime: now.subtract(const Duration(minutes: 7)),
      );
      expect(text, contains('My last known location (7 min ago):'));
    });

    test('without a fix it still asks for help', () {
      final text = sosMessage(position: null, now: now);
      expect(text, contains('My location is not available right now.'));
      expect(text, isNot(contains('openstreetmap')));
    });
  });

  test('the SMS link goes to every contact, spaces as %20', () {
    final uri = sosSmsUri(['+919876543210', '9812345678'], 'Help me now');
    expect(uri.toString(), 'sms:+919876543210,9812345678?body=Help%20me%20now');
  });

  test('phone numbers are cleaned, junk is refused', () {
    expect(normalizePhone(' +91 98765-43210 '), '+919876543210');
    expect(normalizePhone('(0172) 274 0000'), '01722740000');
    expect(normalizePhone('112'), '112');
    expect(normalizePhone('12'), isNull);
    expect(normalizePhone('call me'), isNull);
    expect(normalizePhone('1234567890123456'), isNull);
  });

  test('saved contacts round-trip; unreadable data counts as none', () {
    const contacts = [
      EmergencyContact(
        name: 'Priya',
        phone: '+919876543210',
        relationship: 'Sister',
      ),
      EmergencyContact(name: 'Amit', phone: '9812345678'),
    ];
    expect(decodeContacts(encodeContacts(contacts)), contacts);
    expect(decodeContacts(null), isEmpty);
    expect(decodeContacts('not json'), isEmpty);
    expect(decodeContacts('[{"name":"No phone"}]'), isEmpty);
  });

  test('112 leads the helplines', () {
    expect(indiaHelplines.first.number, '112');
    expect(
      indiaHelplines.map((h) => h.number).toSet(),
      hasLength(indiaHelplines.length),
    );
  });

  group('contacts store', () {
    test('adds, edits and removes, at most five', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(emergencyContactsProvider.notifier);
      await container.read(emergencyContactsProvider.future);

      for (var i = 0; i < 6; i++) {
        await notifier.save(EmergencyContact(name: 'C$i', phone: '98000000$i'));
      }
      var saved = container.read(emergencyContactsProvider).value!;
      expect(saved.map((c) => c.name), ['C0', 'C1', 'C2', 'C3', 'C4']);

      await notifier.save(
        const EmergencyContact(name: 'Mum', phone: '9800000000'),
        index: 0,
      );
      await notifier.remove(1);
      saved = container.read(emergencyContactsProvider).value!;
      expect(saved.map((c) => c.name), ['Mum', 'C2', 'C3', 'C4']);

      final prefs = await SharedPreferences.getInstance();
      expect(decodeContacts(prefs.getString(emergencyContactsKey)), saved);
    });
  });

  testWidgets('Safety screen: SOS, empty contacts, helplines', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SafetyScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('No contacts yet'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Emergency (all services)'), 200);
    expect(find.text('Emergency (all services)'), findsOneWidget);
  });

  testWidgets('adding a contact from the Safety screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SafetyScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Priya');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a phone number'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone'),
      '+91 98765 43210',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(
      find.textContaining('Hold SOS to text your location to Priya'),
      findsOneWidget,
    );
  });
}
