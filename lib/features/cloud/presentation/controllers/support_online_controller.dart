import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/cloud/data/repositories/firestore_customer_session_repository.dart';
import 'package:minicrm/features/cloud/data/services/support_reactor.dart';
import 'package:minicrm/features/cloud/data/subscribers/cloud_response_subscriber.dart';
import 'package:minicrm/features/cloud/presentation/controllers/auth_controller.dart';
import 'package:minicrm/features/settings/presentation/controllers/settings_controller.dart';

final supportReactorProvider = Provider<SupportReactor>((ref) {
  final reactor = SupportReactor(
    ref.watch(customerSessionRepositoryProvider),
    ref.watch(chatEventBusProvider),
    () async {
      final settings = await ref.read(settingsControllerProvider.future);
      return settings.systemPrompt;
    },
    () async {
      final settings = await ref.read(settingsControllerProvider.future);
      return settings.thinkingEnabled;
    },
  );
  ref.onDispose(() => unawaited(reactor.stop()));
  return reactor;
});

final cloudResponseSubscriberProvider =
    Provider<CloudResponseSubscriber>((ref) {
  final sub = CloudResponseSubscriber(
    ref.watch(chatEventBusProvider),
    ref.watch(customerSessionRepositoryProvider),
    () {
      final status = ref.read(authControllerProvider).status;
      return status is AuthSignedIn ? status.user.uid : null;
    },
  )..start();
  ref.onDispose(sub.dispose);
  return sub;
});

sealed class SupportOnlineStatus extends Equatable {
  const SupportOnlineStatus();
  @override
  List<Object?> get props => const [];
}

final class SupportOffline extends SupportOnlineStatus {
  const SupportOffline();
}

final class SupportConnecting extends SupportOnlineStatus {
  const SupportConnecting();
}

final class SupportOnline extends SupportOnlineStatus {
  const SupportOnline();
}

final class SupportOnlineError extends SupportOnlineStatus {
  const SupportOnlineError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class SupportOnlineUiState extends Equatable {
  const SupportOnlineUiState({required this.status});
  const SupportOnlineUiState.initial() : status = const SupportOffline();

  final SupportOnlineStatus status;

  SupportOnlineUiState copyWith({SupportOnlineStatus? status}) =>
      SupportOnlineUiState(status: status ?? this.status);

  @override
  List<Object?> get props => [status];
}

class SupportOnlineController extends Notifier<SupportOnlineUiState> {
  @override
  SupportOnlineUiState build() {
    ref
      ..watch(cloudResponseSubscriberProvider)
      ..listen<AuthUiState>(authControllerProvider, (prev, next) {
        if (next.status is! AuthSignedIn &&
            state.status is! SupportOffline) {
          unawaited(goOffline());
        }
      });
    return const SupportOnlineUiState.initial();
  }

  Future<void> goOnline() async {
    final auth = ref.read(authControllerProvider).status;
    if (auth is! AuthSignedIn) {
      state = state.copyWith(
        status: const SupportOnlineError('Sign in with Google first.'),
      );
      return;
    }
    state = state.copyWith(status: const SupportConnecting());
    try {
      await ref.read(assistantControllerProvider.notifier).start();
      await ref.read(supportReactorProvider).start(auth.user.uid);
      state = state.copyWith(status: const SupportOnline());
    } on Object catch (e) {
      debugPrint('[support] goOnline failed: $e');
      state = state.copyWith(status: SupportOnlineError(e.toString()));
    }
  }

  Future<void> goOffline() async {
    try {
      await ref.read(supportReactorProvider).stop();
    } on Object catch (e) {
      debugPrint('[support] goOffline failed: $e');
    }
    state = state.copyWith(status: const SupportOffline());
  }
}

final supportOnlineControllerProvider =
    NotifierProvider<SupportOnlineController, SupportOnlineUiState>(
  SupportOnlineController.new,
);
