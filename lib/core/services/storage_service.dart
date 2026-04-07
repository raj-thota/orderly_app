import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
  final _secureStorage = const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _leadsKey = 'leads';

  // =========================
  // 🔐 AUTH (SECURE STORAGE)
  // =========================

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> clear() async {
    await _secureStorage.deleteAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_leadsKey);
  }

  // =========================
  // 📦 LEADS (SHARED PREFS)
  // =========================

  Future<void> saveLeads(List<Map<String, dynamic>> leads) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      leads.map((lead) => _encode(lead)).toList(),
    );

    await prefs.setString(_leadsKey, encoded);
  }

  /// 🔥 ENCODE (handles nested DateTime safely)
  dynamic _encode(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    } else if (value is List) {
      return value.map(_encode).toList();
    } else if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _encode(v)));
    }
    return value;
  }

  // =========================
  // 📥 LOAD LEADS (FIXED)
  // =========================

  Future<List<Map<String, dynamic>>> loadLeads() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_leadsKey);

    if (data == null) return [];

    final decoded = jsonDecode(data) as List;

    return decoded.map<Map<String, dynamic>>((lead) {
      return _decodeMap(Map<String, dynamic>.from(lead));
    }).toList();
  }

  /// 🔥 DECODE MAP SAFELY (KEY FIX)
  Map<String, dynamic> _decodeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is String && value.contains("T")) {
        final parsed = DateTime.tryParse(value);
        return MapEntry(key, parsed ?? value);
      } else if (value is List) {
        return MapEntry(
          key,
          value.map((e) {
            if (e is Map) {
              return _decodeMap(Map<String, dynamic>.from(e));
            }
            return _decode(e);
          }).toList(),
        );
      } else if (value is Map) {
        return MapEntry(
          key,
          _decodeMap(Map<String, dynamic>.from(value)),
        );
      }
      return MapEntry(key, value);
    });
  }

  /// 🔁 fallback decode
  dynamic _decode(dynamic value) {
    if (value is String && value.contains("T")) {
      return DateTime.tryParse(value) ?? value;
    }
    return value;
  }
}