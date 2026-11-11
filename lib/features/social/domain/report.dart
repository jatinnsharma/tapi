class UserReport {
  const UserReport({
    required this.reportedUid,
    required this.reportedBy,
    required this.reason,
    required this.createdAt,
  });

  final String reportedUid;
  final String reportedBy;
  final String reason;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'reportedUid': reportedUid,
      'reportedBy': reportedBy,
      'reason': reason,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
