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
  Future<bool> signInWithGoogle() async {
    return supabase.auth.signInWithOAuth(
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

  /// Returns true when the signed-in user already has a business profile.
  Future<bool> hasBusinessProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final existing = await supabase
        .from('business_profile')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

    return existing != null;
  }
}
