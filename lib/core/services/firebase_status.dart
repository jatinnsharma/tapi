import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether `Firebase.initializeApp()` succeeded at startup. Overridden in
/// `main.dart` once that call has run. Screens that need Firebase (auth,
/// social) check this before touching any Firebase API, so the rest of the
/// app — which is fully local-first — keeps working even if Firebase hasn't
/// been configured yet (see PENDING_TASKS.md for setup steps).
final firebaseReadyProvider = Provider<bool>((ref) => false);
