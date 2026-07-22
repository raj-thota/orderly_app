import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;

  /// Cryptographically-random nonce. The raw value is sent to Supabase and the
  /// SHA-256 hash to Apple; Supabase re-hashes and compares, which binds the
  /// returned identity token to this request and blocks replay attacks.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => charset[rand.nextInt(charset.length)],
    ).join();
  }

  /// 🍎 APPLE LOGIN (native, iOS). Returns the session-bearing response.
  Future<AuthResponse> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple did not return an identity token.');
    }

    return supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

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
