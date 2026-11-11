import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/ai/data/gemini_client.dart';
import 'package:real_world_exploration/features/planner/domain/planner_input.dart';
import 'package:real_world_exploration/features/planner/domain/trip_extras.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

TripPlan _plan({
  String destination = 'Varanasi',
  int days = 5,
  TripCompanion companion = TripCompanion.friends,
  TripBudget budget = TripBudget.moderate,
  List<String> interests = const ['Spiritual'],
  DateTime? startDate,
  int? travellers,
}) {
  return TripPlan(
    id: 'trip-1',
    title: '$days Days in $destination',
    destination: destination,
    daysCount: days,
    companion: companion,
    budget: budget,
    interests: interests,
    startDate: startDate,
    travellers: travellers,
    createdAt: DateTime(2026, 10, 17),
    days: const [],
  );
}

/// Answers every Gemini request with a fixed reply, without the network.
class _CannedAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      '{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('formatRupees', () {
    test('uses Indian digit grouping', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(950), '₹950');
      expect(formatRupees(12500), '₹12,500');
      expect(formatRupees(123456), '₹1,23,456');
      expect(formatRupees(12345678), '₹1,23,45,678');
    });
  });

  group('estimateBudget', () {
    test('scales with travellers and nights, and luxury costs more', () {
      final two = estimateBudget(_plan(travellers: 2));
      final four = estimateBudget(_plan(travellers: 4));
      final luxury = estimateBudget(
        _plan(travellers: 2, budget: TripBudget.luxury),
      );
      final shorter = estimateBudget(_plan(travellers: 2, days: 2));

      expect(two.travellers, 2);
      expect(two.low, lessThan(two.high));
      expect(four.low, greaterThan(two.low));
      expect(luxury.low, greaterThan(two.high));
      expect(shorter.high, lessThan(two.high));
    });

    test('defaults travellers from the companion', () {
      expect(_plan(companion: TripCompanion.solo).travellerCount, 1);
      expect(_plan(companion: TripCompanion.family).travellerCount, 4);
      expect(
        _plan(companion: TripCompanion.family, travellers: 3).travellerCount,
        3,
      );
    });
  });

  group('packingListFor', () {
    List<String> items(TripPlan plan) =>
        packingListFor(plan).expand((s) => s.items).toList();

    test('adds seasonal and interest-based items', () {
      final monsoon = items(_plan(startDate: DateTime(2027, 7, 10)));
      expect(monsoon, contains('Umbrella or rain jacket'));
      expect(monsoon, contains('Mosquito repellent'));
      expect(
        monsoon,
        contains('Modest clothes covering shoulders and knees (temples)'),
      );

      final winter = items(_plan(startDate: DateTime(2027, 1, 5)));
      expect(winter, contains('Warm jacket or sweater'));
      expect(winter, isNot(contains('Umbrella or rain jacket')));
    });

    test('items are unique so ticks match after a rebuild', () {
      final list = items(
        _plan(
          startDate: DateTime(2027, 7, 10),
          interests: ['Spiritual', 'Photography', 'Adventure'],
        ),
      );
      expect(list.toSet().length, list.length);
    });
  });

  group('bookingLinksFor', () {
    test('mentions the starting city when known', () {
      final plan = _plan().copyWith(travelingFrom: 'Chandigarh');
      final flights = bookingLinksFor(plan)
          .firstWhere((l) => l.label == 'Flights');
      expect(
        flights.url.queryParameters['q'],
        'flights from Chandigarh to Varanasi',
      );
    });
  });

  group('TripPlan sync fields', () {
    test('survive a JSON round trip', () {
      final plan = _plan(startDate: DateTime(2027, 2, 1), travellers: 3)
          .copyWith(
            travelingFrom: 'Delhi',
            packingChecked: ['Power bank'],
            ownerUid: 'me',
            memberUids: ['me', 'friend'],
            updatedAt: DateTime(2026, 10, 18, 9),
            cloudSynced: true,
          );
      final back = TripPlan.fromJson(plan.toJson());
      expect(back.travelingFrom, 'Delhi');
      expect(back.travellers, 3);
      expect(back.packingChecked, ['Power bank']);
      expect(back.ownerUid, 'me');
      expect(back.memberUids, ['me', 'friend']);
      expect(back.isShared, isTrue);
      expect(back.isOwnedBy('friend'), isFalse);
      expect(back.updatedAt, DateTime(2026, 10, 18, 9));
      expect(back.cloudSynced, isTrue);
    });

    test('older saved trips without the fields still load', () {
      final json = _plan().toJson()
        ..remove('ownerUid')
        ..remove('memberUids')
        ..remove('updatedAt')
        ..remove('cloudSynced')
        ..remove('packingChecked');
      final back = TripPlan.fromJson(json);
      expect(back.memberUids, isEmpty);
      expect(back.cloudSynced, isFalse);
      expect(back.isOwnedBy('anyone'), isTrue);
      expect(back.lastChanged, back.createdAt);
    });
  });

  group('GeminiClient limiter', () {
    test(
      'refuses calls past the hourly allowance without hitting the API',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          'gemini_call_log_v1': [
            for (var i = 0; i < 20; i++) '${now - i * 1000}',
          ],
        });
        final adapter = _CannedAdapter();
        final client = GeminiClient(Dio()..httpClientAdapter = adapter);

        await expectLater(
          client.sendMessage(userMessage: 'hi'),
          throwsA(isA<AiLimitException>()),
        );
        expect(adapter.calls, 0);
      },
    );

    test('allows calls under the allowance and records them', () async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _CannedAdapter();
      final client = GeminiClient(Dio()..httpClientAdapter = adapter);

      expect(await client.sendMessage(userMessage: 'hi'), 'ok');
      expect(adapter.calls, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('gemini_call_log_v1'), hasLength(1));
    });
  });
}
