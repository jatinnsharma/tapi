/// Someone the SOS message goes to. Kept on the phone only.
class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.phone,
    this.relationship = '',
  });

  final String name;

  /// As the user typed it, cleaned by [normalizePhone].
  final String phone;

  /// Free text, e.g. "Sister" or "Friend". May be empty.
  final String relationship;

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'relationship': relationship,
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        relationship: (json['relationship'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact &&
      other.name == name &&
      other.phone == phone &&
      other.relationship == relationship;

  @override
  int get hashCode => Object.hash(name, phone, relationship);
}

/// Keeps digits and one leading `+`; drops spaces, dashes and brackets.
/// Returns null when what's left can't be a phone number (under 3 digits or
/// over 15, the international maximum).
String? normalizePhone(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 3 || digits.length > 15) return null;
  return trimmed.startsWith('+') ? '+$digits' : digits;
}
