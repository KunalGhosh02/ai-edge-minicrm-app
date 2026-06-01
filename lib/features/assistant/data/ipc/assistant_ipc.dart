abstract final class AssistantIpcKind {
  static const String init = 'init';
  static const String install = 'install';
  static const String generate = 'generate';
  static const String stop = 'stop';
  static const String listModels = 'list_models';
  static const String loadModel = 'load_model';
  static const String unloadModel = 'unload_model';
  static const String deleteModel = 'delete_model';
  static const String setSystemPrompt = 'set_system_prompt';
  static const String switchChat = 'switch_chat';
  static const String installEmbedder = 'install_embedder';
  static const String loadEmbedder = 'load_embedder';
  static const String unloadEmbedder = 'unload_embedder';
  static const String embed = 'embed';
  static const String enqueueEmbeddings = 'enqueue_embeddings';
  static const String status = 'status';
  static const String progress = 'progress';
  static const String token = 'token';
  static const String thinking = 'thinking';
  static const String done = 'done';
  static const String log = 'log';
  static const String models = 'models';
  static const String loaded = 'loaded';
  static const String embedderLoaded = 'embedder_loaded';
  static const String embedding = 'embedding';
  static const String indexingProgress = 'indexing_progress';
  static const String indexingDone = 'indexing_done';
}

abstract final class AssistantPhase {
  static const String idle = 'idle';
  static const String downloading = 'downloading';
  static const String loading = 'loading';
  static const String ready = 'ready';
  static const String generating = 'generating';
  static const String error = 'error';
}

sealed class AssistantCommand {
  const AssistantCommand();

  Map<String, dynamic> toMap();
}

final class InitCommand extends AssistantCommand {
  const InitCommand({required this.modelsDir, required this.cacheDir});

  final String modelsDir;
  final String cacheDir;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.init,
        'modelsDir': modelsDir,
        'cacheDir': cacheDir,
      };
}

final class InstallModelCommand extends AssistantCommand {
  const InstallModelCommand({
    required this.url,
    required this.backend,
    this.token,
    this.loadAfterDownload = true,
    this.chatFamily = 'general',
    this.maxTokens = 4096,
  });

  final String url;
  final String backend;
  final String? token;
  final bool loadAfterDownload;
  final String chatFamily;
  final int maxTokens;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.install,
        'url': url,
        'backend': backend,
        'loadAfterDownload': loadAfterDownload,
        'chatFamily': chatFamily,
        'maxTokens': maxTokens,
        if (token != null && token!.isNotEmpty) 'token': token,
      };
}

final class GenerateCommand extends AssistantCommand {
  const GenerateCommand({
    required this.requestId,
    required this.prompt,
    this.contextChunks = const [],
  });

  final String requestId;
  final String prompt;
  final List<String> contextChunks;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.generate,
        'requestId': requestId,
        'prompt': prompt,
        if (contextChunks.isNotEmpty) 'context': contextChunks,
      };
}

final class SetSystemPromptCommand extends AssistantCommand {
  const SetSystemPromptCommand({required this.prompt});

  final String prompt;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.setSystemPrompt,
        'prompt': prompt,
      };
}

final class StopGenerationCommand extends AssistantCommand {
  const StopGenerationCommand();

  @override
  Map<String, dynamic> toMap() => const {'kind': AssistantIpcKind.stop};
}

/// Switch the worker's active conversation. The worker tears down the
/// current `InferenceModelSession`, recreates one with [systemInstruction]
/// + [chatFamily], and replays [history] through `chat.addQueryChunk(...)`
/// so the KV cache is warm for the next [GenerateCommand].
///
/// History entries are `{role: 'user' | 'assistant', text: String}`.
final class SwitchChatCommand extends AssistantCommand {
  const SwitchChatCommand({
    required this.threadId,
    required this.systemInstruction,
    required this.chatFamily,
    required this.history,
    this.thinking = true,
  });

  final String threadId;
  final String systemInstruction;
  final String chatFamily;
  final List<Map<String, String>> history;
  final bool thinking;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.switchChat,
        'threadId': threadId,
        'systemInstruction': systemInstruction,
        'chatFamily': chatFamily,
        'history': history,
        'thinking': thinking,
      };
}

final class ListModelsCommand extends AssistantCommand {
  const ListModelsCommand();

  @override
  Map<String, dynamic> toMap() => const {'kind': AssistantIpcKind.listModels};
}

final class LoadModelCommand extends AssistantCommand {
  const LoadModelCommand({
    required this.path,
    required this.backend,
    this.chatFamily = 'general',
    this.maxTokens = 4096,
  });

  final String path;
  final String backend;
  final String chatFamily;
  final int maxTokens;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.loadModel,
        'path': path,
        'backend': backend,
        'chatFamily': chatFamily,
        'maxTokens': maxTokens,
      };
}

final class UnloadModelCommand extends AssistantCommand {
  const UnloadModelCommand();

  @override
  Map<String, dynamic> toMap() => const {'kind': AssistantIpcKind.unloadModel};
}

final class DeleteModelCommand extends AssistantCommand {
  const DeleteModelCommand({required this.path});

  final String path;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.deleteModel,
        'path': path,
      };
}

final class InstallEmbedderCommand extends AssistantCommand {
  const InstallEmbedderCommand({
    required this.modelUrl,
    required this.tokenizerUrl,
    this.token,
    this.loadAfterDownload = true,
    this.runtime = 'tflite',
    this.backend = 'cpu',
    this.sequenceLength,
    this.presetId,
  });

  final String modelUrl;
  final String tokenizerUrl;
  final String? token;
  final bool loadAfterDownload;
  final String runtime;
  final String backend;
  final int? sequenceLength;
  final String? presetId;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.installEmbedder,
        'modelUrl': modelUrl,
        'tokenizerUrl': tokenizerUrl,
        'loadAfterDownload': loadAfterDownload,
        'runtime': runtime,
        'backend': backend,
        if (sequenceLength != null) 'sequenceLength': sequenceLength,
        if (presetId != null) 'presetId': presetId,
        if (token != null && token!.isNotEmpty) 'token': token,
      };
}

final class LoadEmbedderCommand extends AssistantCommand {
  const LoadEmbedderCommand({
    required this.modelPath,
    required this.tokenizerPath,
    this.backend = 'cpu',
    this.runtime = 'tflite',
    this.sequenceLength,
    this.presetId,
  });

  final String modelPath;
  final String tokenizerPath;
  final String backend;
  final String runtime;
  final int? sequenceLength;
  final String? presetId;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.loadEmbedder,
        'modelPath': modelPath,
        'tokenizerPath': tokenizerPath,
        'backend': backend,
        'runtime': runtime,
        if (sequenceLength != null) 'sequenceLength': sequenceLength,
        if (presetId != null) 'presetId': presetId,
      };
}

final class UnloadEmbedderCommand extends AssistantCommand {
  const UnloadEmbedderCommand();

  @override
  Map<String, dynamic> toMap() =>
      const {'kind': AssistantIpcKind.unloadEmbedder};
}

/// Request the worker to compute an embedding for [text].
/// [isQuery] selects the prompt prefix the model was trained with
/// ("task: search result | query: " vs "title: none | text: ").
/// The response arrives as an [EmbeddingEvent] with the same [requestId].
final class EmbedCommand extends AssistantCommand {
  const EmbedCommand({
    required this.requestId,
    required this.text,
    this.isQuery = false,
  });

  final String requestId;
  final String text;
  final bool isQuery;

  @override
  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.embed,
        'requestId': requestId,
        'text': text,
        'isQuery': isQuery,
      };
}

/// Wake the worker up so it pulls any unembedded chunks from the
/// ObjectBox queue and embeds them in a background loop. Idempotent —
/// if the worker is already draining the queue this is a no-op.
final class EnqueueEmbeddingsCommand extends AssistantCommand {
  const EnqueueEmbeddingsCommand();

  @override
  Map<String, dynamic> toMap() =>
      const {'kind': AssistantIpcKind.enqueueEmbeddings};
}

sealed class AssistantEvent {
  const AssistantEvent();

  static AssistantEvent? tryParse(Object data) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    return switch (map['kind']) {
      AssistantIpcKind.status => StatusEvent(
          phase: map['state'] as String,
          detail: map['detail'] as String?,
        ),
      AssistantIpcKind.progress => ProgressEvent(
          percent: (map['percent'] as num).toInt(),
          receivedBytes: (map['received'] as num?)?.toInt(),
          totalBytes: (map['total'] as num?)?.toInt(),
        ),
      AssistantIpcKind.token => TokenEvent(
          requestId: map['requestId'] as String,
          token: map['token'] as String,
        ),
      AssistantIpcKind.thinking => ThinkingTokenEvent(
          requestId: map['requestId'] as String,
          token: map['token'] as String,
        ),
      AssistantIpcKind.done => DoneEvent(
          requestId: map['requestId'] as String,
          text: (map['text'] as String?) ?? '',
        ),
      AssistantIpcKind.log => LogEvent(message: map['message'] as String),
      AssistantIpcKind.models => ModelsListEvent(
          models: (map['models'] as List<dynamic>?)
                  ?.map(
                    (e) => Map<String, dynamic>.from(e as Map),
                  )
                  .toList() ??
              const [],
        ),
      AssistantIpcKind.loaded => ModelLoadedEvent(
          path: map['path'] as String?,
          name: map['name'] as String?,
          sizeBytes: (map['size'] as num?)?.toInt(),
          backend: map['backend'] as String?,
        ),
      AssistantIpcKind.embedderLoaded => EmbedderLoadedEvent(
          modelPath: map['modelPath'] as String?,
          tokenizerPath: map['tokenizerPath'] as String?,
          dim: (map['dim'] as num?)?.toInt(),
          backend: map['backend'] as String?,
          runtime: map['runtime'] as String?,
        ),
      AssistantIpcKind.embedding => EmbeddingEvent(
          requestId: map['requestId'] as String,
          vector: (map['vector'] as List<dynamic>?)
                  ?.map((e) => (e as num).toDouble())
                  .toList() ??
              const [],
          error: map['error'] as String?,
        ),
      AssistantIpcKind.indexingProgress => IndexingProgressEvent(
          processed: (map['processed'] as num).toInt(),
          total: (map['total'] as num).toInt(),
          avgMs: (map['avgMs'] as num?)?.toDouble() ?? 0.0,
          etaMs: (map['etaMs'] as num?)?.toInt() ?? 0,
        ),
      AssistantIpcKind.indexingDone => IndexingDoneEvent(
          embedded: (map['embedded'] as num?)?.toInt() ?? 0,
          failed: (map['failed'] as num?)?.toInt() ?? 0,
        ),
      _ => null,
    };
  }
}

final class StatusEvent extends AssistantEvent {
  const StatusEvent({required this.phase, this.detail});

  final String phase;
  final String? detail;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.status,
        'state': phase,
        if (detail != null) 'detail': detail,
      };
}

final class ProgressEvent extends AssistantEvent {
  const ProgressEvent({
    required this.percent,
    this.receivedBytes,
    this.totalBytes,
  });

  final int percent;
  final int? receivedBytes;
  final int? totalBytes;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.progress,
        'percent': percent,
        if (receivedBytes != null) 'received': receivedBytes,
        if (totalBytes != null) 'total': totalBytes,
      };
}

final class TokenEvent extends AssistantEvent {
  const TokenEvent({required this.requestId, required this.token});

  final String requestId;
  final String token;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.token,
        'requestId': requestId,
        'token': token,
      };
}

/// Streamed reasoning content (`<think>…</think>`, Gemma 4 thought channel,
/// etc.) emitted by the worker for the message at [requestId]. The text
/// belongs in a separate "Thoughts" section, not in the answer.
final class ThinkingTokenEvent extends AssistantEvent {
  const ThinkingTokenEvent({required this.requestId, required this.token});

  final String requestId;
  final String token;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.thinking,
        'requestId': requestId,
        'token': token,
      };
}

final class DoneEvent extends AssistantEvent {
  const DoneEvent({required this.requestId, required this.text});

  final String requestId;
  final String text;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.done,
        'requestId': requestId,
        'text': text,
      };
}

final class LogEvent extends AssistantEvent {
  const LogEvent({required this.message});

  final String message;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.log,
        'message': message,
      };
}

final class ModelsListEvent extends AssistantEvent {
  const ModelsListEvent({required this.models});

  final List<Map<String, dynamic>> models;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.models,
        'models': models,
      };
}

final class ModelLoadedEvent extends AssistantEvent {
  const ModelLoadedEvent({
    this.path,
    this.name,
    this.sizeBytes,
    this.backend,
  });

  final String? path;
  final String? name;
  final int? sizeBytes;
  final String? backend;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.loaded,
        if (path != null) 'path': path,
        if (name != null) 'name': name,
        if (sizeBytes != null) 'size': sizeBytes,
        if (backend != null) 'backend': backend,
      };
}

final class EmbedderLoadedEvent extends AssistantEvent {
  const EmbedderLoadedEvent({
    this.modelPath,
    this.tokenizerPath,
    this.dim,
    this.backend,
    this.runtime,
  });

  final String? modelPath;
  final String? tokenizerPath;
  final int? dim;
  final String? backend;
  final String? runtime;

  bool get isLoaded => modelPath != null;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.embedderLoaded,
        if (modelPath != null) 'modelPath': modelPath,
        if (tokenizerPath != null) 'tokenizerPath': tokenizerPath,
        if (dim != null) 'dim': dim,
        if (backend != null) 'backend': backend,
        if (runtime != null) 'runtime': runtime,
      };
}

final class EmbeddingEvent extends AssistantEvent {
  const EmbeddingEvent({
    required this.requestId,
    required this.vector,
    this.error,
  });

  final String requestId;
  final List<double> vector;
  final String? error;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.embedding,
        'requestId': requestId,
        'vector': vector,
        if (error != null) 'error': error,
      };
}

/// Periodic progress update emitted by the worker while it's draining the
/// unembedded-chunk queue.
final class IndexingProgressEvent extends AssistantEvent {
  const IndexingProgressEvent({
    required this.processed,
    required this.total,
    this.avgMs = 0.0,
    this.etaMs = 0,
  });

  final int processed;
  final int total;
  final double avgMs;
  final int etaMs;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.indexingProgress,
        'processed': processed,
        'total': total,
        'avgMs': avgMs,
        'etaMs': etaMs,
      };
}

/// Worker finished draining the queue (or aborted due to repeated failures).
final class IndexingDoneEvent extends AssistantEvent {
  const IndexingDoneEvent({required this.embedded, required this.failed});

  final int embedded;
  final int failed;

  Map<String, dynamic> toMap() => {
        'kind': AssistantIpcKind.indexingDone,
        'embedded': embedded,
        'failed': failed,
      };
}
