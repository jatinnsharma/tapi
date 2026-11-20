import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An error whose [message] is already written for users (shown as is).
abstract interface class UserFacingError {
  String get message;
}

/// Plain words for any error, for showing to users. Never shows raw
/// exception text: that goes to the debug log instead.
String friendlyError(Object error) {
  debugPrint('Shown to the user as a friendly error: $error');
  if (error is UserFacingError) return error.message;
  if (_isOffline(error)) {
    return 'No connection. Check your internet and try again.';
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' =>
        "You don't have access to this. Try signing in again.",
      'not-found' => 'This is no longer available.',
      'unavailable' || 'deadline-exceeded' =>
        'The server is busy or unreachable. Try again in a moment.',
      _ => 'Something went wrong. Please try again.',
    };
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('camera') && code.contains('denied') ||
        code.contains('permission')) {
      return 'Permission is off. Allow it in your phone settings.';
    }
  }
  return 'Something went wrong. Please try again.';
}

bool _isOffline(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => true,
      _ => error.error is SocketException,
    };
  }
  return false;
}
