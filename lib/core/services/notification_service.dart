import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:orderly_app/main.dart'; // for navigatorKey
import 'package:orderly_app/shared/components/entry_detail_screen.dart';
import 'package:orderly_app/core/services/leads_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: android, iOS: ios);

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) async {
        final leadId = response.payload;

        if (leadId == null) return;

        final context = navigatorKey.currentContext;
        if (context == null) return;

        /// 🔥 Navigate to detail screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EntryDetailScreen(
              entry: {
                "id": leadId,

                /// minimal — screen will fetch latest
              },
            ),
          ),
        );
      },
    );

    /// 🔥 iOS permission fix
    await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// 🔔 SCHEDULE
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    String? payload,
  }) async {
    final scheduledDate = tz.TZDateTime.from(date, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'followup_channel',
      'Follow Ups',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// ⚡ INSTANT
  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'followup_channel',
      'Follow Ups',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }

  /// ❌ CANCEL
  static Future<void> cancel(int id) async {
    await _notifications.cancel(id: id);
  }

  /// ❌ CANCEL ALL
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// 🧠 SMART REMINDERS
  static Future<void> checkAndTriggerSmartReminders() async {
    final leadsService = LeadsService();
    final leads = await leadsService.fetchLeads();
    final now = DateTime.now();

    final missed = leads.where((lead) {
      if (lead["status"] != "follow" || lead["follow_up_date"] == null) {
        return false;
      }

      final date = DateTime.parse(lead["follow_up_date"]);
      return date.isBefore(now);
    }).toList();

    for (var lead in missed) {
      await showNotification(
        title: "Missed Follow-up 🚨",
        body: "You forgot ${lead["name"]}",
      );
    }
  }
}
