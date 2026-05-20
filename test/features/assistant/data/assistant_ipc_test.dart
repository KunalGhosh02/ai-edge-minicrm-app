import 'package:flutter_test/flutter_test.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';

void main() {
  group('AssistantEvent.tryParse', () {
    test('parses status event', () {
      final event = AssistantEvent.tryParse({
        'kind': 'status',
        'state': 'ready',
      });
      expect(event, isA<StatusEvent>());
      expect((event! as StatusEvent).phase, AssistantPhase.ready);
    });

    test('parses progress event', () {
      final event = AssistantEvent.tryParse({
        'kind': 'progress',
        'percent': 42,
      });
      expect(event, isA<ProgressEvent>());
      expect((event! as ProgressEvent).percent, 42);
    });

    test('parses token event', () {
      final event = AssistantEvent.tryParse({
        'kind': 'token',
        'requestId': 'r1',
        'token': 'Hello',
      });
      expect(event, isA<TokenEvent>());
      final token = event! as TokenEvent;
      expect(token.requestId, 'r1');
      expect(token.token, 'Hello');
    });

    test('parses done event', () {
      final event = AssistantEvent.tryParse({
        'kind': 'done',
        'requestId': 'r1',
        'text': 'Hello world',
      });
      expect(event, isA<DoneEvent>());
      expect((event! as DoneEvent).text, 'Hello world');
    });

    test('returns null for unknown kind', () {
      expect(AssistantEvent.tryParse({'kind': 'mystery'}), isNull);
    });

    test('returns null for non-map input', () {
      expect(AssistantEvent.tryParse('not a map'), isNull);
    });

    test('parses embedder loaded event with metadata', () {
      final event = AssistantEvent.tryParse({
        'kind': 'embedder_loaded',
        'modelPath': '/m/x.tflite',
        'tokenizerPath': '/m/sp.model',
        'dim': 768,
      });
      expect(event, isA<EmbedderLoadedEvent>());
      final loaded = event! as EmbedderLoadedEvent;
      expect(loaded.isLoaded, isTrue);
      expect(loaded.modelPath, '/m/x.tflite');
      expect(loaded.dim, 768);
    });

    test('parses embedder loaded event indicating unload', () {
      final event = AssistantEvent.tryParse({'kind': 'embedder_loaded'});
      expect(event, isA<EmbedderLoadedEvent>());
      expect((event! as EmbedderLoadedEvent).isLoaded, isFalse);
    });

    test('parses embedding result event', () {
      final event = AssistantEvent.tryParse({
        'kind': 'embedding',
        'requestId': 'r1',
        'vector': [0.1, 0.2, 0.3],
      });
      expect(event, isA<EmbeddingEvent>());
      final emb = event! as EmbeddingEvent;
      expect(emb.requestId, 'r1');
      expect(emb.vector, [0.1, 0.2, 0.3]);
      expect(emb.error, isNull);
    });

    test('parses embedding error event', () {
      final event = AssistantEvent.tryParse({
        'kind': 'embedding',
        'requestId': 'r2',
        'vector': <double>[],
        'error': 'No embedder loaded',
      });
      expect(event, isA<EmbeddingEvent>());
      expect((event! as EmbeddingEvent).error, 'No embedder loaded');
    });
  });

  group('AssistantCommand.toMap', () {
    test('install command serialises token only when set', () {
      final without = const InstallModelCommand(
        url: 'https://x',
        backend: 'cpu',
      ).toMap();
      expect(without.containsKey('token'), isFalse);
      expect(without['backend'], 'cpu');

      final with_ = const InstallModelCommand(
        url: 'https://x',
        backend: 'gpu',
        token: 't',
      ).toMap();
      expect(with_['token'], 't');
      expect(with_['backend'], 'gpu');
    });

    test('generate command round-trips through tryParse', () {
      const cmd = GenerateCommand(requestId: 'r', prompt: 'hi');
      final map = cmd.toMap();
      expect(map['kind'], 'generate');
      expect(map['requestId'], 'r');
      expect(map['prompt'], 'hi');
    });

    test('install embedder command carries tokenizer URL', () {
      final map = const InstallEmbedderCommand(
        modelUrl: 'https://m/model.tflite',
        tokenizerUrl: 'https://m/sp.model',
        token: 'hf_abc',
      ).toMap();
      expect(map['kind'], 'install_embedder');
      expect(map['modelUrl'], 'https://m/model.tflite');
      expect(map['tokenizerUrl'], 'https://m/sp.model');
      expect(map['token'], 'hf_abc');
      expect(map['loadAfterDownload'], isTrue);
    });

    test('install embedder command omits empty token', () {
      final map = const InstallEmbedderCommand(
        modelUrl: 'https://m/model.tflite',
        tokenizerUrl: 'https://m/sp.model',
        token: '',
      ).toMap();
      expect(map.containsKey('token'), isFalse);
    });

    test('embed command serialises isQuery flag', () {
      final docMap = const EmbedCommand(
        requestId: 'r',
        text: 'doc',
      ).toMap();
      expect(docMap['isQuery'], isFalse);

      final queryMap = const EmbedCommand(
        requestId: 'r',
        text: 'q',
        isQuery: true,
      ).toMap();
      expect(queryMap['isQuery'], isTrue);
      expect(queryMap['text'], 'q');
    });

    test('load embedder command carries both paths', () {
      final map = const LoadEmbedderCommand(
        modelPath: '/m/x.tflite',
        tokenizerPath: '/m/sp.model',
      ).toMap();
      expect(map['kind'], 'load_embedder');
      expect(map['modelPath'], '/m/x.tflite');
      expect(map['tokenizerPath'], '/m/sp.model');
    });
  });
}
