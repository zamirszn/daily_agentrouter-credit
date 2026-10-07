import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const kDailyId = 0;
const kSummaryId = 1;
const kRunId = 2; // ongoing progress notification, lives for the whole run
const kTestId = 99; // separate id, so a test never cancels the daily schedule

const _channelId = 'daily_login_v2';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    'Daily login run',
    channelDescription: 'Reminder to run the daily login',
    importance: Importance.max,
    priority: Priority.high,
  ),
);

// Full-screen intent: wakes the screen and opens the app by itself (fallback
// for when the native autostart alarm is blocked by the OS).
const _dailyDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    'Daily login run',
    channelDescription: 'Reminder to run the daily login',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
  ),
);

class Notifier {
  final plugin = FlutterLocalNotificationsPlugin();

  Future<void> init(void Function(NotificationResponse) onTap) async {
    tzdata.initializeTimeZones();
    var name = 'Africa/Lagos';
    try {
      name = await FlutterTimezone.getLocalTimezone();
    } catch (_) {}
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Africa/Lagos'));
    }

    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          'Daily login run',
          description: 'Reminder to run the daily login',
          importance: Importance.max,
        ));
  }

  tz.TZDateTime _nextDaily(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  Future<void> scheduleDaily(int hour, int minute) async {
    final when = _nextDaily(hour, minute);
    Future<void> go(AndroidScheduleMode mode) => plugin.zonedSchedule(
          kDailyId,
          'Daily login run',
          'Starting the login run',
          when,
          _dailyDetails,
          payload: 'run',
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      // exact alarms not permitted: fall back so the schedule still exists
      await go(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> scheduleTest(int seconds) async {
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    Future<void> go(AndroidScheduleMode mode) => plugin.zonedSchedule(
          kTestId,
          'Test run',
          'Tap to start the login run',
          when,
          _details,
          payload: 'test',
          androidScheduleMode: mode,
          // no matchDateTimeComponents: one-off
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      await go(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> cancelTest() => plugin.cancel(kTestId);

  /// Ongoing (non-dismissable) progress notification kept up during the run.
  Future<void> showProgress(String title, String text, {int? done, int? total}) =>
      plugin.show(
        kRunId,
        title,
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'run_progress',
            'Run progress',
            channelDescription: 'Shown while the login run is in progress',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showProgress: true,
            indeterminate: total == null,
            maxProgress: total ?? 0,
            progress: done ?? 0,
            category: AndroidNotificationCategory.progress,
          ),
        ),
        payload: 'open',
      );

  Future<void> clearProgress() => plugin.cancel(kRunId);

  Future<void> showRetry() => plugin.show(kSummaryId, 'Run did not start',
      'Could not open the app in the foreground. Tap to run now.', _details,
      payload: 'run');

  Future<void> showSummary(String text) =>
      plugin.show(kSummaryId, 'Daily login run', text, _details, payload: 'summary');

  Future<List<int>> pendingIds() async =>
      (await plugin.pendingNotificationRequests()).map((e) => e.id).toList();
}