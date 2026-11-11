import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _batterySavingKey = 'battery_saving_mode';

final batterySavingModeProvider =
    AsyncNotifierProvider<BatterySavingModeNotifier, bool>(
      BatterySavingModeNotifier.new,
    );

class BatterySavingModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_batterySavingKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_batterySavingKey, enabled);
    state = AsyncData(enabled);
  }
}
