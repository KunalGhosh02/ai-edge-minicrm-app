import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';

abstract interface class AssistantService {
  Stream<AssistantEvent> get events;

  bool get isRunning;

  Future<bool> requestPermissions();

  Future<void> start();

  Future<void> stop();

  Future<void> installModel({
    required String url,
    required String backend,
    String? token,
    bool loadAfterDownload,
    String chatFamily,
    int maxTokens,
  });

  Future<void> listInstalledModels();

  Future<void> loadInstalledModel({
    required String path,
    required String backend,
    String chatFamily,
    int maxTokens,
  });

  Future<void> unloadModel();

  Future<void> deleteInstalledModel({required String path});

  Future<String> generate({
    required String prompt,
    List<String> contextChunks,
  });

  Future<void> stopGeneration();

  Future<void> setSystemPrompt(String prompt);

  /// Tear down the current chat session, recreate it with [systemInstruction]
  /// + [chatFamily], and replay [history] (each item is
  /// `{role: 'user' | 'assistant', text: String}`) so the model's KV cache is
  /// warm. Call this when the user opens or switches between persisted chat
  /// threads.
  Future<void> switchChat({
    required String threadId,
    required String systemInstruction,
    required String chatFamily,
    required List<Map<String, String>> history,
  });

  /// Download (and optionally load) the embedding model + tokenizer pair.
  /// [runtime] selects the inference backend: `tflite` (legacy
  /// tflite_flutter path) or `flutter_gemma` (LiteRT FFI via the
  /// flutter_gemma plugin, recommended).
  Future<void> installEmbedder({
    required String modelUrl,
    required String tokenizerUrl,
    String? token,
    bool loadAfterDownload,
    String runtime,
    String backend,
    int? sequenceLength,
    String? presetId,
  });

  /// Load a previously-downloaded embedding model + tokenizer pair.
  /// [backend] selects the accelerator (`cpu` or `gpu`).
  /// [runtime] picks between `tflite` and `flutter_gemma`.
  Future<void> loadEmbedder({
    required String modelPath,
    required String tokenizerPath,
    String backend,
    String runtime,
    int? sequenceLength,
    String? presetId,
  });

  Future<void> unloadEmbedder();

  /// Compute a normalised embedding for [text]. Set [isQuery] to true
  /// for retrieval queries (uses the model's query prompt prefix);
  /// false for documents being indexed.
  Future<List<double>> embed({required String text, bool isQuery});

  /// Wake the worker so it pulls any unembedded chunks from the
  /// ObjectBox queue and embeds them in a background loop. The worker
  /// emits [IndexingProgressEvent] and [IndexingDoneEvent].
  Future<void> enqueueEmbeddings();
}
