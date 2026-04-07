import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/services/auth_service.dart';

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

const _userSentinel = Object();

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final supabase.User? user;

  const AuthState({
    required this.isAuthenticated,
    this.isLoading = false,
    this.user,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    Object? user = _userSentinel,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: identical(user, _userSentinel) ? this.user : user as supabase.User?,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();
  final _supabase = supabase.Supabase.instance.client;
  late final StreamSubscription<supabase.AuthState> _authSubscription;

  AuthController() : super(const AuthState(isAuthenticated: false)) {
    _listenToAuthChanges();
  }

  /// 🔥 LISTEN TO SUPABASE SESSION (CRITICAL)
  void _listenToAuthChanges() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;

      state = state.copyWith(
        isAuthenticated: session != null,
        isLoading: false,
        user: session?.user,
      );
    });
  }

  /// 🔍 Check existing session (app start)
  Future<void> checkAuth() async {
    final session = _supabase.auth.currentSession;

    state = state.copyWith(
      isAuthenticated: session != null,
      user: session?.user, // ✅ FIX
    );
  }

  /// 🔑 GOOGLE LOGIN
  Future<void> loginWithGoogle() async {
    state = state.copyWith(isLoading: true);

    try {
      await _authService.signInWithGoogle();
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> sendOtp(String phone) async {
    state = state.copyWith(isLoading: true);

    try {
      await _authService.sendOtp(phone);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<bool> verifyOtp(String phone, String otp) async {
    state = state.copyWith(isLoading: true);

    try {
      final response = await _authService.verifyPhoneOtp(
        phone: phone,
        otp: otp,
      );

      state = state.copyWith(
        isAuthenticated: response.session != null,
        isLoading: false,
        user: response.user,
      );

      return response.session != null;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<void> refreshSession() async {
    final session = _supabase.auth.currentSession;

    state = state.copyWith(
      isAuthenticated: session != null,
      user: session?.user,
      isLoading: false,
    );
  }

  /// 🚪 LOGOUT
  Future<void> logout() async {
    await _authService.logout();

    state = const AuthState(isAuthenticated: false, user: null);
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
