import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/memories_api.dart';
import '../../auth/application/auth_service.dart';
import '../domain/lens_answer.dart';
import '../../../core/ui/friendly_error.dart';

/// Largest photo sent (the server allows 4 MB).
const lensMaxBytes = 4 * 1024 * 1024;

final lensServiceProvider = Provider<LensService>(
  (ref) => LensService(
    Dio(
      BaseOptions(
        baseUrl: memoriesApiUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    ),
    ref.watch(firebaseAuthProvider),
  ),
);

/// A lens problem fine to show the user as it is.
class LensException implements Exception, UserFacingError {
  LensException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

/// Asks the server's Sightseer Lens what a photo shows. The Gemini key is
/// the server's; the app only sends the photo with the user's login.
class LensService {
  LensService(this._dio, this._auth);

  final Dio _dio;
  final FirebaseAuth _auth;

  Future<LensAnswer> identify(
    Uint8List photo, {
    double? latitude,
    double? longitude,
    String? near,
    String contentType = 'image/jpeg',
  }) async {
    if (memoriesApiUrl.isEmpty) {
      throw LensException("The lens isn't available in this version yet.");
    }
    if (photo.length > lensMaxBytes) {
      throw LensException('That photo is too big. Try again.');
    }
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) throw LensException('Sign in to use the lens.');
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/lens',
        queryParameters: {'lat': ?latitude, 'lng': ?longitude, 'near': ?near},
        data: Stream.fromIterable([photo]),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            Headers.contentTypeHeader: contentType,
            Headers.contentLengthHeader: photo.length,
          },
        ),
      );
      return LensAnswer.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        throw LensException(data['error'] as String);
      }
      throw LensException(
        'Could not reach the lens. Check your internet and try again.',
      );
    }
  }
}
