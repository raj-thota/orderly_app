import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sink that persists one event row. Injected so tests can capture or fail it
/// without a live Supabase client.
typedef EventSink = Future<void> Function(Map<String, dynamic> row);

/// Fire-and-forget funnel telemetry. Every call is best-effort: a slow or
/// failed write must never surface to the user or block a flow, so all errors
/// are swallowed. Rows land in `app_events`, owner-scoped by RLS.
///
/// Never pass PII in [props] -- event names and non-identifying metadata only
/// (e.g. a price), never phone, name, address, or raw amounts.
class EventService {
  EventService({EventSink? sink, String? Function()? currentUserId})
      : _sink = sink ?? _defaultSink,
        _currentUserId = currentUserId ?? _defaultUserId;

  final EventSink _sink;
  final String? Function() _currentUserId;

  static String? _defaultUserId() =>
      Supabase.instance.client.auth.currentUser?.id;

  static Future<void> _defaultSink(Map<String, dynamic> row) async {
    await Supabase.instance.client.from('app_events').insert(row);
  }

  /// Records [name] against the signed-in user. No-op when signed out.
  Future<void> track(String name, {Map<String, dynamic>? props}) async {
    try {
      final userId = _currentUserId();
      if (userId == null) return;
      await _sink({
        'user_id': userId,
        'name': name,
        'props': props ?? const <String, dynamic>{},
      });
    } catch (_) {
      // Telemetry must never break a user flow -- swallow everything,
      // including an uninitialized Supabase client under test.
    }
  }
}

final eventServiceProvider = Provider<EventService>((ref) => EventService());
