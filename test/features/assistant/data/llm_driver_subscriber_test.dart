import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/data/subscribers/llm_driver_subscriber.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';

class _FakeAssistantService implements AssistantService {
  final StreamController<AssistantEvent> _events =
      StreamController<AssistantEvent>.broadcast();

  final List<({String threadId, int historyLen})> switchCalls = [];
  final List<String> generateCalls = [];

  Completer<String>? _pending;
  bool _failGenerateAsNoModel = false;

  void failNextGenerateAsNoModel() {
    _failGenerateAsNoModel = true;
  }

  @override
  Stream<AssistantEvent> get events => _events.stream;

  void resolveGenerate(String text) {
    final p = _pending;
    _pending = null;
    p?.complete(text);
  }

  @override
  Future<void> switchChat({
    required String threadId,
    required String systemInstruction,
    required String chatFamily,
    required List<Map<String, String>> history,
    bool thinking = true,
  }) async {
    switchCalls.add((threadId: threadId, historyLen: history.length));
  }

  @override
  Future<String> generate({
    required String prompt,
    List<String> contextChunks = const [],
  }) {
    generateCalls.add(prompt);
    if (_failGenerateAsNoModel) {
      _failGenerateAsNoModel = false;
      return Future<String>.error(StateError('No model loaded'));
    }
    _pending = Completer<String>();
    return _pending!.future;
  }

  @override
  bool get isRunning => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> stopGeneration() async {}

  @override
  Future<void> setSystemPrompt(String prompt) async {}

  @override
  Future<void> installModel({
    required String url,
    required String backend,
    String? token,
    bool loadAfterDownload = true,
    String chatFamily = 'general',
    int maxTokens = 4096,
  }) async {}

  @override
  Future<void> listInstalledModels() async {}

  @override
  Future<void> loadInstalledModel({
    required String path,
    required String backend,
    String chatFamily = 'general',
    int maxTokens = 4096,
  }) async {}

  @override
  Future<void> unloadModel() async {}

  @override
  Future<void> deleteInstalledModel({required String path}) async {}

  @override
  Future<void> installEmbedder({
    required String modelUrl,
    required String tokenizerUrl,
    String? token,
    bool loadAfterDownload = true,
    String runtime = 'tflite',
    String backend = 'cpu',
    int? sequenceLength,
    String? presetId,
  }) async {}

  @override
  Future<void> loadEmbedder({
    required String modelPath,
    required String tokenizerPath,
    String backend = 'cpu',
    String runtime = 'tflite',
    int? sequenceLength,
    String? presetId,
  }) async {}

  @override
  Future<void> unloadEmbedder() async {}

  @override
  Future<List<double>> embed({
    required String text,
    bool isQuery = false,
  }) async =>
      const [];

  @override
  Future<void> enqueueEmbeddings() async {}
}

UserMessageSubmitted _userTurn({
  required String threadId,
  required String text,
  ChatChannel channel = ChatChannel.local,
  List<ChatTurnHistory> history = const [],
}) {
  return UserMessageSubmitted(
    threadId: threadId,
    channel: channel,
    replayHistory: history,
    message: AssistantMessage(
      id: 'u-$threadId-$text',
      role: AssistantRole.user,
      text: text,
      createdAt: DateTime.now(),
    ),
  );
}

void main() {
  group('LlmDriverSubscriber', () {
    late ChatEventBus bus;
    late _FakeAssistantService service;
    late LlmDriverSubscriber driver;
    late List<ChatEvent> seen;

    setUp(() {
      bus = ChatEventBus();
      service = _FakeAssistantService();
      driver = LlmDriverSubscriber(bus, service, (_) async => const [])
        ..start();
      seen = [];
      bus.events.listen(seen.add);
    });

    tearDown(() async {
      await driver.dispose();
      await bus.dispose();
    });

    test(
      'serialises turns: second turn does not start until first completes',
      () async {
        bus
          ..publish(_userTurn(threadId: 'A', text: 'hi A'))
          ..publish(_userTurn(threadId: 'B', text: 'hi B'));

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(service.generateCalls, ['hi A']);

        service.resolveGenerate('A reply');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(service.generateCalls, ['hi A', 'hi B']);

        service.resolveGenerate('B reply');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final completedThreads = seen
            .whereType<AssistantCompleted>()
            .map((e) => '${e.threadId}:${e.channel.name}:${e.message.text}')
            .toList();
        expect(completedThreads, [
          'A:local:A reply',
          'B:local:B reply',
        ]);
      },
    );

    test('switchChat fires only when the worker session changes', () async {
      bus.publish(_userTurn(threadId: 'A', text: 'q1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('a1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      bus.publish(_userTurn(threadId: 'A', text: 'q2'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('a2');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      bus.publish(_userTurn(threadId: 'B', text: 'q3'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('b1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        service.switchCalls.map((e) => e.threadId).toList(),
        ['A', 'B'],
      );
    });

    test('different channels with same thread id share the worker session',
        () async {
      bus.publish(_userTurn(threadId: 'X', text: 'local q'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('local r');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      bus.publish(_userTurn(
        threadId: 'X',
        text: 'cloud q',
        channel: ChatChannel.cloud,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('cloud r');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        service.switchCalls.map((e) => e.threadId).toList(),
        ['X'],
      );

      final completedChannels = seen
          .whereType<AssistantCompleted>()
          .map((e) => e.channel)
          .toList();
      expect(completedChannels, [ChatChannel.local, ChatChannel.cloud]);
    });

    test(
      'cloud turn falls back to canned reply when no model is loaded',
      () async {
        service.failNextGenerateAsNoModel();
        bus.publish(_userTurn(
          threadId: 'cloud-A',
          text: 'help',
          channel: ChatChannel.cloud,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final completed = seen.whereType<AssistantCompleted>().toList();
        final failed = seen.whereType<AssistantFailed>().toList();
        expect(failed, isEmpty);
        expect(completed, hasLength(1));
        expect(completed.first.channel, ChatChannel.cloud);
        expect(completed.first.message.text, contains('get back to you'));
      },
    );

    test(
      'local turn surfaces the failure when no model is loaded',
      () async {
        service.failNextGenerateAsNoModel();
        bus.publish(_userTurn(threadId: 'local-A', text: 'hello'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final completed = seen.whereType<AssistantCompleted>().toList();
        final failed = seen.whereType<AssistantFailed>().toList();
        expect(completed, isEmpty);
        expect(failed, hasLength(1));
        expect(failed.first.error.toLowerCase(), contains('no model loaded'));
      },
    );

    test('invalidateWorkerSession forces a switchChat on the next turn',
        () async {
      bus.publish(_userTurn(threadId: 'A', text: 'q1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('a1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      driver.invalidateWorkerSession();

      bus.publish(_userTurn(threadId: 'A', text: 'q2'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resolveGenerate('a2');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        service.switchCalls.map((e) => e.threadId).toList(),
        ['A', 'A'],
      );
    });
  });
}
