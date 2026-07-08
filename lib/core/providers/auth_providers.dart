import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emits the signed-in user id (null when signed out). Feature providers
/// watch this so per-user state resets on login/logout.
final authUserIdProvider = StreamProvider<String?>((ref) {
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
});
