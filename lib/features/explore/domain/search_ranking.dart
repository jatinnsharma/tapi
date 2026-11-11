import 'dart:math' as math;

/// How well a search query matches names: forgiving of case, punctuation,
/// spacing, small typos ("varansi") and old city names ("Banaras",
/// "Bombay").

/// Lowercase letters and digits with single spaces; keeps Devanagari.
String normalizeForSearch(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ]+'), ' ').trim();

/// Other names people search Indian cities by, keyed by the catalog name.
const cityAliases = <String, List<String>>{
  'Varanasi': ['banaras', 'benares', 'benaras', 'kashi'],
  'Mumbai': ['bombay'],
  'Bengaluru': ['bangalore', 'banglore'],
  'Chennai': ['madras'],
  'Kolkata': ['calcutta'],
  'Gurugram': ['gurgaon'],
  'Pune': ['poona'],
  'Kovalam & Trivandrum': ['thiruvananthapuram'],
  'Kochi': ['cochin', 'ernakulam'],
  'Mysuru': ['mysore'],
  'Pondicherry & Auroville': ['puducherry', 'pondy'],
  'Shimla': ['simla'],
  'Vadodara': ['baroda'],
  'Prayagraj': ['allahabad'],
  'Ooty & Coonoor': ['udhagamandalam', 'ootacamund'],
  'Kanyakumari': ['cape comorin'],
  'Visakhapatnam': ['vizag', 'vishakhapatnam'],
  'Puri': ['jagannath puri'],
  'New Delhi': ['dilli'],
  'Panaji (Goa)': ['panjim'],
  'Bhubaneswar': ['bhubaneshwar'],
  'Mathura & Vrindavan': ['brindavan'],
  'Rameswaram & Dhanushkodi': ['rameshwaram'],
  'Havelock Island (Swaraj Dweep)': ['havelock'],
  'Port Blair': ['andaman'],
  'Gangtok': ['sikkim'],
  'Leh': ['ladakh'],
  'Bodh Gaya': ['bodhgaya'],
  'Mount Abu': ['mt abu'],
  'Katra (Vaishno Devi)': ['vaishnodevi'],
};

/// Typos allowed for a word of [length]: none for short words, one from 4
/// letters, two from 8.
int allowedTypos(int length) => length >= 8 ? 2 : (length >= 4 ? 1 : 0);

/// Edit distance with adjacent swaps ("varnasi"), stopping early once it
/// exceeds [max].
int editDistance(String a, String b, {int max = 3}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prevPrev = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, prevPrev[j - 2] + 1);
      }
      cur[j] = v;
      rowMin = math.min(rowMin, v);
    }
    if (rowMin > max) return max + 1;
    prevPrev = prev;
    prev = cur;
  }
  return prev[b.length];
}

/// 0–100: how well [query] matches [name]. 0 means no match.
///  100 exact · 90 starts with · 80 a word starts with · 70 every word, any
///  order · 65 contains ·
///  55 close spelling of the whole name or a word · 50 close spelling of
///  the start.
int nameScore(String query, String name) {
  final q = normalizeForSearch(query);
  final n = normalizeForSearch(name);
  if (q.isEmpty || n.isEmpty) return 0;
  if (n == q) return 100;
  if (n.startsWith(q)) return 90;
  final words = n.split(' ');
  if (words.any((w) => w.startsWith(q))) return 80;
  // Every typed word in the name, any order: "sarnath museum" for
  // "Archaeological Museum Sarnath".
  final queryWords = q.split(' ').where((w) => w.length >= 3).toList();
  if (queryWords.length >= 2 &&
      queryWords.every((qw) => words.any((w) => w.startsWith(qw)))) {
    return 70;
  }
  if (q.length >= 3 && n.contains(q)) return 65;

  final typos = allowedTypos(q.length);
  if (typos == 0) return 0;
  if (editDistance(q, n, max: typos) <= typos) return 55;
  for (final w in words) {
    if (editDistance(q, w, max: typos) <= typos) return 55;
  }
  // Typing the start of a name with a typo: "varn" for "varanasi".
  if (q.length >= 4 && n.length > q.length) {
    if (editDistance(q, n.substring(0, q.length), max: typos) <= typos) {
      return 50;
    }
  }
  return 0;
}

/// Score for a catalog city: its name, then its other names, then the state
/// and the kind of place (both weaker, so "Rajasthan" lists its cities below
/// any city actually named like the query).
int cityScore(
  String query, {
  required String name,
  required String state,
  required String category,
}) {
  final byName = nameScore(query, name);
  if (byName >= 90) return byName;
  var best = byName;
  for (final alias in cityAliases[name] ?? const <String>[]) {
    final s = nameScore(query, alias);
    // An exact old name is as good as the real one.
    final asAlias = s == 100 ? 95 : (s * 0.9).round();
    if (asAlias > best) best = asAlias;
  }
  final byState = (nameScore(query, state) * 0.4).round();
  final byCategory = normalizeForSearch(category) == normalizeForSearch(query)
      ? 30
      : 0;
  return [best, byState, byCategory].reduce(math.max);
}

/// The part of [text] that matches [query] case-insensitively, for
/// highlighting, or null.
({int start, int end})? matchRange(String query, String text) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return null;
  final i = text.toLowerCase().indexOf(q);
  return i < 0 ? null : (start: i, end: i + q.length);
}
