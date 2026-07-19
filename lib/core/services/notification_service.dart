import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:orderly_app/core/services/follow_up_reminder_planner.dart';
import 'package:orderly_app/core/services/follow_up_reminder_scheduler.dart';
import 'package:orderly_app/core/services/lead_navigation_service.dart';
import 'package:orderly_app/core/services/notification_id_registry.dart';
import 'package:orderly_app/core/services/tap_deduper.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/followups/data/follow_ups_service.dart';
import 'package:orderly_app/main.dart';

/// Static facade over `flutter_local_notifications`. Owns plugin init,
/// permissions, the follow-up reminder scheduler, and tap navigation. All the
/// scheduling *decisions* live in the pure planner/reconcile/scheduler units.
class NotificationService {
  static const String _channelId = 'followup_channel';
  static const String _channelName = 'Follow Ups';
  static const String _channelDescription =
      'Follow-up and overdue lead reminders';
  static const String _migrationFlagKey = 'notif_reconcile_migration_v1_done';

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
  static final TapDeduper _tapDeduper = TapDeduper();

  static bool _initialized = false;
  static bool _canScheduleExactAlarms = true;
  static FollowUpReminderScheduler? _scheduler;
  static String? _pendingLaunchPayload;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

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
      onDidReceiveNotificationResponse: (response) {
        _handleTap(response.payload);
      },
    );

    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyOnce(prefs);

    // Build the scheduler before requesting permissions so a failing permission
    // call can never leave reminder scheduling permanently disabled.
    _scheduler = FollowUpReminderScheduler(
      pendingIds: _pendingIds,
      schedule: _scheduleReminder,
      cancel: (id) => _notifications.cancel(id: id),
      registry: NotificationIdRegistry.load(prefs),
    );

    // Cold-start tap: stash the payload and replay it once the app shell is
    // mounted (see consumePendingLaunchTap). Navigating from here would push
    // onto the splash route and be lost when splash replaces itself.
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _pendingLaunchPayload = launchDetails?.notificationResponse?.payload;
    }

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_notificationChannel);
    await androidPlugin?.requestNotificationsPermission();
    final exactPermission = await androidPlugin?.requestExactAlarmsPermission();
    if (exactPermission != null) {
      _canScheduleExactAlarms = exactPermission;
    }
  }

  /// Replays a notification tap that cold-started the app, once the app shell
  /// (navigator) is mounted. Call from the app shell after the first frame.
  static void consumePendingLaunchTap() {
    final payload = _pendingLaunchPayload;
    if (payload == null) return;
    _pendingLaunchPayload = null;
    _handleTap(payload);
  }

  /// Old-scheme (Object.hash id) notifications can't be matched by the new
  /// registry ids, so clear everything once; the next sync reschedules fresh.
  static Future<void> _migrateLegacyOnce(SharedPreferences prefs) async {
    if (prefs.getBool(_migrationFlagKey) ?? false) return;
    await _notifications.cancelAll();
    await prefs.remove('scheduled_follow_up_lead_ids');
    for (final key in prefs
        .getKeys()
        .where((k) => k.startsWith('follow_up_notification_'))
        .toList()) {
      await prefs.remove(key);
    }
    await prefs.setBool(_migrationFlagKey, true);
  }

  static Future<Set<int>> _pendingIds() async {
    final pending = await _notifications.pendingNotificationRequests();
    return pending.map((r) => r.id).toSet();
  }

  static Future<void> _scheduleReminder(PlannedReminder reminder) async {
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
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: _canScheduleExactAlarms
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
      matchDateTimeComponents:
          reminder.repeatDaily ? DateTimeComponents.time : null,
    );
  }

  /// Reconcile the OS reminder set against [leads] (defaults to the legacy
  /// lead maps). Safe to call from anywhere; runs are serialized. [leads] must
  /// be the COMPLETE desired lead set — reconcile cancels reminders for any
  /// lead not present, so never pass a partial subset.
  static Future<void> syncFollowUpReminders({
    List<Map<String, dynamic>>? leads,
  }) async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    final leadData = leads ?? await EnquiriesService().fetchLegacyMaps();
    await scheduler.sync(leadData);
  }

  /// Entry point used by app lifecycle + save flows. Prefers the follow_ups
  /// table, falling back to legacy leads if it is unavailable.
  static Future<void> checkAndTriggerSmartReminders() async {
    try {
      final followUps = await FollowUpsService().fetchPending();
      final maps = followUps.map((f) => f.toNotificationMap()).toList();
      await syncFollowUpReminders(leads: maps);
    } catch (_) {
      final leads = await EnquiriesService().fetchLegacyMaps();
      await syncFollowUpReminders(leads: leads);
    }
  }

  static void _handleTap(String? payload) {
    if (!_tapDeduper.shouldHandle(payload)) return;
    _navigateToLead(payload!);
  }

  static Future<void> _navigateToLead(String leadId) async {
    // Bounded wait for the navigator to be ready (cold start), then push once.
    for (var attempt = 0; attempt < 20; attempt++) {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(LeadNavigationService.leadDetailRoute({'id': leadId}));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}
