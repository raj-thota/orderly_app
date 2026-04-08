import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:orderly_app/core/services/lead_navigation_service.dart';
import 'package:orderly_app/core/services/leads_service.dart';
import 'package:orderly_app/main.dart';

class NotificationBuckets {
  const NotificationBuckets({
    required this.overdue,
    required this.today,
    required this.attention,
  });

  final List<Map<String, dynamic>> overdue;
  final List<Map<String, dynamic>> today;
  final List<Map<String, dynamic>> attention;

  int get totalCount => attention.length;
  bool get hasItems => attention.isNotEmpty;
}

class NotificationSuggestion {
  const NotificationSuggestion({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.kind,
    this.lead,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final String kind;
  final Map<String, dynamic>? lead;
}

class NotificationService {
  static const String _channelId = 'followup_channel';
  static const String _channelName = 'Follow Ups';
  static const String _channelDescription =
      'Follow-up and overdue lead reminders';
  static const String _scheduledLeadIdsKey = 'scheduled_follow_up_lead_ids';
  static const int _defaultReminderHour = 9;
  static const AndroidNotificationChannel _notificationChannel =
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static String? _pendingLeadId;
  static bool _canScheduleExactAlarms = true;

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

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(_notificationChannel);
    await androidPlugin?.requestNotificationsPermission();

    final exactPermission = await androidPlugin?.requestExactAlarmsPermission();
    if (exactPermission != null) {
      _canScheduleExactAlarms = exactPermission;
    }
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

  static NotificationBuckets buildBuckets(
    List<Map<String, dynamic>> leads, {
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final overdue = <Map<String, dynamic>>[];
    final today = <Map<String, dynamic>>[];

    for (final lead in leads) {
      if (isOverdueFollowUp(lead, now: currentTime)) {
        overdue.add(lead);
        continue;
      }

      if (isFollowUpToday(lead, now: currentTime)) {
        today.add(lead);
      }
    }

    int sortByFollowUp(Map<String, dynamic> a, Map<String, dynamic> b) {
      final first = parseFollowUpDate(a["follow_up_date"]) ?? DateTime(2100);
      final second = parseFollowUpDate(b["follow_up_date"]) ?? DateTime(2100);
      return first.compareTo(second);
    }

    overdue.sort(sortByFollowUp);
    today.sort(sortByFollowUp);

    return NotificationBuckets(
      overdue: overdue,
      today: today,
      attention: [...overdue, ...today],
    );
  }

  static List<NotificationSuggestion> buildSuggestions(
    List<Map<String, dynamic>> leads, {
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final buckets = buildBuckets(leads, now: currentTime);
    final suggestions = <NotificationSuggestion>[];
    final seenLeadIds = <String>{};

    void addSuggestion(NotificationSuggestion suggestion) {
      final leadId = suggestion.lead?["id"]?.toString();
      if (leadId != null && leadId.isNotEmpty && !seenLeadIds.add(leadId)) {
        return;
      }

      suggestions.add(suggestion);
    }

    for (final lead in buckets.overdue.take(2)) {
      addSuggestion(
        NotificationSuggestion(
          title: 'Overdue follow-up for ${_leadName(lead)}',
          subtitle:
              'This lead slipped past the due date. Call or message them now.',
          actionLabel: 'Open lead',
          kind: 'overdue',
          lead: lead,
        ),
      );
    }

    final hotLead = leads.cast<Map<String, dynamic>>().firstWhere(
      (lead) => _isHighIntentLead(lead) && !_isClosedLead(lead),
      orElse: () => <String, dynamic>{},
    );
    if (hotLead.isNotEmpty) {
      addSuggestion(
        NotificationSuggestion(
          title: 'Hot lead ready for a fast reply',
          subtitle:
              '${_leadName(hotLead)} looks high intent. Sending a quote or closing the loop now can lift conversion.',
          actionLabel: 'Open lead',
          kind: 'hot',
          lead: hotLead,
        ),
      );
    }

    for (final lead in buckets.today.take(2)) {
      addSuggestion(
        NotificationSuggestion(
          title: 'Follow-up due today for ${_leadName(lead)}',
          subtitle:
              'Scheduled ${_friendlyFollowUpLabel(lead, currentTime)}. A quick reply keeps this lead warm.',
          actionLabel: 'Open lead',
          kind: 'today',
          lead: lead,
        ),
      );
    }

    if (suggestions.isEmpty) {
      suggestions.add(
        const NotificationSuggestion(
          title: 'Nothing urgent right now',
          subtitle:
              'Your reminders are in sync. New follow-ups will appear here automatically.',
          actionLabel: 'All clear',
          kind: 'clear',
        ),
      );
    }

    return suggestions.take(4).toList();
  }

  /// 🔔 SCHEDULE
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    String? payload,
    bool repeatDaily = false,
  }) async {
    final scheduledDate = tz.TZDateTime.from(date, tz.local);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      threadIdentifier: 'follow_up_thread',
    );

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: _canScheduleExactAlarms
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
      matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
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
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      threadIdentifier: 'follow_up_thread',
    );

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
        .where(
          (lead) =>
              lead["id"] != null &&
              lead["status"] == "follow" &&
              parseFollowUpDate(lead["follow_up_date"]) != null,
        )
        .map((lead) => lead["id"].toString())
        .toSet();

    for (final removedLeadId in previousLeadIds.where(
      (leadId) => !currentLeadIds.contains(leadId),
    )) {
      await cancel(_notificationId(removedLeadId, "follow_up"));
      await cancel(_notificationId(removedLeadId, "overdue"));
    }

    for (final lead in leadData) {
      final leadId = lead["id"]?.toString();
      final followUpDate = parseFollowUpDate(lead["follow_up_date"]);

      if (leadId == null ||
          followUpDate == null ||
          lead["status"] != "follow") {
        if (leadId != null) {
          await cancel(_notificationId(leadId, "follow_up"));
          await cancel(_notificationId(leadId, "overdue"));
        }
        continue;
      }

      final leadName = (lead["name"] ?? "Customer").toString();
      final followUpNotificationId = _notificationId(leadId, "follow_up");
      final overdueNotificationId = _notificationId(leadId, "overdue");

      if (isOverdueFollowUp(lead, now: currentTime)) {
        await cancel(followUpNotificationId);
        await scheduleNotification(
          id: overdueNotificationId,
          title: 'Overdue follow-up',
          body: '$leadName still needs your attention.',
          date: _nextOverdueReminderTime(currentTime),
          payload: leadId,
          repeatDaily: true,
        );
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
      final notificationTime = _notificationTimeForFollowUp(followUpDate);

      if (notificationTime.isAfter(currentTime)) {
        await scheduleNotification(
          id: followUpNotificationId,
          title: "Follow-up reminder",
          body: "Reach out to $leadName on time.",
          date: notificationTime,
          payload: leadId,
        );
        continue;
      }

      await cancel(followUpNotificationId);

      if (isFollowUpToday(lead, now: currentTime)) {
        await _showOncePerDay(
          prefs: prefs,
          type: "today",
          leadId: leadId,
          day: currentTime,
          id: followUpNotificationId,
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

  static DateTime _notificationTimeForFollowUp(DateTime followUpDate) {
    final hasExplicitTime =
        followUpDate.hour != 0 ||
        followUpDate.minute != 0 ||
        followUpDate.second != 0 ||
        followUpDate.millisecond != 0 ||
        followUpDate.microsecond != 0;

    return hasExplicitTime
        ? followUpDate
        : DateTime(
            followUpDate.year,
            followUpDate.month,
            followUpDate.day,
            _defaultReminderHour,
          );
  }

  static DateTime _nextOverdueReminderTime(DateTime currentTime) {
    final reminderTime = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
      _defaultReminderHour,
    );

    if (reminderTime.isAfter(currentTime)) {
      return reminderTime;
    }

    return reminderTime.add(const Duration(days: 1));
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

  static String _leadName(Map<String, dynamic> lead) {
    return (lead["name"] ?? "Customer").toString().trim();
  }

  static bool _isClosedLead(Map<String, dynamic> lead) {
    return (lead["status"] ?? "").toString().toLowerCase() == "closed";
  }

  static bool _isHighIntentLead(Map<String, dynamic> lead) {
    final intent = (lead["intent"] ?? "").toString().toLowerCase();
    final message = (lead["msg"] ?? "").toString().toLowerCase();

    return intent == "high" ||
        message.contains("price") ||
        message.contains("quote") ||
        message.contains("buy") ||
        message.contains("order");
  }

  static String _friendlyFollowUpLabel(
    Map<String, dynamic> lead,
    DateTime currentTime,
  ) {
    final followUpDate = parseFollowUpDate(lead["follow_up_date"]);
    if (followUpDate == null) {
      return 'today';
    }

    final notificationTime = _notificationTimeForFollowUp(followUpDate);
    final hour = notificationTime.hour % 12 == 0
        ? 12
        : notificationTime.hour % 12;
    final minute = notificationTime.minute.toString().padLeft(2, '0');
    final suffix = notificationTime.hour >= 12 ? 'PM' : 'AM';

    if (notificationTime.year == currentTime.year &&
        notificationTime.month == currentTime.month &&
        notificationTime.day == currentTime.day) {
      return 'for $hour:$minute $suffix';
    }

    return 'soon';
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
