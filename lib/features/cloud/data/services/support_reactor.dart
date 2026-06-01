import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_message.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_session.dart';
import 'package:minicrm/features/cloud/domain/repositories/customer_session_repository.dart';

typedef SystemPromptProvider = Future<String> Function();
typedef ThinkingEnabledProvider = Future<bool> Function();

class SupportReactor {
  SupportReactor(
    this._repo,
    this._bus,
    this._systemPromptProvider,
    this._thinkingEnabledProvider,
  );

  final CustomerSessionRepository _repo;
  final ChatEventBus _bus;
  final SystemPromptProvider _systemPromptProvider;
  final ThinkingEnabledProvider _thinkingEnabledProvider;

  StreamSubscription<List<CustomerSession>>? _sessionsSubscription;
  final Map<String, StreamSubscription<List<CustomerMessage>>>
      _messageSubscriptions = {};
  final Map<String, String> _lastSeenMessageId = {};
  final Map<String, bool> _takenOver = {};

  String? _userId;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start(String userId) async {
    if (_running) return;
    _running = true;
    _userId = userId;
    debugPrint('[support] reactor starting for $userId');
    _sessionsSubscription =
        _repo.watchSessions(userId).listen(_onSessionsSnapshot);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    debugPrint('[support] reactor stopping');
    await _sessionsSubscription?.cancel();
    _sessionsSubscription = null;
    for (final sub in _messageSubscriptions.values) {
      await sub.cancel();
    }
    _messageSubscriptions.clear();
    _lastSeenMessageId.clear();
    _takenOver.clear();
    _userId = null;
  }

  void _onSessionsSnapshot(List<CustomerSession> sessions) {
    final userId = _userId;
    if (userId == null) return;
    debugPrint('[support] sessions snapshot: ${sessions.length} session(s)');
    final seen = <String>{};
    for (final session in sessions) {
      seen.add(session.customerId);
      _takenOver[session.customerId] = session.takenOver;
      _ensureMessageSubscription(userId, session.customerId);
    }
    final stale = _messageSubscriptions.keys
        .where((id) => !seen.contains(id))
        .toList(growable: false);
    for (final id in stale) {
      unawaited(_messageSubscriptions.remove(id)?.cancel());
      _lastSeenMessageId.remove(id);
      _takenOver.remove(id);
    }
  }

  void _ensureMessageSubscription(String userId, String customerId) {
    if (_messageSubscriptions.containsKey(customerId)) return;
    _messageSubscriptions[customerId] = _repo
        .watchMessages(userId: userId, customerId: customerId)
        .listen((messages) => _onMessagesSnapshot(customerId, messages));
  }

  void _onMessagesSnapshot(
    String customerId,
    List<CustomerMessage> messages,
  ) {
    unawaited(_onMessagesSnapshotAsync(customerId, messages));
  }

  Future<void> _onMessagesSnapshotAsync(
    String customerId,
    List<CustomerMessage> messages,
  ) async {
    if (messages.isEmpty) return;
    final last = messages.last;
    debugPrint(
      '[support] messages snapshot for $customerId: '
      '${messages.length} doc(s), last sender=${last.sender.name} '
      'id=${last.id}',
    );
    if (last.sender != CustomerSender.customer) return;
    if (_lastSeenMessageId[customerId] == last.id) return;
    _lastSeenMessageId[customerId] = last.id;

    if (_takenOver[customerId] == true) {
      debugPrint(
        '[support] session $customerId is in takeover mode; skipping bot reply',
      );
      return;
    }

    final history = <ChatTurnHistory>[
      for (final m in messages.take(messages.length - 1))
        ChatTurnHistory(
          role: m.sender == CustomerSender.customer ? 'user' : 'assistant',
          text: m.text,
        ),
    ];

    String? systemInstruction;
    try {
      final prompt = (await _systemPromptProvider()).trim();
      if (prompt.isNotEmpty) systemInstruction = prompt;
    } on Object catch (e) {
      debugPrint('[support] systemPromptProvider failed: $e');
    }

    var thinkingEnabled = true;
    try {
      thinkingEnabled = await _thinkingEnabledProvider();
    } on Object catch (e) {
      debugPrint('[support] thinkingEnabledProvider failed: $e');
    }

    debugPrint(
      '[support] publishing UserMessageSubmitted(channel=cloud, '
      'thread=$customerId, msg=${last.id}, history=${history.length})',
    );
    _bus.publish(UserMessageSubmitted(
      threadId: customerId,
      channel: ChatChannel.cloud,
      replayHistory: history,
      systemInstruction: systemInstruction,
      thinkingEnabled: thinkingEnabled,
      message: AssistantMessage(
        id: last.id,
        role: AssistantRole.user,
        text: last.text,
        createdAt: last.createdAt,
      ),
    ));
  }
}
