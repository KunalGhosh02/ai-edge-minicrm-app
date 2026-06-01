import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';
import 'package:minicrm/features/assistant/domain/repositories/rag_retriever.dart';
import 'package:uuid/uuid.dart';

const _kCloudFallbackReply =
    'Thanks for your message! Our team will get back to you shortly.';

class LlmDriverSubscriber {
  LlmDriverSubscriber(this._bus, this._service, this._retriever);

  static const _uuid = Uuid();

  final ChatEventBus _bus;
  final AssistantService _service;
  final RagRetriever _retriever;

  StreamSubscription<ChatEvent>? _busSubscription;
  StreamSubscription<AssistantEvent>? _serviceSubscription;

  final Queue<UserMessageSubmitted> _queue = Queue<UserMessageSubmitted>();
  bool _draining = false;

  String? _activeThreadId;
  String? _activeMessageId;
  ChatChannel _activeChannel = ChatChannel.local;
  final StringBuffer _textBuffer = StringBuffer();
  final StringBuffer _thinkingBuffer = StringBuffer();

  String? _workerSessionId;

  void start() {
    if (_busSubscription != null) return;
    _busSubscription = _bus.events.listen(_onChatEvent);
    _serviceSubscription = _service.events.listen(_onWorkerEvent);
  }

  Future<void> dispose() async {
    await _busSubscription?.cancel();
    await _serviceSubscription?.cancel();
    _busSubscription = null;
    _serviceSubscription = null;
  }

  void abortInFlight() {
    _queue.clear();
    _workerSessionId = null;
  }

  void invalidateWorkerSession() {
    _workerSessionId = null;
  }

  void _onChatEvent(ChatEvent event) {
    if (event is! UserMessageSubmitted) return;
    _queue.add(event);
    debugPrint(
      '[llm-driver] enqueued thread=${event.threadId} channel=${event.channel.name} '
      'queue=${_queue.length} draining=$_draining',
    );
    if (!_draining) {
      _draining = true;
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        final turn = _queue.removeFirst();
        await _processTurn(turn);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _processTurn(UserMessageSubmitted turn) async {
    final messageId = _uuid.v4();
    final startedAt = DateTime.now();

    _activeThreadId = turn.threadId;
    _activeMessageId = messageId;
    _activeChannel = turn.channel;
    _textBuffer.clear();
    _thinkingBuffer.clear();

    _bus.publish(AssistantStarted(
      threadId: turn.threadId,
      messageId: messageId,
      channel: turn.channel,
    ));

    try {
      if (_workerSessionId != turn.threadId) {
        debugPrint(
          '[llm-driver] switchChat → ${turn.threadId} '
          '(history=${turn.replayHistory.length})',
        );
        await _service.switchChat(
          threadId: turn.threadId,
          systemInstruction: turn.systemInstruction ?? '',
          chatFamily: turn.chatFamily,
          history: [
            for (final h in turn.replayHistory)
              {'role': h.role, 'text': h.text},
          ],
          thinking: turn.thinkingEnabled,
        );
        _workerSessionId = turn.threadId;
      }

      final contextChunks = await _retriever(turn.message.text);
      debugPrint(
        '[llm-driver] generate channel=${turn.channel.name} '
        'thread=${turn.threadId} msg=$messageId ctx=${contextChunks.length}',
      );
      final finalText = await _service.generate(
        prompt: turn.message.text,
        contextChunks: contextChunks,
      );

      _bus.publish(AssistantCompleted(
        threadId: turn.threadId,
        channel: turn.channel,
        message: AssistantMessage(
          id: messageId,
          role: AssistantRole.assistant,
          text: finalText.isNotEmpty ? finalText : _textBuffer.toString(),
          thinking: _thinkingBuffer.toString(),
          createdAt: startedAt,
        ),
      ));
    } on Object catch (e) {
      debugPrint('[llm-driver] turn failed: $e');
      _workerSessionId = null;
      if (turn.channel == ChatChannel.cloud && _isNoModelError(e)) {
        debugPrint('[llm-driver] no model loaded → cloud fallback reply');
        _bus.publish(AssistantCompleted(
          threadId: turn.threadId,
          channel: turn.channel,
          message: AssistantMessage(
            id: messageId,
            role: AssistantRole.assistant,
            text: _kCloudFallbackReply,
            createdAt: DateTime.now(),
          ),
        ));
      } else {
        _bus.publish(AssistantFailed(
          threadId: turn.threadId,
          messageId: messageId,
          channel: turn.channel,
          error: e.toString(),
        ));
      }
    } finally {
      if (_activeMessageId == messageId) {
        _activeThreadId = null;
        _activeMessageId = null;
        _textBuffer.clear();
        _thinkingBuffer.clear();
      }
    }
  }

  void _onWorkerEvent(AssistantEvent event) {
    final threadId = _activeThreadId;
    final messageId = _activeMessageId;
    final channel = _activeChannel;
    if (threadId == null || messageId == null) return;
    switch (event) {
      case TokenEvent():
        _textBuffer.write(event.token);
        _bus.publish(AssistantToken(
          threadId: threadId,
          messageId: messageId,
          channel: channel,
          token: event.token,
        ));
      case ThinkingTokenEvent():
        _thinkingBuffer.write(event.token);
        _bus.publish(AssistantThinkingToken(
          threadId: threadId,
          messageId: messageId,
          channel: channel,
          token: event.token,
        ));
      case DoneEvent():
      case StatusEvent():
      case ProgressEvent():
      case LogEvent():
      case ModelsListEvent():
      case ModelLoadedEvent():
      case EmbedderLoadedEvent():
      case EmbeddingEvent():
      case IndexingProgressEvent():
      case IndexingDoneEvent():
        break;
    }
  }

  bool _isNoModelError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('no model loaded') ||
        msg.contains('model not loaded') ||
        msg.contains('not initialised');
  }
}
