import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/data/repositories/object_box_chat_history_repository.dart';
import 'package:minicrm/features/assistant/data/subscribers/chat_persistence_subscriber.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/entities/chat_thread.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:minicrm/features/assistant/domain/repositories/chat_history_repository.dart';

class _FakeChatHistoryRepository implements ChatHistoryRepository {
  final List<({String threadId, AssistantMessage message})> appended = [];
  final List<({String threadId, AssistantMessage message})> upserted = [];

  @override
  Future<void> appendMessage({
    required String threadId,
    required AssistantMessage message,
  }) async {
    appended.add((threadId: threadId, message: message));
  }

  @override
  Future<void> upsertMessage({
    required String threadId,
    required AssistantMessage message,
  }) async {
    upserted.add((threadId: threadId, message: message));
  }

  @override
  Future<ChatThread> createThread({
    required String title,
    required String systemInstruction,
    required ChatModelFamily chatFamily,
    String? modelId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteThread(String threadId) => throw UnimplementedError();

  @override
  Future<List<AssistantMessage>> getMessages(String threadId) =>
      throw UnimplementedError();

  @override
  Future<ChatThread?> getThread(String threadId) =>
      throw UnimplementedError();

  @override
  Future<List<ChatThread>> listThreads() => throw UnimplementedError();

  @override
  Future<void> updateThread(ChatThread thread) => throw UnimplementedError();

  @override
  Stream<List<AssistantMessage>> watchMessages(String threadId) =>
      const Stream.empty();

  @override
  Stream<List<ChatThread>> watchThreads() => const Stream.empty();
}

void main() {
  group('ChatEventBus', () {
    test('publish delivers events to listeners', () async {
      final bus = ChatEventBus();
      addTearDown(bus.dispose);
      final received = <ChatEvent>[];
      final sub = bus.events.listen(received.add);
      addTearDown(sub.cancel);

      final event = UserMessageSubmitted(
        threadId: 't1',
        message: AssistantMessage(
          id: 'm1',
          role: AssistantRole.user,
          text: 'hi',
          createdAt: DateTime(2026),
        ),
      );
      bus.publish(event);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, same(event));
    });

    test('late subscribers do not receive past events', () async {
      final bus = ChatEventBus();
      addTearDown(bus.dispose);

      bus.publish(const AssistantStarted(threadId: 't1', messageId: 'm1'));

      final received = <ChatEvent>[];
      final sub = bus.events.listen(received.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });
  });

  group('ChatPersistenceSubscriber', () {
    late ProviderContainer container;
    late _FakeChatHistoryRepository repo;

    setUp(() {
      repo = _FakeChatHistoryRepository();
      container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
    });

    tearDown(() => container.dispose());

    ChatEventBus busWithSubscriber() {
      container.read(chatPersistenceSubscriberProvider);
      return container.read(chatEventBusProvider);
    }

    test('persists user messages on UserMessageSubmitted', () async {
      final msg = AssistantMessage(
        id: 'u1',
        role: AssistantRole.user,
        text: 'hello',
        createdAt: DateTime(2026, 5, 20),
      );
      busWithSubscriber()
          .publish(UserMessageSubmitted(threadId: 't1', message: msg));

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repo.appended, hasLength(1));
      expect(repo.appended.single.threadId, 't1');
      expect(repo.appended.single.message, msg);
      expect(repo.upserted, isEmpty);
    });

    test('persists final assistant message on AssistantCompleted', () async {
      final final0 = AssistantMessage(
        id: 'a1',
        role: AssistantRole.assistant,
        text: 'final answer',
        thinking: 'because…',
        createdAt: DateTime(2026, 5, 20),
      );
      busWithSubscriber()
          .publish(AssistantCompleted(threadId: 't1', message: final0));

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repo.upserted, hasLength(1));
      expect(repo.upserted.single.message, final0);
      expect(repo.appended, isEmpty);
    });

    test('ignores token-level events', () async {
      busWithSubscriber()
        ..publish(const AssistantStarted(threadId: 't1', messageId: 'a1'))
        ..publish(
          const AssistantToken(threadId: 't1', messageId: 'a1', token: 'hi'),
        )
        ..publish(
          const AssistantThinkingToken(
            threadId: 't1',
            messageId: 'a1',
            token: 'reasoning',
          ),
        )
        ..publish(
          const AssistantFailed(
            threadId: 't1',
            error: 'oom',
            messageId: 'a1',
          ),
        );

      await Future<void>.delayed(Duration.zero);
      expect(repo.appended, isEmpty);
      expect(repo.upserted, isEmpty);
    });
  });
}
