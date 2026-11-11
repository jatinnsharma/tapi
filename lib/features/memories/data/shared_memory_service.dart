import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/memories_api.dart';
import '../../../core/services/firebase_status.dart';
import '../../auth/application/auth_service.dart';
import '../../social/data/social_repository.dart';
import '../domain/memory_model.dart';
import '../domain/shared_memory.dart';
import 'memory_repository.dart';

final sharedMemoryServiceProvider = Provider<SharedMemoryService>((ref) {
  return SharedMemoryService(
    Dio(
      BaseOptions(
        baseUrl: memoriesApiUrl,
        // A free server that has been idle takes up to a minute to wake.
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    ),
    ref.watch(firebaseAuthProvider),
    ref.watch(socialRepositoryProvider),
    ref.watch(memoryRepositoryProvider),
  );
});

/// A problem with sharing that is fine to show the user as it is.
class SharingException implements Exception {
  SharingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Shares photos and videos through the memories API (MongoDB for the
/// records, GridFS for the files) and reads what others have shared.
///
/// Who sees a memory is decided by the server: public ones by everyone,
/// friends-only ones by the friends this app names in the request (friendships
/// stay in Firebase). Media links are signed and expire, so the feed is
/// refreshed whenever the screen is opened.
class SharedMemoryService {
  SharedMemoryService(this._dio, this._auth, this._social, this._memories);

  final Dio _dio;
  final FirebaseAuth _auth;
  final SocialRepository _social;
  final MemoryRepository _memories;

  static const _maxBytes = 50 * 1024 * 1024; // matches the server

  /// Photos and videos only: voice notes stay private.
  static bool canShare(Memory m) => m.type != MemoryType.voiceNote;

  Future<Options> _options({Map<String, Object?>? headers}) async {
    if (memoriesApiUrl.isEmpty) {
      throw SharingException(
        'Sharing is not set up yet: the app has no memories server address.',
      );
    }
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) throw SharingException('Sign in to share memories.');
    return Options(headers: {'Authorization': 'Bearer $token', ...?headers});
  }

  /// Turns a failed call into something readable.
  Never _fail(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      throw SharingException(data['error'] as String);
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      throw SharingException(
        'Could not reach the memories server. Check your internet and try again.',
      );
    }
    throw SharingException('The memories server had a problem (${e.message}).');
  }

  /// Uploads [memory] and records it as shared. [onProgress] gets 0..1.
  /// Returns the memory with its sharing details, already saved locally.
  Future<Memory> share({
    required Memory memory,
    required String uid,
    required String fallbackName,
    required MemoryVisibility visibility,
    String? caption,
    String? placeName,
    void Function(double progress)? onProgress,
  }) async {
    if (!canShare(memory)) {
      throw SharingException("Voice notes can't be shared.");
    }
    final file = File(memory.filePath);
    if (!await file.exists()) {
      throw SharingException('The file is no longer on this phone.');
    }
    final length = await file.length();
    if (length > _maxBytes) {
      throw SharingException('That file is over 50 MB, too big to share.');
    }

    final sharedId = memory.sharedId ?? memory.id;
    final profile = await _social.getProfile(uid);
    final finalCaption = caption ?? memory.caption;

    try {
      var done = false;
      // Re-sharing an already shared memory only changes who can see it.
      if (memory.isShared) {
        try {
          await _dio.patch<Object?>(
            '/memories/$sharedId',
            data: {'visibility': visibility.name, 'caption': finalCaption},
            options: await _options(),
          );
          done = true;
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          // The server lost it: upload it again below.
        }
      }
      if (!done) {
        final ext = p.extension(memory.filePath).toLowerCase();
        await _dio.put<Object?>(
          '/memories/$sharedId',
          queryParameters: {
            'type': memory.type.name,
            'visibility': visibility.name,
            'displayName': profile?.displayName ?? fallbackName,
            'createdAt': memory.timestamp.toUtc().toIso8601String(),
            'caption': ?finalCaption,
            'placeName': ?placeName,
            if (memory.latitude != null) 'lat': memory.latitude,
            if (memory.longitude != null) 'lng': memory.longitude,
          },
          data: file.openRead(),
          options: await _options(
            headers: {
              Headers.contentLengthHeader: length,
              Headers.contentTypeHeader: _contentType(ext, memory.type),
            },
          ),
          onSendProgress: (sent, total) {
            if (total > 0) onProgress?.call(sent / total);
          },
        );
      }
    } on DioException catch (e) {
      _fail(e);
    }

    final shared = memory.copyWith(
      caption: caption,
      sharedId: sharedId,
      visibility: visibility,
    );
    await _memories.updateMemory(shared);
    return shared;
  }

  /// Takes a memory offline again: deletes the online copy and the file. The
  /// copy on this phone is untouched.
  Future<Memory> unshare({required Memory memory, required String uid}) async {
    final sharedId = memory.sharedId;
    if (sharedId != null) {
      try {
        await _dio.delete<Object?>(
          '/memories/$sharedId',
          options: await _options(),
        );
      } on DioException catch (e) {
        _fail(e);
      }
    }
    final local = memory.copyWith(clearSharing: true);
    await _memories.updateMemory(local);
    return local;
  }

  /// Deletes everything [uid] has shared (account deletion). Does nothing if
  /// sharing was never set up, so deleting an account still works.
  Future<void> deleteAllFor(String uid) async {
    if (memoriesApiUrl.isEmpty) return;
    try {
      await _dio.delete<Object?>('/memories', options: await _options());
    } on DioException catch (e) {
      _fail(e);
    }
  }

  /// What others have shared that [uid] may see, newest first: either what
  /// their accepted friends shared, or everything public. Blocked people
  /// (either way) are left out.
  Future<List<SharedMemory>> feed({
    required String uid,
    required bool friendsOnly,
  }) async {
    final hidden = {
      ...await _social.getBlockedUids(uid),
      ...await _social.getUidsWhoBlockedMe(uid),
    };

    final query = <String, Object>{'scope': friendsOnly ? 'friends' : 'public'};
    if (friendsOnly) {
      final friendUids = [
        for (final f in await _social.getFriendshipsFor(uid))
          if (f.isAccepted && !hidden.contains(f.otherUid(uid)))
            f.otherUid(uid),
      ];
      if (friendUids.isEmpty) return const [];
      query['friends'] = friendUids.join(',');
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/memories/feed',
        queryParameters: query,
        options: await _options(),
      );
      final list = (response.data?['memories'] as List?) ?? const [];
      final base = memoriesApiUrl.replaceAll(RegExp(r'/+$'), '');
      final memories = <SharedMemory>[];
      for (final raw in list) {
        final map = Map<String, Object?>.from(raw as Map);
        map['url'] = '$base${map['url']}';
        final memory = SharedMemory.fromMap(map['id']! as String, map);
        if (!hidden.contains(memory.uid)) memories.add(memory);
      }
      return memories..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on DioException catch (e) {
      _fail(e);
    }
  }

  static String _contentType(String ext, MemoryType type) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.mov':
        return 'video/quicktime';
      case '.3gp':
        return 'video/3gpp';
      case '.webm':
        return 'video/webm';
      case '.mp4':
        return 'video/mp4';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
    }
    return type == MemoryType.video ? 'video/mp4' : 'image/jpeg';
  }
}

/// A feed of what friends (true) or everyone (false) shared.
final communityMemoriesProvider = FutureProvider.autoDispose
    .family<List<SharedMemory>, bool>((ref, friendsOnly) async {
      if (!ref.watch(firebaseReadyProvider)) return const [];
      final user = ref.watch(authStateProvider).value;
      if (user == null) return const [];
      return ref
          .watch(sharedMemoryServiceProvider)
          .feed(uid: user.uid, friendsOnly: friendsOnly);
    });
