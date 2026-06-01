import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/data/repositories/object_box_chat_history_repository.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';

class ChatPersistenceSubscriber {
  ChatPersistenceSubscriber(this._ref);

  final Ref _ref;
  StreamSubscription<ChatEvent>? _subscription;

  void start() {
    if (_subscription != null) return;
    final bus = _ref.read(chatEventBusProvider);
    _subscription = bus.events.listen(_onEvent);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onEvent(ChatEvent event) async {
    if (event.channel != ChatChannel.local) return;
    switch (event) {
      case UserMessageSubmitted():
        await _persistUserMessage(event);
      case AssistantCompleted():
        await _persistAssistantMessage(event);
      case AssistantStarted():
      case AssistantToken():
      case AssistantThinkingToken():
      case AssistantFailed():
        break;
    }
  }

  Future<void> _persistUserMessage(UserMessageSubmitted event) async {
    try {
      final repo = await _ref.read(chatHistoryRepositoryProvider.future);
      await repo.appendMessage(
        threadId: event.threadId,
        message: event.message,
      );
    } on Object catch (e) {
      debugPrint('[persistence] user msg write failed: $e');
    }
  }

  Future<void> _persistAssistantMessage(AssistantCompleted event) async {
    try {
      final repo = await _ref.read(chatHistoryRepositoryProvider.future);
      await repo.upsertMessage(
        threadId: event.threadId,
        message: event.message,
      );
    } on Object catch (e) {
      debugPrint('[persistence] assistant msg write failed: $e');
    }
  }
}

final chatPersistenceSubscriberProvider =
    Provider<ChatPersistenceSubscriber>((ref) {
  final sub = ChatPersistenceSubscriber(ref)..start();
  ref.onDispose(sub.dispose);
  return sub;
});
