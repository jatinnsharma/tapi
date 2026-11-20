import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/memories/data/memory_repository.dart';
import 'package:real_world_exploration/features/memories/data/shared_memory_service.dart';
import 'package:real_world_exploration/features/memories/domain/capsule_watch.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/memories/domain/shared_memory.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';

class _Nope implements FirebaseAuth, SocialRepository, MemoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _now = DateTime(2026, 11, 17, 10);
const _ghat = LatLng(25.2900, 83.0060);

SharedMemory _capsule(String id, double metersNorth) =>
    SharedMemory.fromMap(id, {
      'uid': 'u-$id',
      'displayName': 'User $id',
      'type': 'voice',
      'url': 'https://example.com/media/$id',
      'visibility': 'public',
      'createdAt': '2026-11-01T00:00:00Z',
      'caption': 'Capsule $id',
      'latitude': _ghat.latitude + metersNorth / 111195,
      'longitude': _ghat.longitude,
    });

void main() {
  test('the server\'s "voice" type reads as a voice note', () {
    expect(_capsule('a', 0).type, MemoryType.voiceNote);
  });

  test('capsules are announced within 25 m, once, nearest first', () {
    final capsules = [
      _capsule('far', 200),
      _capsule('b', 20),
      _capsule('a', 5),
    ];
    final reached = capsulesToAnnounce(capsules, _ghat);
    expect(reached.map((c) => c.id), ['a', 'b']);
    expect(capsulesToAnnounce(capsules, _ghat, announced: {'a', 'b'}), isEmpty);
  });

  test('nearby capsules are fetched again after 5 min or 300 m', () {
    expect(shouldFetchCapsules(now: _now, here: _ghat), isTrue);
    expect(
      shouldFetchCapsules(
        now: _now,
        here: _ghat,
        lastAt: _now.subtract(const Duration(minutes: 1)),
        lastWhere: _ghat,
      ),
      isFalse,
    );
    expect(
      shouldFetchCapsules(
        now: _now,
        here: _ghat,
        lastAt: _now.subtract(capsuleRefetchAfter),
        lastWhere: _ghat,
      ),
      isTrue,
    );
    expect(
      shouldFetchCapsules(
        now: _now,
        here: LatLng(_ghat.latitude + 400 / 111195, _ghat.longitude),
        lastAt: _now,
        lastWhere: _ghat,
      ),
      isTrue,
    );
  });

  group('leaving a capsule is checked before anything is sent', () {
    final service = SharedMemoryService(Dio(), _Nope(), _Nope(), _Nope());
    Memory note({double? lat = 25.29, Duration age = Duration.zero}) => Memory(
      id: 'note-1',
      type: MemoryType.voiceNote,
      filePath: '/nowhere/note.m4a',
      timestamp: _now.subtract(age),
      latitude: lat,
      longitude: lat == null ? null : 83.0,
    );
    Future<void> leave(Memory m) => service.leaveCapsule(
      memory: m,
      uid: 'me',
      fallbackName: 'me',
      visibility: MemoryVisibility.public,
      now: _now,
    );

    test('it needs the spot', () {
      expect(() => leave(note(lat: null)), throwsA(isA<SharingException>()));
    });

    test('it must be recorded there and then', () {
      expect(
        () => leave(note(age: const Duration(minutes: 3))),
        throwsA(
          isA<SharingException>().having(
            (e) => e.message,
            'message',
            contains('where you leave it'),
          ),
        ),
      );
    });

    test('a missing recording is explained', () {
      expect(
        () => leave(note()),
        throwsA(
          isA<SharingException>().having(
            (e) => e.message,
            'message',
            contains('no longer on this phone'),
          ),
        ),
      );
    });
  });
}
