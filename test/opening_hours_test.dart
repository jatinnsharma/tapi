import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/planner/data/opening_hours_service.dart';
import 'package:real_world_exploration/features/planner/domain/opening_hours.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/stop_hours.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2027-03-01 is a Monday.
DateTime _day(int weekday, [int hour = 12]) => DateTime(2027, 3, weekday, hour);

/// A pretend Overpass that returns [elements] and counts requests.
class _FakeOverpass implements HttpClientAdapter {
  _FakeOverpass(this.elements, {this.fail = false});
  final List<Map<String, Object?>> elements;
  final bool fail;
  final queries = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    queries.add('${options.data}');
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'elements': elements}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _el(
  String type,
  int id,
  String name,
  String hours, {
  double lat = 25.3810,
  double lon = 83.0240,
}) => {
  'type': type,
  'id': id,
  'lat': lat,
  'lon': lon,
  'tags': {'name': name, 'opening_hours': hours},
};

void main() {
  group('parsing', () {
    test('every day, same hours', () {
      final h = OpeningHours.parse('Mo-Su 06:00-21:00')!;
      expect(h.understood, isTrue);
      expect(h.describeDay(3), '6 AM – 9 PM');
      expect(h.summary, '6 AM – 9 PM daily');
      expect(h.closedDays, isEmpty);
    });

    test('closed one day', () {
      final h = OpeningHours.parse('Tu-Su 09:30-17:00; Mo off')!;
      expect(h.describeDay(1), 'Closed');
      expect(h.describeDay(2), '9:30 AM – 5 PM');
      expect(h.summary, '9:30 AM – 5 PM · closed Mon');
      expect(h.closedDays, {1});
    });

    test('days no rule names are closed', () {
      final h = OpeningHours.parse('Sa-Su 10:00-18:00')!;
      expect(h.describeDay(5), 'Closed');
      expect(h.describeDay(6), '10 AM – 6 PM');
    });

    test('times only means every day; split times', () {
      final h = OpeningHours.parse('05:00-12:00,16:00-21:30')!;
      expect(h.describeDay(7), '5 AM – 12 PM, 4 PM – 9:30 PM');
      expect(h.isOpenAt(_day(1, 14)), isFalse); // Afternoon break.
      expect(h.isOpenAt(_day(1, 17)), isTrue);
    });

    test('later rules override earlier ones', () {
      final h = OpeningHours.parse('Mo-Su 09:00-18:00; Fr 09:00-12:00')!;
      expect(h.describeDay(5), '9 AM – 12 PM');
      expect(h.describeDay(4), '9 AM – 6 PM');
    });

    test('day lists, wrap-around ranges and 24/7', () {
      final h = OpeningHours.parse('Mo,We,Fr 10:00-16:00')!;
      expect(h.closedDays, {2, 4, 6, 7});
      final wrap = OpeningHours.parse('Sa-Mo 08:00-20:00')!;
      expect(wrap.closedDays, {2, 3, 4, 5});
      final always = OpeningHours.parse('24/7')!;
      expect(always.isAlwaysOpen, isTrue);
      expect(always.summary, 'Open 24 hours');
    });

    test('past midnight and sunrise to sunset', () {
      final night = OpeningHours.parse('Fr-Sa 20:00-02:00')!;
      expect(night.isOpenAt(DateTime(2027, 3, 6, 1)), isTrue); // Sat 1 AM.
      final sun = OpeningHours.parse('sunrise-sunset')!;
      expect(sun.describeDay(2), 'Sunrise – sunset');
    });

    test('holiday rules are skipped, odd parts mark it not understood', () {
      expect(
        OpeningHours.parse('Mo-Sa 10:00-17:00; PH off')!.understood,
        isTrue,
      );
      final odd = OpeningHours.parse('Mo-Fr 09:00-17:00; Jan-Mar Sa 10:00')!;
      expect(odd.understood, isFalse);
      expect(odd.summary, odd.raw);
    });

    test('nothing usable gives null', () {
      expect(OpeningHours.parse(null), isNull);
      expect(OpeningHours.parse('  '), isNull);
      expect(OpeningHours.parse('by appointment'), isNull);
    });

    test('clock labels', () {
      expect(formatClock(0), '12 AM');
      expect(formatClock(12 * 60), '12 PM');
      expect(formatClock(9 * 60 + 5), '9:05 AM');
      expect(formatClock(25 * 60), '1 AM');
    });
  });

  group('planned visit', () {
    final museum = OpeningHours.parse('Sa-Th 09:00-17:00; Fr off');

    test('closed on the planned weekday', () {
      expect(
        verdictFor(museum, _day(5), 'Morning'),
        HoursVerdict.closedThatDay,
      );
    });

    test('open that day, but not in the evening', () {
      expect(verdictFor(museum, _day(2), 'Evening'), HoursVerdict.wrongTime);
      expect(verdictFor(museum, _day(2), 'Morning'), HoursVerdict.open);
    });

    test('no date or no hours: unknown', () {
      expect(verdictFor(museum, null, 'Morning'), HoursVerdict.unknown);
      expect(verdictFor(null, _day(2), 'Morning'), HoursVerdict.unknown);
    });
  });

  group('OpenStreetMap lookup', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('reads OSM ids from both id styles', () {
      expect(OpeningHoursService.osmIdOf('osm-N123'), ('node', 123));
      expect(OpeningHoursService.osmIdOf('osm-way-45'), ('way', 45));
      expect(OpeningHoursService.osmIdOf('wiki-9'), isNull);
      expect(OpeningHoursService.osmIdOf(null), isNull);
    });

    test('one query covers every stop of the day', () {
      final q = OpeningHoursService.buildQuery([
        (key: 'a', placeId: 'osm-W7', name: 'Fort', lat: 1, lng: 2),
        (key: 'b', placeId: 'wiki-1', name: 'Museum', lat: 3, lng: 4),
      ]);
      expect(q, contains('way(id:7);'));
      expect(q, contains('around:200,1.0,2.0'));
      expect(q, contains('around:200,3.0,4.0'));
      expect('out tags center'.allMatches(q), hasLength(1));
    });

    test('matches by id first, then by name nearby', () {
      final elements = [
        _el('way', 7, 'Ramnagar Fort', 'Mo-Su 10:00-17:00'),
        _el(
          'node',
          1,
          'Archaeological Museum Sarnath',
          'Sa-Th 09:00-17:00; Fr off',
        ),
        _el('node', 2, 'Some Shop', 'Mo-Su 08:00-22:00'),
        _el('node', 3, 'Sarnath Museum', '24/7', lat: 26.5), // Far away.
      ];
      expect(
        OpeningHoursService.matchHours((
          key: 'a',
          placeId: 'osm-W7',
          name: 'Fort',
          lat: 25.381,
          lng: 83.024,
        ), elements),
        'Mo-Su 10:00-17:00',
      );
      expect(
        OpeningHoursService.matchHours((
          key: 'b',
          placeId: 'wiki-1',
          name: 'Sarnath Museum',
          lat: 25.381,
          lng: 83.024,
        ), elements),
        'Sa-Th 09:00-17:00; Fr off',
      );
      expect(
        OpeningHoursService.matchHours((
          key: 'c',
          placeId: null,
          name: 'Dhamek Stupa',
          lat: 25.381,
          lng: 83.024,
        ), elements),
        isNull,
      );
    });

    test('answers are kept, so a second look asks nothing', () async {
      final fake = _FakeOverpass([_el('way', 7, 'Ramnagar Fort', '24/7')]);
      final service = OpeningHoursService(Dio()..httpClientAdapter = fake);
      final stops = [
        (
          key: 'a',
          placeId: 'osm-W7',
          name: 'Ramnagar Fort',
          lat: 25.381,
          lng: 83.024,
        ),
        (key: 'b', placeId: null, name: 'Nowhere', lat: 25.381, lng: 83.024),
      ];
      expect(await service.hoursFor(stops), {'a': '24/7'});
      expect(await service.hoursFor(stops), {'a': '24/7'});
      expect(fake.queries, hasLength(1)); // "Not listed" is kept too.
    });

    test('offline: nothing found, nothing kept', () async {
      final fake = _FakeOverpass(const [], fail: true);
      final service = OpeningHoursService(Dio()..httpClientAdapter = fake);
      final stops = [
        (key: 'a', placeId: 'osm-W7', name: 'Fort', lat: 25.381, lng: 83.024),
      ];
      expect(await service.hoursFor(stops), isEmpty);
      await service.hoursFor(stops);
      expect(fake.queries.length, greaterThan(1)); // Tried again.
    });

    test('day queries survive encoding', () {
      final stops = [
        (key: 'a', placeId: null, name: 'Assi Ghat', lat: 25.2, lng: 83.0),
      ];
      expect(decodeHoursQueries(encodeHoursQueries(stops)), stops);
    });
  });

  test('AI hours survive a JSON round trip', () {
    const stop = TripStop(
      id: 's',
      placeName: 'Sarnath Museum',
      description: '',
      timeSlot: 'Morning',
      durationMinutes: 60,
      latitude: 25.38,
      longitude: 83.02,
      category: 'heritage',
      openingHours: 'Sa-Th 09:00-17:00; Fr off',
    );
    expect(TripStop.fromJson(stop.toJson()).openingHours, stop.openingHours);
    expect(TripStop.fromJson({'openingHours': ''}).openingHours, isNull);
  });

  group('stop card', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

    testWidgets('warns when closed on the planned day, week on tap', (
      tester,
    ) async {
      await pump(
        tester,
        StopHours(
          hours: OpeningHours.parse('Sa-Th 09:00-17:00; Fr off'),
          source: HoursSource.map,
          loading: false,
          plannedDay: _day(5),
          timeSlot: 'Morning',
        ),
      );
      expect(find.text('Closed that day'), findsOneWidget);
      expect(find.textContaining('Friday'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(find.text('Mon'), findsOneWidget);
      expect(find.textContaining('From OpenStreetMap'), findsOneWidget);
    });

    testWidgets('says when it opens if planned too early', (tester) async {
      await pump(
        tester,
        StopHours(
          hours: OpeningHours.parse('Mo-Su 10:00-18:00'),
          source: HoursSource.map,
          loading: false,
          plannedDay: _day(2),
          timeSlot: 'Morning',
        ),
      );
      expect(find.text('Opens 10 AM'), findsOneWidget);
    });

    testWidgets('AI hours are marked approximate', (tester) async {
      await pump(
        tester,
        StopHours(
          hours: OpeningHours.parse('Mo-Su 06:00-21:00'),
          source: HoursSource.ai,
          loading: false,
          plannedDay: null,
          timeSlot: 'Morning',
        ),
      );
      expect(find.text('Approx.'), findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
    });

    testWidgets('loading and not listed', (tester) async {
      await pump(
        tester,
        const StopHours(
          hours: null,
          source: null,
          loading: true,
          plannedDay: null,
          timeSlot: 'Morning',
        ),
      );
      expect(find.text('Checking opening hours…'), findsOneWidget);
      await pump(
        tester,
        const StopHours(
          hours: null,
          source: null,
          loading: false,
          plannedDay: null,
          timeSlot: 'Morning',
        ),
      );
      expect(find.textContaining('not listed'), findsOneWidget);
    });
  });
}
