import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:orderly_app/core/services/lead_navigation_service.dart';
import 'package:orderly_app/core/services/leads_service.dart';
import 'package:orderly_app/main.dart';

class NotificationService {
  static const String _channelId = 'followup_channel';
  static const String _channelName = 'Follow Ups';
  static const String _scheduledLeadIdsKey = 'scheduled_follow_up_lead_ids';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static String? _pendingLeadId;

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
        _queueLeadNavigation(response.payload);
      },
    );

    final launchDetails = await _notifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _queueLeadNavigation(launchDetails?.notificationResponse?.payload);
    }

    /// 🔥 iOS permission fix
    await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static DateTime? parseFollowUpDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static bool isFollowUpToday(Map<String, dynamic> lead, {DateTime? now}) {
    if (lead["status"] != "follow") return false;

    final followUpDate = parseFollowUpDate(lead["follow_up_date"]);
    if (followUpDate == null) return false;

    final currentTime = now ?? DateTime.now();
    return followUpDate.year == currentTime.year &&
        followUpDate.month == currentTime.month &&
        followUpDate.day == currentTime.day;
  }

  static bool isOverdueFollowUp(Map<String, dynamic> lead, {DateTime? now}) {
    if (lead["status"] != "follow") return false;

    final followUpDate = parseFollowUpDate(lead["follow_up_date"]);
    if (followUpDate == null) return false;

    final currentTime = now ?? DateTime.now();
    final startOfToday = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );

    return followUpDate.isBefore(startOfToday);
  }

  static bool needsFollowUpAttention(
    Map<String, dynamic> lead, {
    DateTime? now,
  }) {
    return isFollowUpToday(lead, now: now) || isOverdueFollowUp(lead, now: now);
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
      _channelId,
      _channelName,
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
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
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
    final leads = await LeadsService().fetchLeads();
    await syncLeadNotifications(leads: leads);
  }

  static Future<void> syncLeadNotifications({
    List<Map<String, dynamic>>? leads,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentTime = DateTime.now();
    final leadData = leads ?? await LeadsService().fetchLeads();

    final previousLeadIds =
        prefs.getStringList(_scheduledLeadIdsKey) ?? <String>[];
    final currentLeadIds = leadData
        .map((lead) => lead["id"]?.toString())
        .whereType<String>()
        .toSet();

    for (final removedLeadId in previousLeadIds.where(
      (leadId) => !currentLeadIds.contains(leadId),
    )) {
      await cancel(_notificationId(removedLeadId, "today"));
      await cancel(_notificationId(removedLeadId, "overdue"));
    }

    for (final lead in leadData) {
      final leadId = lead["id"]?.toString();
      final followUpDate = parseFollowUpDate(lead["follow_up_date"]);

      if (leadId == null ||
          followUpDate == null ||
          lead["status"] != "follow") {
        if (leadId != null) {
          await cancel(_notificationId(leadId, "today"));
          await cancel(_notificationId(leadId, "overdue"));
        }
        continue;
      }

      final leadName = (lead["name"] ?? "Customer").toString();
      final todayNotificationId = _notificationId(leadId, "today");
      final overdueNotificationId = _notificationId(leadId, "overdue");

      if (isOverdueFollowUp(lead, now: currentTime)) {
        await cancel(todayNotificationId);
        await _showOncePerDay(
          prefs: prefs,
          type: "overdue",
          leadId: leadId,
          day: currentTime,
          id: overdueNotificationId,
          title: "Overdue follow-up",
          body: "$leadName still needs your attention.",
        );
        continue;
      }

      await cancel(overdueNotificationId);

      if (!isFollowUpToday(lead, now: currentTime)) {
        await cancel(todayNotificationId);
        continue;
      }

      final notificationTime = _notificationTimeForToday(
        followUpDate,
        currentTime,
      );

      if (notificationTime.isAfter(currentTime)) {
        await scheduleNotification(
          id: todayNotificationId,
          title: "Follow-up today",
          body: "Reach out to $leadName today.",
          date: notificationTime,
          payload: leadId,
        );
      } else {
        await cancel(todayNotificationId);
        await _showOncePerDay(
          prefs: prefs,
          type: "today",
          leadId: leadId,
          day: currentTime,
          id: todayNotificationId,
          title: "Follow-up today",
          body: "Reach out to $leadName today.",
        );
      }
    }

    await prefs.setStringList(_scheduledLeadIdsKey, currentLeadIds.toList());
  }

  static Future<void> _showOncePerDay({
    required SharedPreferences prefs,
    required String type,
    required String leadId,
    required DateTime day,
    required int id,
    required String title,
    required String body,
  }) async {
    final receiptKey = _dailyReceiptKey(type, leadId, day);
    if (prefs.getBool(receiptKey) == true) return;

    await showNotification(id: id, title: title, body: body, payload: leadId);
    await prefs.setBool(receiptKey, true);
  }

  static DateTime _notificationTimeForToday(
    DateTime followUpDate,
    DateTime currentTime,
  ) {
    final hasExplicitTime =
        followUpDate.hour != 0 ||
        followUpDate.minute != 0 ||
        followUpDate.second != 0 ||
        followUpDate.millisecond != 0 ||
        followUpDate.microsecond != 0;

    final notificationTime = hasExplicitTime
        ? followUpDate
        : DateTime(followUpDate.year, followUpDate.month, followUpDate.day, 9);

    if (notificationTime.isAfter(currentTime)) {
      return notificationTime;
    }

    return currentTime;
  }

  static String _dailyReceiptKey(String type, String leadId, DateTime date) {
    final dayKey =
        "${date.year.toString().padLeft(4, '0')}-"
        "${date.month.toString().padLeft(2, '0')}-"
        "${date.day.toString().padLeft(2, '0')}";
    return "follow_up_notification_${type}_${leadId}_$dayKey";
  }

  static int _notificationId(String leadId, String type) {
    return Object.hash(leadId, type) & 0x7fffffff;
  }

  static void _queueLeadNavigation(String? leadId) {
    if (leadId == null || leadId.isEmpty) return;

    _pendingLeadId = leadId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;
      final queuedLeadId = _pendingLeadId;

      if (navigator == null || queuedLeadId == null) {
        if (queuedLeadId != null) {
          _queueLeadNavigation(queuedLeadId);
        }
        return;
      }

      _pendingLeadId = null;
      navigator.push(
        LeadNavigationService.leadDetailRoute({"id": queuedLeadId}),
      );
    });
  }
}
