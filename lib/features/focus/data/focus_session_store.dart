import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'focus_snapshot.dart';

/// Persists the active Focus session so it can be resumed after leaving.
class FocusSessionStore {
  FocusSessionStore(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'focus_session_v1';

  Future<void> save(FocusSnapshot snapshot) async {
    await _prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<FocusSnapshot?> read() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return FocusSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() async => _prefs.remove(_key);
}
