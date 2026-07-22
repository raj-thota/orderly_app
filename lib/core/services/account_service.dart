import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Permanent account + data deletion. Calls the `delete-account` edge function,
/// which hard-deletes the auth user (FK cascade removes all owned rows), then
/// signs out locally so the app returns to the intro via RootGate.
class AccountService {
  AccountService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> deleteAccount() async {
    final res = await _supabase.functions.invoke('delete-account');
    if (res.status != 200) {
      throw Exception('delete_failed_${res.status}');
    }
    await _supabase.auth.signOut();
  }
}

final accountServiceProvider = Provider<AccountService>((ref) => AccountService());
