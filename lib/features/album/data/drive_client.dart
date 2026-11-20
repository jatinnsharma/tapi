import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Something went wrong talking to Google Drive.
class DriveException implements Exception {
  const DriveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The Drive connection expired or was revoked: connect Drive again.
class DriveAuthException extends DriveException {
  const DriveAuthException() : super('Connect Google Drive again.');
}

/// Too many requests: wait and retry later.
class DriveRateLimitException extends DriveException {
  const DriveRateLimitException() : super('Google Drive is busy. Retrying.');
}

/// No connection: retry when back online.
class DriveOfflineException extends DriveException {
  const DriveOfflineException() : super('No connection. Retrying.');
}

/// The file or folder isn't there (deleted in Drive).
class DriveNotFoundException extends DriveException {
  const DriveNotFoundException() : super('Not found in Google Drive.');
}

/// The few Google Drive calls an album needs, with the `drive.file` scope:
/// the app only ever sees files it created.
class DriveClient {
  DriveClient(this._dio, this._accessToken);

  final Dio _dio;

  /// A current access token (from [DriveAuth]).
  final Future<String> Function() _accessToken;

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';

  Future<Options> _auth([Map<String, Object>? extra]) async => Options(
    headers: {'Authorization': 'Bearer ${await _accessToken()}', ...?extra},
  );

  /// Creates a folder and returns its id.
  Future<String> createFolder(String name) => _guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_api/files',
      queryParameters: {'fields': 'id'},
      data: {'name': name, 'mimeType': 'application/vnd.google-apps.folder'},
      options: await _auth(),
    );
    return res.data!['id'] as String;
  });

  /// Whether the folder is still there (not deleted or in the bin).
  Future<bool> folderExists(String id) async {
    try {
      final res = await _guard(
        () async => _dio.get<Map<String, dynamic>>(
          '$_api/files/$id',
          queryParameters: {'fields': 'id,trashed'},
          options: await _auth(),
        ),
      );
      return res.data?['trashed'] != true;
    } on DriveNotFoundException {
      return false;
    }
  }

  /// Uploads a JPEG into [folderId] and returns the new file's id.
  Future<String> uploadJpeg({
    required String folderId,
    required String name,
    required Uint8List bytes,
  }) => _guard(() async {
    const boundary = 'tabi-album-boundary';
    final body = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode({
            'name': name,
            'parents': [folderId],
          })}\r\n'
          '--$boundary\r\n'
          'Content-Type: image/jpeg\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final data = body.takeBytes();
    final res = await _dio.post<Map<String, dynamic>>(
      '$_upload/files',
      queryParameters: {'uploadType': 'multipart', 'fields': 'id'},
      data: Stream.fromIterable([data]),
      options: await _auth({
        Headers.contentTypeHeader: 'multipart/related; boundary=$boundary',
        Headers.contentLengthHeader: data.length,
      }),
    );
    return res.data!['id'] as String;
  });

  /// Lets anyone with the file's id view it. The id is only kept in the
  /// trip's album, which only members can read.
  Future<void> shareByLink(String fileId) => _guard(() async {
    await _dio.post<Object?>(
      '$_api/files/$fileId/permissions',
      data: {'role': 'reader', 'type': 'anyone'},
      options: await _auth(),
    );
  });

  /// Deletes a file; one that's already gone counts as deleted.
  Future<void> delete(String fileId) async {
    try {
      await _guard(() async {
        await _dio.delete<Object?>(
          '$_api/files/$fileId',
          options: await _auth(),
        );
      });
    } on DriveNotFoundException {
      // Already gone.
    }
  }

  /// Turns HTTP and network failures into the exceptions above, so the
  /// queue knows whether to retry, wait or ask to reconnect.
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  static DriveException mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) return const DriveOfflineException();
    if (status == 401) return const DriveAuthException();
    if (status == 404) return const DriveNotFoundException();
    if (status == 429) return const DriveRateLimitException();
    if (status == 403) {
      final reason = e.response?.data.toString() ?? '';
      if (reason.contains('ateLimitExceeded')) {
        return const DriveRateLimitException();
      }
      if (reason.contains('storageQuotaExceeded')) {
        return const DriveException('Your Google Drive is full.');
      }
      return const DriveAuthException();
    }
    if (status >= 500) return const DriveRateLimitException();
    return DriveException('Google Drive said no ($status).');
  }
}
