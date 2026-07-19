import 'package:shared_preferences/shared_preferences.dart';

/// Stable, collision-free notification ids keyed by "&lt;leadId&gt;:&lt;type&gt;".
///
/// Replaces the old `Object.hash(leadId, type)` scheme, which could collide
/// across different leads and cancel the wrong notification. Ids are assigned
/// from a monotonic counter and persisted so cancels match what was scheduled.
class NotificationIdRegistry {
  NotificationIdRegistry._(this._prefs, this._map, this._counter);

  final SharedPreferences _prefs;
  final Map<String, int> _map;
  int _counter;
  bool _dirty = false;

  static const String _mapKey = 'notif_id_registry_v1';
  static const String _counterKey = 'notif_id_registry_counter_v1';

  static NotificationIdRegistry load(SharedPreferences prefs) {
    final map = <String, int>{};
    for (final entry in prefs.getStringList(_mapKey) ?? const <String>[]) {
      final sep = entry.lastIndexOf('=');
      if (sep <= 0) continue;
      final id = int.tryParse(entry.substring(sep + 1));
      if (id != null) map[entry.substring(0, sep)] = id;
    }
    return NotificationIdRegistry._(prefs, map, prefs.getInt(_counterKey) ?? 0);
  }

  /// Returns the existing id for [leadId]+[type], or assigns the next one.
  /// Synchronous so it can be used as the `idFor` callback during planning;
  /// call [flush] afterwards to persist any newly-assigned ids.
  // Note: keys are joined with ':'; leadId/type must not contain ':'.
  int idFor(String leadId, String type) {
    final key = '$leadId:$type';
    final existing = _map[key];
    if (existing != null) return existing;
    _counter += 1;
    _map[key] = _counter;
    _dirty = true;
    return _counter;
  }

  Future<void> flush() async {
    if (!_dirty) return;
    await _prefs.setInt(_counterKey, _counter);
    await _prefs.setStringList(
      _mapKey,
      _map.entries.map((e) => '${e.key}=${e.value}').toList(),
    );
    _dirty = false;
  }
}
