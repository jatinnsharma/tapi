import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/locations/data/place_photos_service.dart';

/// A pretend Wikimedia: answers each kind of request with what the test says.
class _FakeWikimedia implements HttpClientAdapter {
  _FakeWikimedia({
    this.commonsGeo = const [],
    this.wikiNearby = const [],
    this.wikiArticleImages = const [],
    this.failGeo = false,
  });

  final List<Map<String, Object?>> commonsGeo;
  final List<Map<String, Object?>> wikiNearby;
  final List<Map<String, Object?>> wikiArticleImages;
  final bool failGeo;
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requests.add(uri);
    final q = uri.queryParameters;
    List<Map<String, Object?>> pages;
    if (uri.host == 'commons.wikimedia.org' && q['generator'] == 'geosearch') {
      if (failGeo) {
        return ResponseBody.fromString('oops', 500);
      }
      pages = commonsGeo;
    } else if (uri.host == 'commons.wikimedia.org') {
      pages = const [];
    } else if (q['generator'] == 'geosearch') {
      pages = wikiNearby;
    } else {
      pages = wikiArticleImages;
    }
    return ResponseBody.fromString(
      jsonEncode({
        'query': {'pages': pages},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _file(
  String title, {
  int? index,
  String mime = 'image/jpeg',
}) => {
  'title': title,
  'index': ?index,
  'imageinfo': [
    {
      'mime': mime,
      'url': 'https://upload.test/$title',
      'thumburl': 'https://upload.test/thumb/$title',
      'descriptionurl': 'https://commons.test/$title',
      'extmetadata': {
        'Artist': {'value': '<a href="x">Asha</a>'},
        'LicenseShortName': {'value': 'CC BY-SA 4.0'},
      },
    },
  ],
};

Map<String, Object?> _article(String title, {bool withImage = true}) => {
  'pageid': 42,
  'title': title,
  if (withImage) ...{
    'thumbnail': {'source': 'https://upload.test/lead-$title.jpg'},
    'original': {'source': 'https://upload.test/orig-$title.jpg'},
  },
};

PlacePhotosService _service(_FakeWikimedia fake) =>
    PlacePhotosService(Dio()..httpClientAdapter = fake);

PlaceKey _place({String id = 'osm-1', String name = 'Rock Garden'}) =>
    (id: id, name: name, city: 'Chandigarh', lat: 30.7525, lng: 76.8101);

void main() {
  group('A place with no article of its own', () {
    test('gets photos taken at its location, nearest first', () async {
      final fake = _FakeWikimedia(
        commonsGeo: [
          _file('File:Far.jpg', index: 5),
          _file('File:Near.jpg', index: 1),
        ],
      );
      final photos = await _service(fake).photosFor(_place());
      expect(photos.map((p) => p.title), ['File:Near.jpg', 'File:Far.jpg']);
      expect(photos.first.credit, 'Photo: Asha · CC BY-SA 4.0');
    });

    test('searches around the coordinates it was given', () async {
      final fake = _FakeWikimedia();
      await _service(fake).photosFor(_place());
      final geo = fake.requests.firstWhere(
        (u) =>
            u.host == 'commons.wikimedia.org' &&
            u.queryParameters['generator'] == 'geosearch',
      );
      expect(geo.queryParameters['ggscoord'], '30.7525|76.8101');
      expect(geo.queryParameters['ggsradius'], '200');
    });

    test('uses the lead picture of a nearby article with its name', () async {
      final fake = _FakeWikimedia(
        wikiNearby: [
          _article('Chandigarh Bird Park'),
          _article('Rock Garden of Chandigarh'),
        ],
      );
      final photos = await _service(fake).photosFor(_place());
      expect(photos, hasLength(1));
      expect(photos.single.thumbUrl, contains('Rock Garden of Chandigarh'));
      expect(photos.single.fullUrl, contains('orig-'));
    });

    test('never uses a neighbour\'s article picture', () async {
      final fake = _FakeWikimedia(
        wikiNearby: [_article('Chandigarh Bird Park')],
      );
      expect(await _service(fake).photosFor(_place()), isEmpty);
    });

    test('an article without a picture adds nothing', () async {
      final fake = _FakeWikimedia(
        wikiNearby: [_article('Rock Garden of Chandigarh', withImage: false)],
      );
      expect(await _service(fake).photosFor(_place()), isEmpty);
    });

    test('merges article picture first, then location photos', () async {
      final fake = _FakeWikimedia(
        wikiNearby: [_article('Rock Garden of Chandigarh')],
        commonsGeo: [_file('File:Near.jpg', index: 1)],
      );
      final photos = await _service(fake).photosFor(_place());
      expect(photos.first.title, startsWith('Wikipedia:'));
      expect(photos.last.title, 'File:Near.jpg');
    });

    test('drops logos, maps and non-photos', () async {
      final fake = _FakeWikimedia(
        commonsGeo: [
          _file('File:Rock Garden logo.jpg', index: 1),
          _file('File:Site map.png', index: 2),
          _file('File:Drawing.svg', index: 3, mime: 'image/svg+xml'),
          _file('File:Real photo.jpg', index: 4),
        ],
      );
      final photos = await _service(fake).photosFor(_place());
      expect(photos.map((p) => p.title), ['File:Real photo.jpg']);
    });

    test('one source failing does not lose the others', () async {
      final fake = _FakeWikimedia(
        failGeo: true,
        wikiNearby: [_article('Rock Garden of Chandigarh')],
      );
      final photos = await _service(fake).photosFor(_place());
      expect(photos, hasLength(1));
    });

    test('with nothing found anywhere, returns an empty list', () async {
      expect(await _service(_FakeWikimedia()).photosFor(_place()), isEmpty);
    });
  });

  group('Remembering photos', () {
    test('a place seen before shows its photos without asking again', () async {
      final fake = _FakeWikimedia(commonsGeo: [_file('File:Near.jpg')]);
      final service = _service(fake);
      final first = await service.photosFor(_place());
      final asked = fake.requests.length;
      final again = await service.photosFor(_place());
      expect(again.map((p) => p.title), first.map((p) => p.title));
      expect(fake.requests.length, asked);
    });

    test('nothing found is not remembered, so the next look retries', () async {
      final fake = _FakeWikimedia();
      final service = _service(fake);
      await service.photosFor(_place());
      final asked = fake.requests.length;
      await service.photosFor(_place());
      expect(fake.requests.length, greaterThan(asked));
    });
  });

  group('A Wikipedia place', () {
    test('keeps its article photos first and does not duplicate', () async {
      final fake = _FakeWikimedia(
        wikiArticleImages: [_file('File:Fort.jpg')],
        commonsGeo: [
          _file('File:Fort.jpg', index: 1),
          _file('File:Gate.jpg', index: 2),
        ],
      );
      final photos = await _service(fake)
          .photosFor(_place(id: 'wiki-123', name: 'Mani Majra Fort'));
      expect(photos.map((p) => p.title), ['File:Fort.jpg', 'File:Gate.jpg']);
    });
  });

  group('Matching an article to a place', () {
    bool match(String a, String p) =>
        PlacePhotosService.articleMatchesPlace(a, p);

    test('same name, different spacing or extras', () {
      expect(match('Manimajra Fort', 'Mani Majra Fort'), true);
      expect(match('Rock Garden of Chandigarh', 'Rock Garden'), true);
      expect(match('Sukhna Lake', 'Sukhna Lake, Chandigarh'), true);
    });
    test('a neighbour or a generic name does not match', () {
      expect(match('Chandigarh Bird Park', 'Rock Garden'), false);
      expect(match('Rose Garden', 'Terraced Garden'), false);
      expect(match('Leisure Valley', 'Sector 17 Market'), false);
    });
    test('empty names never match', () {
      expect(match('', 'Rock Garden'), false);
      expect(match('Rock Garden', ''), false);
    });
  });
}
