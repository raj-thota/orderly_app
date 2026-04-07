import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/auth_service.dart';

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user; // 🔥 added

  const AuthState({
    required this.isAuthenticated,
    this.isLoading = false,
    this.user,
  });

  AuthState copyWith({bool? isAuthenticated, bool? isLoading, User? user}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

  AuthController() : super(const AuthState(isAuthenticated: false)) {
    _listenToAuthChanges();
  }

  /// 🔥 LISTEN TO SUPABASE SESSION (CRITICAL)
void _listenToAuthChanges() {
  _supabase.auth.onAuthStateChange.listen((data) {
    final session = data.session;

    print("AUTH EVENT: ${data.event}");
    print("SESSION: $session");

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
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.flutter://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
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
    await _supabase.auth.signOut();

    state = const AuthState(isAuthenticated: false, user: null);
  }
}
