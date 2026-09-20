import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local (on-device) notifications: a daily quest reminder and an on-demand
/// preview. Tapping a notification opens the app and emits its payload on [taps].
class NotificationService {
  NotificationService._();

  static const payloadHome = 'open_home';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _taps = StreamController<String>.broadcast();
  static Stream<String> get taps => _taps.stream;

  static const _dailyId = 100;
  static const _previewId = 101;
  static const _kEnabled = 'notif_daily_enabled';
  static const _kHour = 'notif_daily_hour';
  static const _kMinute = 'notif_daily_minute';

  static final ValueNotifier<bool> dailyEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<TimeOfDay> dailyTime =
      ValueNotifier<TimeOfDay>(const TimeOfDay(hour: 18, minute: 0));

  static bool _ready = false;
  static String? _launchPayload;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'credexa_reminders',
      'Reminders',
      channelDescription: 'Daily quest reminders and previews',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Falls back to UTC; reminders would then follow UTC.
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentAlert: true,
          defaultPresentBadge: true,
          defaultPresentSound: true,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) _taps.add(p);
      },
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchPayload = launch!.notificationResponse?.payload;
    }

    final prefs = await SharedPreferences.getInstance();
    dailyTime.value = TimeOfDay(
      hour: prefs.getInt(_kHour) ?? 18,
      minute: prefs.getInt(_kMinute) ?? 0,
    );
    dailyEnabled.value = prefs.getBool(_kEnabled) ?? false;
    _ready = true;
    if (dailyEnabled.value) await _scheduleDaily();
  }

  /// Payload of the notification that cold-started the app, if any (once).
  static String? consumeLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  /// Asks the user for permission (shows the system prompt the first time).
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (Platform.isIOS || Platform.isMacOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// Schedules a preview notification [seconds] from now. Returns false if the
  /// user has not allowed notifications.
  static Future<bool> sendPreview({int seconds = 5}) async {
    if (!await requestPermission()) return false;
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await _plugin.zonedSchedule(
      id: _previewId,
      title: 'Credexa',
      body: 'Is that post real? Find out in seconds.',
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payloadHome,
    );
    return true;
  }

  static Future<bool> setDailyEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    if (on) {
      if (!await requestPermission()) {
        dailyEnabled.value = false;
        await prefs.setBool(_kEnabled, false);
        return false;
      }
      dailyEnabled.value = true;
      await prefs.setBool(_kEnabled, true);
      await _scheduleDaily();
    } else {
      dailyEnabled.value = false;
      await prefs.setBool(_kEnabled, false);
      await _plugin.cancel(id: _dailyId);
    }
    return true;
  }

  static Future<void> setDailyTime(TimeOfDay t) async {
    dailyTime.value = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kHour, t.hour);
    await prefs.setInt(_kMinute, t.minute);
    if (dailyEnabled.value) await _scheduleDaily();
  }

  /// Call after the daily quest is answered so today's reminder is skipped.
  static Future<void> skipToday() async {
    if (dailyEnabled.value) await _scheduleDaily(skipToday: true);
  }

  static Future<void> _scheduleDaily({bool skipToday = false}) async {
    final t = dailyTime.value;
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (skipToday || !when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: 'Your daily quest is ready',
      body: 'Can you spot the manipulation? It takes under a minute.',
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payloadHome,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
