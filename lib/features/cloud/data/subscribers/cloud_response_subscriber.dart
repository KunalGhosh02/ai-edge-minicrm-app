import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_message.dart';
import 'package:minicrm/features/cloud/domain/repositories/customer_session_repository.dart';

typedef CloudUserIdLookup = String? Function();

class CloudResponseSubscriber {
  CloudResponseSubscriber(this._bus, this._repo, this._userIdLookup);

  final ChatEventBus _bus;
  final CustomerSessionRepository _repo;
  final CloudUserIdLookup _userIdLookup;

  StreamSubscription<ChatEvent>? _subscription;

  void start() {
    if (_subscription != null) return;
    _subscription = _bus.events.listen(_onEvent);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onEvent(ChatEvent event) async {
    if (event.channel != ChatChannel.cloud) return;
    if (event is! AssistantCompleted) return;
    final userId = _userIdLookup();
    if (userId == null) {
      debugPrint(
        '[support] cloud AssistantCompleted seen but no signed-in user; dropping',
      );
      return;
    }
    debugPrint(
      '[support] writing assistant reply to '
      'users/$userId/sessions/${event.threadId}/messages/${event.message.id} '
      '(${event.message.text.length} chars)',
    );
    try {
      await _repo.appendAssistantMessage(
        userId: userId,
        customerId: event.threadId,
        message: CustomerMessage(
          id: event.message.id,
          sender: CustomerSender.assistant,
          text: event.message.text,
          createdAt: event.message.createdAt,
        ),
      );
    } on Object catch (e) {
      debugPrint('[support] cloud response write failed: $e');
    }
  }
}
