/// What the Sightseer Lens says a photo shows (from the server's `/lens`).
class LensAnswer {
  const LensAnswer({
    required this.name,
    required this.summary,
    required this.details,
    required this.confidence,
    this.style,
    this.era,
  });

  final String name;
  final String? style;
  final String? era;
  final String summary;

  /// Up to 3 things to look for right now.
  final List<String> details;

  /// 'high', 'medium' or 'low'.
  final String confidence;

  bool get isUnsure => confidence == 'low';

  factory LensAnswer.fromJson(Map<String, dynamic> json) => LensAnswer(
    name: (json['name'] as String?) ?? 'Unknown',
    style: json['style'] as String?,
    era: json['era'] as String?,
    summary: (json['summary'] as String?) ?? '',
    details: [for (final d in (json['details'] as List?) ?? const []) '$d'],
    confidence: (json['confidence'] as String?) ?? 'low',
  );

  /// The text read aloud by "Listen": each part a sentence.
  String get narration => [
    name,
    if (style != null || era != null) [?style, ?era].join(', '),
    summary,
    if (details.isNotEmpty) 'Look for: ${details.join('; ')}',
  ].map(_sentence).where((p) => p.isNotEmpty).join(' ');

  static String _sentence(String part) {
    final t = part.trim();
    if (t.isEmpty) return t;
    return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
  }
}
