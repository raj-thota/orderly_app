import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;

  String _normalizePhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+')) {
      return cleaned;
    }
    return '+91$cleaned';
  }

  /// 🔥 GOOGLE LOGIN
  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// EMAIL (keep if needed)
  Future<void> signInWithEmail(String email) async {
    await supabase.auth.signInWithOtp(email: email);
  }

  Future<void> sendOtp(String phone) async {
    await supabase.auth.signInWithOtp(phone: _normalizePhone(phone));
  }

  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    return supabase.auth.verifyOTP(
      phone: _normalizePhone(phone),
      token: otp,
      type: OtpType.sms,
    );
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
