import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/ui/friendly_error.dart';
import 'package:real_world_exploration/features/memories/data/shared_memory_service.dart';
import 'package:real_world_exploration/features/offline/data/offline_pack_store.dart';

void main() {
  test('connection problems say so', () {
    const offline = 'No connection. Check your internet and try again.';
    expect(friendlyError(const SocketException('x')), offline);
    expect(
      friendlyError(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      offline,
    );
  });

  test('Firebase errors read as plain words', () {
    expect(
      friendlyError(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      ),
      contains('signing in again'),
    );
    expect(
      friendlyError(FirebaseException(plugin: 'firestore', code: 'weird')),
      'Something went wrong. Please try again.',
    );
  });

  test("the app's own messages pass through; anything else is generic", () {
    expect(
      friendlyError(SharingException('Sign in to share memories.')),
      'Sign in to share memories.',
    );
    expect(
      friendlyError(PackStorageFullException()),
      contains('Delete a city'),
    );
    expect(
      friendlyError(StateError('Bad state: secret internals')),
      'Something went wrong. Please try again.',
    );
  });
}
