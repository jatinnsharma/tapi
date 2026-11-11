/// Which explorers a ranking compares.
enum RankingScope {
  /// Every explorer (version 1 covers Chandigarh, so: everyone in the city).
  global,

  /// You and your accepted friends.
  friends;

  String get label => this == RankingScope.global ? 'Global' : 'Friends';
}

/// The timeframe of the ranking: This week (resets Mondays) or All-Time.
enum RankingTimeframe {
  thisWeek,
  allTime;

  String get label =>
      this == RankingTimeframe.thisWeek ? 'This Week' : 'All-Time';
}

/// Filter combining scope (global vs friends) and timeframe (this week vs all-time).
class LeaderboardFilter {
  const LeaderboardFilter({
    this.scope = RankingScope.global,
    this.timeframe = RankingTimeframe.thisWeek,
  });

  final RankingScope scope;
  final RankingTimeframe timeframe;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaderboardFilter &&
          runtimeType == other.runtimeType &&
          scope == other.scope &&
          timeframe == other.timeframe;

  @override
  int get hashCode => Object.hash(scope, timeframe);
}

/// One row of a leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.totalXp,
    required this.rank,
    required this.isMe,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final int totalXp;

  /// 1-based. Equal XP shares a rank ("1, 2, 2, 4").
  final int rank;
  final bool isMe;
  final String? photoUrl;
}

/// A ranking plus where the signed-in user stands, even when they're not in
/// the rows shown (the global list only holds the top explorers).
class Leaderboard {
  const Leaderboard({required this.entries, required this.me});

  final List<LeaderboardEntry> entries;

  /// The signed-in user's row; null when they have no profile yet.
  final LeaderboardEntry? me;

  bool get meIsListed => me != null && entries.any((e) => e.isMe);
}

/// Sorts explorers by XP (highest first; ties by name so the order is
/// stable) and gives equal XP the same rank: [1000, 500, 500, 200] ranks
/// as 1, 2, 2, 4.
List<LeaderboardEntry> rankByXp(
  List<({String uid, String name, int xp, String? photoUrl})> explorers, {
  required String myUid,
}) {
  final sorted = [...explorers]
    ..sort((a, b) {
      final byXp = b.xp.compareTo(a.xp);
      return byXp != 0
          ? byXp
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final entries = <LeaderboardEntry>[];
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    final rank = i > 0 && sorted[i - 1].xp == e.xp
        ? entries[i - 1].rank
        : i + 1;
    entries.add(
      LeaderboardEntry(
        uid: e.uid,
        displayName: e.name,
        totalXp: e.xp,
        rank: rank,
        isMe: e.uid == myUid,
        photoUrl: e.photoUrl,
      ),
    );
  }
  return entries;
}
