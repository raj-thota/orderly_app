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
  final String? errorMessage;

  const AuthState({
    required this.isAuthenticated,
    this.isLoading = false,
    this.user,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    Object? user = _userSentinel,
    Object? errorMessage = _userSentinel,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: identical(user, _userSentinel) ? this.user : user as supabase.User?,
      errorMessage: identical(errorMessage, _userSentinel)
          ? this.errorMessage
          : errorMessage as String?,
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
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (data) {
        final session = data.session;

        state = state.copyWith(
          isAuthenticated: session != null,
          isLoading: false,
          user: session?.user,
          errorMessage: null,
        );
      },
      onError: (error, _) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _mapAuthError(error),
        );
      },
    );
  }

  /// 🔍 Check existing session (app start)
  Future<void> checkAuth() async {
    final session = _supabase.auth.currentSession;

    state = state.copyWith(
      isAuthenticated: session != null,
      user: session?.user, // ✅ FIX
      errorMessage: null,
    );
  }

  /// 🔑 GOOGLE LOGIN
  Future<void> loginWithGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final didLaunch = await _authService.signInWithGoogle();

      if (!didLaunch) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Could not open Google sign-in. Please try again.',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _mapAuthError(e));
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

    state = const AuthState(
      isAuthenticated: false,
      user: null,
      errorMessage: null,
    );
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  String _mapAuthError(Object error) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return 'Google sign-in failed. Please try again.';
    }

    final cleaned = message.replaceFirst(RegExp(r'^AuthException\s*\(?'), '');
    return cleaned.replaceFirst(RegExp(r'\)?$'), '');
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
