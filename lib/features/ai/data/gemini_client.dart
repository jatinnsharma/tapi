import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/ai_status.dart';

final geminiClientProvider = Provider<GeminiClient>((ref) {
  return GeminiClient(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        // A full itinerary can take Gemini a while to write.
        receiveTimeout: const Duration(seconds: 90),
      ),
    ),
  );
});

/// Thrown instead of calling Gemini when this device has used up its AI
/// allowance. Its message is shown to the user as is.
class AiLimitException implements Exception {
  const AiLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper around the Gemini REST API using `dio`.
///
/// Every call goes through a limiter so a bug, a stuck button or an eager user
/// can't run up the API bill: calls are spaced at least [_minGap] apart, and
/// each device may make at most [_maxPerHour] calls an hour and [_maxPerDay] a
/// day. The counts are kept in shared preferences, so restarting the app
/// doesn't reset them.
class GeminiClient {
  GeminiClient(this._dio);

  final Dio _dio;

  static const _minGap = Duration(seconds: 3);
  static const _maxPerHour = 20;
  static const _maxPerDay = 60;
  static const _callLogKey = 'gemini_call_log_v1';

  /// Shared by every client so the spacing holds app-wide; also chains calls
  /// so two screens asking at once still go out one at a time.
  static Future<void> _queue = Future.value();
  static DateTime? _lastCall;

  /// Waits for its turn and records the call, or throws [AiLimitException].
  Future<void> _takeSlot() {
    final slot = _queue.then((_) async {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final log = [
        for (final s in prefs.getStringList(_callLogKey) ?? const <String>[])
          ?int.tryParse(s),
      ].where((ms) => now.millisecondsSinceEpoch - ms < 86400000).toList();

      final lastHour = log
          .where((ms) => now.millisecondsSinceEpoch - ms < 3600000)
          .length;
      if (log.length >= _maxPerDay) {
        throw const AiLimitException(
          "You've used today's AI suggestions. They'll be back tomorrow.",
        );
      }
      if (lastHour >= _maxPerHour) {
        throw const AiLimitException(
          'Too many AI requests this hour. Please try again a little later.',
        );
      }

      final last = _lastCall;
      if (last != null) {
        final wait = _minGap - now.difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastCall = DateTime.now();
      log.add(_lastCall!.millisecondsSinceEpoch);
      await prefs.setStringList(_callLogKey, [for (final ms in log) '$ms']);
    });
    // A refused slot must not block the ones after it.
    _queue = slot.catchError((_) {});
    return slot;
  }

  /// Sends a single user message with an optional system prompt and returns
  /// Gemini's reply text. Throws [AiLimitException] when the allowance is
  /// used up, and [DioException] on network/API errors.
  Future<String> sendMessage({
    required String userMessage,
    String? systemPrompt,
    int maxTokens = 2000,
    bool json = false,
  }) async {
    await _takeSlot();

    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey';

    final requestBody = {
      if (systemPrompt != null)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
      'contents': [
        {
          'parts': [
            {'text': userMessage},
          ],
        },
      ],
      'generationConfig': {
        'maxOutputTokens': maxTokens,
        // Ask for bare JSON when the caller parses the reply.
        if (json) 'responseMimeType': 'application/json',
      },
    };

    final response = await _dio.post<Map<String, dynamic>>(
      url,
      options: Options(headers: {'content-type': 'application/json'}),
      data: requestBody,
    );

    final candidates = response.data?['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final firstCandidate = candidates.first as Map<String, dynamic>;
      final content = firstCandidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts != null && parts.isNotEmpty) {
        final text = parts.first['text'] as String?;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    }

    throw StateError('Gemini API returned no text content.');
  }
}
