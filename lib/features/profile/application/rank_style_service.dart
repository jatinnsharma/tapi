import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tracking/data/adventure_repository.dart';
import '../domain/rank_style.dart';

const _equippedKey = 'equipped_rank_style';

/// The user's total XP and the style they have equipped (never a locked one).
class StyleState {
  const StyleState({required this.totalXp, required this.equipped});
  final int totalXp;
  final RankStyle equipped;
}

final rankStyleProvider = FutureProvider.autoDispose<StyleState>((ref) async {
  final xp = await ref.watch(adventureRepositoryProvider).getTotalXp();
  final prefs = await SharedPreferences.getInstance();
  return StyleState(
    totalXp: xp,
    equipped: resolveStyle(prefs.getString(_equippedKey), xp),
  );
});

/// Equips [style] if [totalXp] unlocks it. Returns whether it was equipped.
Future<bool> equipStyle(RankStyle style, int totalXp) async {
  if (!style.isUnlocked(totalXp)) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_equippedKey, style.id);
  return true;
}
