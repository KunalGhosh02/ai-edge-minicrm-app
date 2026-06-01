import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/cloud/data/repositories/firebase_auth_repository.dart';
import 'package:minicrm/features/cloud/data/repositories/firestore_customer_session_repository.dart';
import 'package:minicrm/features/cloud/domain/entities/auth_user.dart';
import 'package:minicrm/features/cloud/domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(),
);

sealed class AuthStatus extends Equatable {
  const AuthStatus();
  @override
  List<Object?> get props => const [];
}

final class AuthIdle extends AuthStatus {
  const AuthIdle();
}

final class AuthSigningIn extends AuthStatus {
  const AuthSigningIn();
}

final class AuthSignedIn extends AuthStatus {
  const AuthSignedIn(this.user);
  final AuthUser user;
  @override
  List<Object?> get props => [user];
}

final class AuthError extends AuthStatus {
  const AuthError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class AuthUiState extends Equatable {
  const AuthUiState({required this.status});

  const AuthUiState.initial() : status = const AuthIdle();

  final AuthStatus status;

  AuthUiState copyWith({AuthStatus? status}) =>
      AuthUiState(status: status ?? this.status);

  @override
  List<Object?> get props => [status];
}

class AuthController extends Notifier<AuthUiState> {
  StreamSubscription<AuthUser?>? _subscription;

  @override
  AuthUiState build() {
    final repo = ref.watch(authRepositoryProvider);
    unawaited(_subscription?.cancel());
    _subscription = repo.watchCurrentUser().listen(_onUserChanged);
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    final initial = repo.currentUser;
    return AuthUiState(
      status: initial == null ? const AuthIdle() : AuthSignedIn(initial),
    );
  }

  void _onUserChanged(AuthUser? user) {
    if (user == null) {
      if (state.status is! AuthSigningIn) {
        state = state.copyWith(status: const AuthIdle());
      }
    } else {
      state = state.copyWith(status: AuthSignedIn(user));
      unawaited(_ensureUserDoc(user));
    }
  }

  Future<void> _ensureUserDoc(AuthUser user) async {
    try {
      final repo = ref.read(customerSessionRepositoryProvider);
      await repo.ensureUserDoc(user);
    } on Object catch (e) {
      debugPrint('[auth] ensureUserDoc failed: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    if (state.status is AuthSigningIn) return;
    state = state.copyWith(status: const AuthSigningIn());
    try {
      final user = await ref.read(authRepositoryProvider).signInWithGoogle();
      state = state.copyWith(status: AuthSignedIn(user));
    } on Object catch (e) {
      debugPrint('[auth] sign-in failed: $e');
      state = state.copyWith(status: AuthError(_friendlyError(e)));
    }
  }

  Future<void> signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      state = state.copyWith(status: const AuthIdle());
    } on Object catch (e) {
      debugPrint('[auth] sign-out failed: $e');
      state = state.copyWith(status: AuthError(_friendlyError(e)));
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('no-app')) {
      return 'Firebase is not configured. Drop your google-services.json into '
          'android/app/ and rebuild.';
    }
    if (raw.contains('canceled') || raw.contains('cancelled')) {
      return 'Sign-in cancelled.';
    }
    return raw;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthUiState>(AuthController.new);
