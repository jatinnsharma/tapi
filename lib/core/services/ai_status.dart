import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Gemini API key, injected at build/run time via
/// `--dart-define=GEMINI_API_KEY=AIza...` — never hardcoded in source.
const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// The Gemini model to call. Defaults to Google's `gemini-flash-latest`
/// alias, which always points at the current Flash model (the free tier covers
/// Flash/Flash-Lite), so retired model names can't break the app. Override at
/// run time with `--dart-define=GEMINI_MODEL=<model-id>`.
const String geminiModel = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-flash-latest',
);

/// Whether an API key was supplied. AI screens check this before calling out,
/// so the rest of the app — which is fully usable without AI — keeps working
/// when it hasn't been configured.
final aiReadyProvider = Provider<bool>((ref) => geminiApiKey.isNotEmpty);
