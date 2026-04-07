import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;

  /// 🔥 GOOGLE LOGIN
  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback',
    );
  }

  /// EMAIL (keep if needed)
  Future<void> signInWithEmail(String email) async {
    await supabase.auth.signInWithOtp(email: email);
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }

  Future<void> ensureUserProfile() async {
    final user = supabase.auth.currentUser;

    if (user == null) return;

    final existing = await supabase
        .from('users')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) return;

    final meta = user.userMetadata;

    await supabase.from('users').insert({
      "id": user.id,
      "email": user.email,
      "avatar": meta?['avatar_url'],
      "business_name": meta?['full_name'] ?? meta?['name'],
      "created_at": DateTime.now().toIso8601String(),
    });
  }
}
