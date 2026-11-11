import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/memories/data/shared_memory_service.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/memories/domain/shared_memory.dart';

Memory _memory({
  MemoryType type = MemoryType.photo,
  String? sharedId,
  MemoryVisibility? visibility,
}) => Memory(
  id: 'm1',
  type: type,
  filePath: '/data/memories/a.jpg',
  timestamp: DateTime.utc(2026, 10, 12, 9, 30),
  latitude: 30.74,
  longitude: 76.82,
  caption: 'Sunrise',
  sharedId: sharedId,
  visibility: visibility,
);

void main() {
  group('Memory sharing state', () {
    test('a new memory is private', () {
      final m = _memory();
      expect(m.isShared, isFalse);
      expect(m.visibility, isNull);
    });

    test('is shared only with both an online id and a visibility', () {
      expect(_memory(sharedId: 's1').isShared, isFalse);
      expect(_memory(visibility: MemoryVisibility.public).isShared, isFalse);
      expect(
        _memory(sharedId: 's1', visibility: MemoryVisibility.friends).isShared,
        isTrue,
      );
    });

    test('copyWith shares, and clearSharing makes it private again', () {
      final shared = _memory().copyWith(
        sharedId: 's1',
        visibility: MemoryVisibility.public,
      );
      expect(shared.isShared, isTrue);
      expect(shared.caption, 'Sunrise'); // untouched fields are kept

      final priv = shared.copyWith(clearSharing: true);
      expect(priv.isShared, isFalse);
      expect(priv.sharedId, isNull);
      expect(priv.visibility, isNull);
    });

    test('survives a round trip through the database map', () {
      final original = _memory(
        type: MemoryType.video,
        sharedId: 's1',
        visibility: MemoryVisibility.friends,
      );
      final back = Memory.fromMap(original.toMap());
      expect(back.type, MemoryType.video);
      expect(back.sharedId, 's1');
      expect(back.visibility, MemoryVisibility.friends);
      expect(back.timestamp, original.timestamp);
    });

    test('rows saved before sharing existed load as private', () {
      final row = _memory().toMap()
        ..remove('shared_id')
        ..remove('visibility');
      expect(Memory.fromMap(row).isShared, isFalse);
    });
  });

  group('MemoryVisibility', () {
    test('has no private value, and ignores unknown names', () {
      expect(MemoryVisibility.fromName('friends'), MemoryVisibility.friends);
      expect(MemoryVisibility.fromName('public'), MemoryVisibility.public);
      expect(MemoryVisibility.fromName('private'), isNull);
      expect(MemoryVisibility.fromName(null), isNull);
    });
  });

  group('SharedMemory', () {
    final data = <String, Object?>{
      'uid': 'u1',
      'displayName': 'Asha',
      'type': 'video',
      'url': 'https://example.com/v.mp4',
      'visibility': 'public',
      'createdAt': '2026-10-12T09:30:00.000Z',
      'caption': 'Sukhna at dawn',
      'latitude': 30.742,
      'longitude': 76.818,
    };

    test('reads a document', () {
      final m = SharedMemory.fromMap('doc1', data);
      expect(m.id, 'doc1');
      expect(m.isVideo, isTrue);
      expect(m.visibility, MemoryVisibility.public);
      expect(m.caption, 'Sukhna at dawn');
      expect(m.createdAt, DateTime.utc(2026, 10, 12, 9, 30));
    });

    test('falls back safely for missing or odd fields', () {
      final m = SharedMemory.fromMap('doc2', {
        'uid': 'u2',
        'url': 'https://example.com/p.jpg',
        'type': 'hologram',
        'visibility': 'secret',
      });
      expect(m.displayName, 'Explorer');
      expect(m.type, MemoryType.photo);
      // An unknown visibility is treated as the narrower one.
      expect(m.visibility, MemoryVisibility.friends);
    });

    test('round-trips through toMap', () {
      final m = SharedMemory.fromMap('doc1', data);
      final again = SharedMemory.fromMap('doc1', m.toMap());
      expect(again.url, m.url);
      expect(again.uid, m.uid);
      expect(again.createdAt, m.createdAt);
    });
  });

  group('SharedMemoryService.canShare', () {
    test('allows photos and videos, never voice notes', () {
      expect(SharedMemoryService.canShare(_memory()), isTrue);
      expect(
        SharedMemoryService.canShare(_memory(type: MemoryType.video)),
        isTrue,
      );
      expect(
        SharedMemoryService.canShare(_memory(type: MemoryType.voiceNote)),
        isFalse,
      );
    });
  });
}
