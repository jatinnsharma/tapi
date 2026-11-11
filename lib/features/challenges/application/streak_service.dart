import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tracking/data/adventure_repository.dart';
import '../domain/streak_data.dart';

final streakServiceProvider = Provider<StreakService>((ref) {
  return StreakService(ref.watch(adventureRepositoryProvider));
});

final streakDataProvider = FutureProvider<StreakData>((ref) {
  return ref.watch(streakServiceProvider).getStreakData();
});

class StreakService {
  StreakService(this._repository);

  final AdventureRepository _repository;
  static const String _freezesKey = 'tabi_streak_freezes';
  static const String _lastFreezeDateKey = 'tabi_last_freeze_date';
  static const String _bestStreakKey = 'tabi_best_streak';

  Future<StreakData> getStreakData() async {
    final adventures = await _repository.getCompletedAdventures();
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Unique days with at least one counted completed trip
    final activeDays = <DateTime>{};
    for (final adv in adventures) {
      final date = adv.startedAt.toLocal();
      activeDays.add(DateTime(date.year, date.month, date.day));
    }

    final completedToday = activeDays.contains(today);
    var freezes =
        prefs.getInt(_freezesKey) ?? 1; // Start with 1 complimentary freeze
    final lastFreezeDateStr = prefs.getString(_lastFreezeDateKey);
    final lastFreezeDate = lastFreezeDateStr == null
        ? null
        : DateTime.tryParse(lastFreezeDateStr);

    var currentStreak = 0;
    var checkDay = completedToday ? today : yesterday;
    var freezeUsedToday = false;

    final priorDayToYesterday = yesterday.subtract(const Duration(days: 1));
    final hasPriorStreak = activeDays.contains(priorDayToYesterday);

    // Check consecutive days backwards
    while (true) {
      if (activeDays.contains(checkDay)) {
        currentStreak++;
        checkDay = checkDay.subtract(const Duration(days: 1));
      } else {
        // If missing a day, see if freeze was already used or can be applied for yesterday
        if (checkDay == yesterday &&
            freezes > 0 &&
            lastFreezeDate != yesterday &&
            hasPriorStreak) {
          freezes--;
          await prefs.setInt(_freezesKey, freezes);
          await prefs.setString(
            _lastFreezeDateKey,
            yesterday.toIso8601String(),
          );
          freezeUsedToday = true;
          currentStreak++;
          checkDay = checkDay.subtract(const Duration(days: 1));
          continue;
        } else if (lastFreezeDate == checkDay && hasPriorStreak) {
          // Already frozen day
          currentStreak++;
          checkDay = checkDay.subtract(const Duration(days: 1));
          continue;
        }
        break;
      }
    }

    // Award bonus freeze every 7 days (capped at 3)
    if (currentStreak > 0 && currentStreak % 7 == 0 && freezes < 3) {
      final lastAwardedStreak = prefs.getInt('last_awarded_freeze_streak') ?? 0;
      if (currentStreak > lastAwardedStreak) {
        freezes = (freezes + 1).clamp(0, 3);
        await prefs.setInt(_freezesKey, freezes);
        await prefs.setInt('last_awarded_freeze_streak', currentStreak);
      }
    }

    var bestStreak = prefs.getInt(_bestStreakKey) ?? 0;
    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
      await prefs.setInt(_bestStreakKey, bestStreak);
    }

    return StreakData(
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      completedToday: completedToday,
      freezesAvailable: freezes,
      freezeUsedToday: freezeUsedToday,
    );
  }
}
