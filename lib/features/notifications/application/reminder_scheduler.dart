import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';

/// Shows the repeating reminders. Swapped for a fake in tests.
abstract class ReminderScheduler {
  /// Asks to show notifications (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  /// Replaces every reminder with [specs].
  Future<void> apply(List<ReminderSpec> specs);
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalNotificationsScheduler(),
);

/// [ReminderScheduler] on the phone's own notifications. Inexact alarms are
/// used (a few minutes late is fine for a nudge), so no exact-alarm
/// permission is needed. Does nothing where notifications aren't supported.
class LocalNotificationsScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _channel = AndroidNotificationDetails(
    'tabi_reminders',
    'Reminders',
    channelDescription: 'Streak, daily challenge and friends reminders.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> _init() => _ready ??= () async {
    if (!_supported) return false;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(localLocation(DateTime.now().timeZoneOffset));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked when a reminder is turned on, not at start.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return true;
  }();

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> apply(List<ReminderSpec> specs) async {
    if (!await _init()) return;
    for (final id in allReminderIds) {
      await _plugin.cancel(id: id);
    }
    final now = tz.TZDateTime.now(tz.local);
    for (final spec in specs) {
      final next = nextFireTime(spec, now);
      await _plugin.zonedSchedule(
        id: spec.id,
        title: spec.title,
        body: spec.body,
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: spec.weekday == null
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }
}

/// The time-zone location for a UTC [offset]: India's when it matches
/// (+05:30), else the first zone with that offset now, else UTC. Avoids a
/// plugin just to read the phone's zone name.
tz.Location localLocation(Duration offset) {
  final india = tz.getLocation('Asia/Kolkata');
  if (india.currentTimeZone.offset == offset) return india;
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final location in tz.timeZoneDatabase.locations.values) {
    if (location.timeZone(now).offset == offset) {
      return location;
    }
  }
  return tz.UTC;
}
