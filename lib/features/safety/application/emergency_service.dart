import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/emergency_contact.dart';

/// SharedPreferences key of the saved contacts (a JSON list).
const emergencyContactsKey = 'emergency_contacts_v1';

/// At most this many contacts: the SOS message goes to all of them at once.
const maxEmergencyContacts = 5;

/// The user's emergency contacts, stored on the phone only.
final emergencyContactsProvider =
    AsyncNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>(
      EmergencyContactsNotifier.new,
    );

class EmergencyContactsNotifier extends AsyncNotifier<List<EmergencyContact>> {
  @override
  Future<List<EmergencyContact>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeContacts(prefs.getString(emergencyContactsKey));
  }

  /// Adds [contact], or replaces the one at [index].
  Future<void> save(EmergencyContact contact, {int? index}) async {
    final current = [...(state.value ?? await future)];
    if (index != null && index >= 0 && index < current.length) {
      current[index] = contact;
    } else {
      if (current.length >= maxEmergencyContacts) return;
      current.add(contact);
    }
    await _write(current);
  }

  /// Puts [contact] back at [index] (Undo after [remove]).
  Future<void> restore(int index, EmergencyContact contact) async {
    final current = [...(state.value ?? await future)];
    if (current.length >= maxEmergencyContacts) return;
    current.insert(index.clamp(0, current.length), contact);
    await _write(current);
  }

  Future<void> remove(int index) async {
    final current = [...(state.value ?? await future)];
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _write(current);
  }

  Future<void> _write(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(emergencyContactsKey, encodeContacts(contacts));
    state = AsyncData(contacts);
  }
}

String encodeContacts(List<EmergencyContact> contacts) =>
    jsonEncode([for (final c in contacts) c.toJson()]);

/// Reads saved contacts; anything unreadable counts as none.
List<EmergencyContact> decodeContacts(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) EmergencyContact.fromJson(item),
    ].where((c) => c.phone.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

/// The SOS text. [position] is the latest fix, or null when there is none;
/// [fixTime] says how old it is. Works offline: SMS needs no internet, and
/// the link opens on the receiver's phone.
String sosMessage({
  required LatLng? position,
  required DateTime now,
  DateTime? fixTime,
}) {
  final buffer = StringBuffer('EMERGENCY! I need help.');
  if (position == null) {
    buffer.write(' My location is not available right now.');
  } else {
    final lat = position.latitude.toStringAsFixed(5);
    final lng = position.longitude.toStringAsFixed(5);
    final age = fixTime == null ? Duration.zero : now.difference(fixTime);
    buffer.write(
      age.inMinutes >= 2
          ? ' My last known location (${age.inMinutes} min ago):'
          : ' My location:',
    );
    buffer.write(
      ' https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng',
    );
    buffer.write(' ($lat, $lng)');
  }
  buffer.write(' Sent from Tabi at ${DateFormat('HH:mm, d MMM').format(now)}.');
  return buffer.toString();
}

/// An `sms:` link to all [phones] with [body] filled in. The body is encoded
/// with `%20` for spaces: SMS apps don't read `+` as a space.
Uri sosSmsUri(List<String> phones, String body) =>
    Uri.parse('sms:${phones.join(',')}?body=${Uri.encodeComponent(body)}');

/// A `tel:` link to dial [number].
Uri dialUri(String number) => Uri(scheme: 'tel', path: number);
