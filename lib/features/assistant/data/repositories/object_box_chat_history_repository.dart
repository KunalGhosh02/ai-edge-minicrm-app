import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/core/storage/object_box_store.dart';
import 'package:minicrm/features/assistant/data/models/chat_thread_box.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/entities/chat_thread.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/assistant/domain/repositories/chat_history_repository.dart';
import 'package:minicrm/objectbox.g.dart';
import 'package:uuid/uuid.dart';

class ObjectBoxChatHistoryRepository implements ChatHistoryRepository {
  ObjectBoxChatHistoryRepository(Store store)
      : _threadBox = store.box<ChatThreadBox>(),
        _messageBox = store.box<ChatMessageBox>();

  final Box<ChatThreadBox> _threadBox;
  final Box<ChatMessageBox> _messageBox;
  static const _uuid = Uuid();

  @override
  Stream<List<ChatThread>> watchThreads() {
    final query = _threadBox
        .query()
        .order(ChatThreadBox_.updatedAtMs, flags: Order.descending)
        .watch(triggerImmediately: true);
    return query.map((q) => q.find().map(_toDomain).toList());
  }

  @override
  Future<List<ChatThread>> listThreads() async {
    final builder = _threadBox
        .query()
        .order(ChatThreadBox_.updatedAtMs, flags: Order.descending);
    final q = builder.build();
    try {
      return q.find().map(_toDomain).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<ChatThread?> getThread(String threadId) async {
    final q = _threadBox.query(ChatThreadBox_.threadId.equals(threadId)).build();
    try {
      final hit = q.findFirst();
      return hit == null ? null : _toDomain(hit);
    } finally {
      q.close();
    }
  }

  @override
  Future<ChatThread> createThread({
    required String title,
    required String systemInstruction,
    required ChatModelFamily chatFamily,
    String? modelId,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final entity = ChatThreadBox(
      threadId: id,
      title: title,
      systemInstruction: systemInstruction,
      chatFamily: chatFamily.id,
      modelId: modelId,
      createdAtMs: now.millisecondsSinceEpoch,
      updatedAtMs: now.millisecondsSinceEpoch,
    );
    _threadBox.put(entity);
    return _toDomain(entity);
  }

  @override
  Future<void> updateThread(ChatThread thread) async {
    final q = _threadBox.query(ChatThreadBox_.threadId.equals(thread.id)).build();
    try {
      final existing = q.findFirst();
      if (existing == null) return;
      existing
        ..title = thread.title
        ..systemInstruction = thread.systemInstruction
        ..chatFamily = thread.chatFamily.id
        ..modelId = thread.modelId
        ..updatedAtMs = thread.updatedAt.millisecondsSinceEpoch;
      _threadBox.put(existing);
    } finally {
      q.close();
    }
  }

  @override
  Future<void> deleteThread(String threadId) async {
    final tq = _threadBox.query(ChatThreadBox_.threadId.equals(threadId)).build();
    final mq = _messageBox.query(ChatMessageBox_.threadId.equals(threadId)).build();
    try {
      final thread = tq.findFirst();
      if (thread != null) {
        _threadBox.remove(thread.id);
      }
      final msgs = mq.find();
      if (msgs.isNotEmpty) {
        _messageBox.removeMany(msgs.map((m) => m.id).toList());
      }
    } finally {
      tq.close();
      mq.close();
    }
  }

  @override
  Future<List<AssistantMessage>> getMessages(String threadId) async {
    final q = _messageBox
        .query(ChatMessageBox_.threadId.equals(threadId))
        .order(ChatMessageBox_.createdAtMs)
        .build();
    try {
      return q.find().map(_messageToDomain).toList();
    } finally {
      q.close();
    }
  }

  @override
  Future<void> appendMessage({
    required String threadId,
    required AssistantMessage message,
  }) async {
    _messageBox.put(_messageToBox(threadId, message));
    _touchThread(threadId);
  }

  @override
  Future<void> upsertMessage({
    required String threadId,
    required AssistantMessage message,
  }) async {
    final q = _messageBox.query(ChatMessageBox_.messageId.equals(message.id)).build();
    try {
      final existing = q.findFirst();
      if (existing == null) {
        _messageBox.put(_messageToBox(threadId, message));
      } else {
        existing
          ..text = message.text
          ..thinking = message.thinking
          ..role = message.role == AssistantRole.user ? 0 : 1
          ..createdAtMs = message.createdAt.millisecondsSinceEpoch;
        _messageBox.put(existing);
      }
    } finally {
      q.close();
    }
    _touchThread(threadId);
  }

  void _touchThread(String threadId) {
    final q = _threadBox.query(ChatThreadBox_.threadId.equals(threadId)).build();
    try {
      final t = q.findFirst();
      if (t == null) return;
      t.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
      _threadBox.put(t);
    } finally {
      q.close();
    }
  }

  ChatThread _toDomain(ChatThreadBox e) => ChatThread(
        id: e.threadId,
        title: e.title,
        systemInstruction: e.systemInstruction,
        chatFamily: ChatModelFamilyX.parse(e.chatFamily),
        modelId: e.modelId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(e.createdAtMs),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(e.updatedAtMs),
      );

  AssistantMessage _messageToDomain(ChatMessageBox e) => AssistantMessage(
        id: e.messageId,
        role: e.role == 0 ? AssistantRole.user : AssistantRole.assistant,
        text: e.text,
        createdAt: DateTime.fromMillisecondsSinceEpoch(e.createdAtMs),
        thinking: e.thinking,
      );

  ChatMessageBox _messageToBox(String threadId, AssistantMessage m) =>
      ChatMessageBox(
        messageId: m.id,
        threadId: threadId,
        role: m.role == AssistantRole.user ? 0 : 1,
        text: m.text,
        thinking: m.thinking,
        createdAtMs: m.createdAt.millisecondsSinceEpoch,
      );
}

final chatHistoryRepositoryProvider =
    FutureProvider<ChatHistoryRepository>((ref) async {
  final store = await ref.watch(objectBoxStoreProvider.future);
  return ObjectBoxChatHistoryRepository(store.store);
});

final chatThreadsProvider =
    StreamProvider<List<ChatThread>>((ref) async* {
  final repo = await ref.watch(chatHistoryRepositoryProvider.future);
  yield* repo.watchThreads();
});
