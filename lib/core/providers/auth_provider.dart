import 'package:flutter_riverpod/flutter_riverpod.dart';

// Authentication state
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? userId;
  final String? userRole;
  final String? email;
  final String? error;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.userId,
    this.userRole,
    this.email,
    this.error,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? userId,
    String? userRole,
    String? email,
    String? error,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      userRole: userRole ?? this.userRole,
      email: email ?? this.email,
      error: error ?? this.error,
    );
  }
}

// Auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  Future<void> login({
    required String userId,
    required String userRole,
    required String email,
    bool rememberMe = false,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      // Login logic will handle SharedPreferences saving
      state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        userId: userId,
        userRole: userRole,
        email: email,
      );
    } catch (e) {
      state = AuthState(
        isLoading: false,
        isAuthenticated: false,
        error: e.toString(),
      );
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      state = const AuthState(
        isLoading: false,
        isAuthenticated: false,
      );
    } catch (e) {
      state = AuthState(
        isLoading: false,
        isAuthenticated: false,
        error: e.toString(),
      );
    }
  }
}