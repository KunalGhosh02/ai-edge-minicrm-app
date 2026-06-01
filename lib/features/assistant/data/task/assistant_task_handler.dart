import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:minicrm/core/storage/object_box_store.dart';
import 'package:minicrm/features/assistant/data/embedder/embedder.dart';
import 'package:minicrm/features/assistant/data/embedder/embedding_gemma_embedder.dart';
import 'package:minicrm/features/assistant/data/embedder/flutter_gemma_embedder.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/context/data/repositories/document_chunk_repository.dart';
import 'package:minicrm/objectbox.g.dart' show Store;
import 'package:path_provider/path_provider.dart';

class AssistantTaskHandler extends TaskHandler {
  InferenceModel? _inferenceModel;
  InferenceChat? _chat;
  StreamSubscription<ModelResponse>? _generationSubscription;
  dio.CancelToken? _downloadCancel;
  bool _isInstalling = false;
  Directory? _modelsDir;
  Directory? _cacheDir;
  String? _currentModelPath;
  String? _currentBackend;
  ChatModelFamily _currentFamily = ChatModelFamily.general;
  int _currentMaxTokens = 4096;
  String _systemInstruction = _defaultSystemInstruction;
  bool _thinkingEnabled = true;
  final List<({bool isUser, String text})> _sessionHistory = [];
  Completer<void> _initialized = Completer<void>();
  Embedder? _embedder;
  String? _embedderModelPath;
  String? _embedderTokenizerPath;
  bool _isEmbedding = false;

  Store? _store;
  DocumentChunkRepository? _chunkRepo;
  bool _isDrainingQueue = false;
  bool _drainRequested = false;

  /// Resolves once [_handleInit] has finished and [_modelsDir]/[_cacheDir]
  /// are populated. Other handlers must await this before touching paths
  /// to avoid the "not initialised yet" race when commands arrive before
  /// the InitCommand has been processed. As a last resort this kicks off
  /// [_selfInit] so the worker is robust to the IPC InitCommand being
  /// dropped (e.g. when sent before the worker isolate has registered
  /// its data callback).
  Future<void> _awaitInit({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_initialized.isCompleted) return;
    unawaited(_selfInit());
    await _initialized.future.timeout(timeout);
  }

  static const String _defaultSystemInstruction =
      'You are MiniCRM, an on-device customer support assistant. '
      'Answer clearly and concisely using the provided context when available. '
      'If the context does not contain the answer, say you are not sure '
      'rather than guessing.';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[task] onStart starter=$starter ts=$timestamp');
    _emit(const StatusEvent(phase: AssistantPhase.idle));
    _emit(const ModelLoadedEvent());
    _emit(const LogEvent(message: 'Worker isolate booted'));
    debugPrint('[task] onStart: emitted idle');
    unawaited(_selfInit());
  }

  Future<void> _selfInit() async {
    if (_initialized.isCompleted) return;
    try {
      DartPluginRegistrant.ensureInitialized();
      final docs = await getApplicationDocumentsDirectory()
          .timeout(const Duration(seconds: 5));
      final modelsPath = '${docs.path}/models';
      final cachePath = '${docs.path}/litert_cache';
      debugPrint('[task] _selfInit: models=$modelsPath cache=$cachePath');
      await _handleInit({'modelsDir': modelsPath, 'cacheDir': cachePath});
      await _openWorkerStore(docs.path);
      await _initFlutterGemma();
    } on Object catch (e, st) {
      debugPrint('[task] _selfInit failed: $e\n$st');
    }
  }

  Future<void> _initFlutterGemma() async {
    try {
      await FlutterGemma.initialize();
      debugPrint('[task] FlutterGemma.initialize() ok');
    } on Object catch (e, st) {
      debugPrint('[task] FlutterGemma.initialize() failed: $e\n$st');
    }
  }

  Future<void> _openWorkerStore(String docsPath) async {
    if (_store != null) return;
    try {
      _store = await ObjectBoxStore.openAt(docsPath);
      _chunkRepo = DocumentChunkRepository(_store!);
      final pending = _chunkRepo!.countUnembedded();
      debugPrint('[task] worker store opened, pending=$pending');
      if (pending > 0) {
        _requestDrain();
      }
    } on Object catch (e, st) {
      debugPrint('[task] _openWorkerStore failed: $e\n$st');
    }
  }

  Future<void> _handleInit(Map<String, dynamic> map) async {
    debugPrint('[task] _handleInit: $map');
    try {
      final modelsPath = map['modelsDir'] as String;
      final cachePath = map['cacheDir'] as String;
      _modelsDir = Directory(modelsPath);
      _cacheDir = Directory(cachePath);
      if (!_modelsDir!.existsSync()) {
        _modelsDir!.createSync(recursive: true);
      }
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
      if (!_initialized.isCompleted) {
        _initialized.complete();
      }
      _emitModelsList();
      _emit(LogEvent(message: 'Init complete: models=$modelsPath'));
      _emitCurrentState();
      debugPrint('[task] _handleInit done');
    } on Object catch (e, st) {
      debugPrint('[task] Init error: $e\n$st');
      if (!_initialized.isCompleted) {
        _initialized.completeError(e, st);
        _initialized = Completer<void>();
      }
      _emit(StatusEvent(phase: AssistantPhase.error, detail: e.toString()));
    }
  }

  void _emitCurrentState() {
    final modelPath = _currentModelPath;
    if (modelPath != null) {
      final file = File(modelPath);
      _emit(
        ModelLoadedEvent(
          path: modelPath,
          name: file.uri.pathSegments.last,
          sizeBytes: file.existsSync() ? file.lengthSync() : null,
          backend: _currentBackend,
        ),
      );
      if (_isInstalling) {
        return;
      }
      _emit(
        StatusEvent(
          phase: _generationSubscription != null
              ? AssistantPhase.generating
              : AssistantPhase.ready,
        ),
      );
    } else {
      _emit(const ModelLoadedEvent());
      if (!_isInstalling) {
        _emit(const StatusEvent(phase: AssistantPhase.idle));
      }
    }

    final embedder = _embedder;
    if (embedder != null &&
        _embedderModelPath != null &&
        _embedderTokenizerPath != null) {
      _emit(
        EmbedderLoadedEvent(
          modelPath: _embedderModelPath,
          tokenizerPath: _embedderTokenizerPath,
          dim: embedder.embeddingDim,
          backend: embedder.backendName,
          runtime: embedder.runtime.id,
        ),
      );
    } else {
      _emit(const EmbedderLoadedEvent());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    _downloadCancel?.cancel('task destroyed');
    _downloadCancel = null;
    await _disposeChat();
    await _inferenceModel?.close();
    _inferenceModel = null;
    _embedder?.dispose();
    _embedder = null;
    _embedderModelPath = null;
    _embedderTokenizerPath = null;
    _chunkRepo = null;
    _store?.close();
    _store = null;
    _modelsDir = null;
    _cacheDir = null;
    if (_initialized.isCompleted) {
      _initialized = Completer<void>();
    }
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[task] onReceiveData: $data');
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    switch (map['kind']) {
      case AssistantIpcKind.init:
        unawaited(_handleInit(map));
      case AssistantIpcKind.install:
        unawaited(_handleInstall(map));
      case AssistantIpcKind.generate:
        unawaited(_handleGenerate(map));
      case AssistantIpcKind.stop:
        unawaited(_handleStop());
      case AssistantIpcKind.listModels:
        unawaited(_handleListModels());
      case AssistantIpcKind.loadModel:
        unawaited(_handleLoadModel(map));
      case AssistantIpcKind.unloadModel:
        unawaited(_handleUnloadModel());
      case AssistantIpcKind.deleteModel:
        unawaited(_handleDeleteModel(map));
      case AssistantIpcKind.setSystemPrompt:
        unawaited(_handleSetSystemPrompt(map));
      case AssistantIpcKind.switchChat:
        unawaited(_handleSwitchChat(map));
      case AssistantIpcKind.installEmbedder:
        unawaited(_handleInstallEmbedder(map));
      case AssistantIpcKind.loadEmbedder:
        unawaited(_handleLoadEmbedder(map));
      case AssistantIpcKind.unloadEmbedder:
        unawaited(_handleUnloadEmbedder());
      case AssistantIpcKind.embed:
        unawaited(_handleEmbed(map));
      case AssistantIpcKind.enqueueEmbeddings:
        _requestDrain();
    }
  }

  void _requestDrain() {
    _drainRequested = true;
    if (_isDrainingQueue) return;
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    if (_isDrainingQueue) return;
    _isDrainingQueue = true;
    try {
      while (_drainRequested) {
        _drainRequested = false;
        await _drainOnce();
      }
    } finally {
      _isDrainingQueue = false;
    }
  }

  Future<void> _drainOnce() async {
    final repo = _chunkRepo;
    final embedder = _embedder;
    if (repo == null || embedder == null) {
      debugPrint(
        '[task][drain] skipped: repo=${repo != null} '
        'embedder=${embedder != null}',
      );
      return;
    }

    final initialPending = repo.countUnembedded();
    if (initialPending == 0) return;

    _emit(IndexingProgressEvent(processed: 0, total: initialPending));
    embedder.resetStats();
    final drainSw = Stopwatch()..start();
    debugPrint('[task][drain] start, $initialPending chunks pending');
    var embedded = 0;
    var failed = 0;
    var batches = 0;
    var consecutiveFailures = 0;
    const batchSize = 16;

    while (true) {
      final batchSw = Stopwatch()..start();
      final batch = repo.findUnembedded(limit: batchSize);
      if (batch.isEmpty) break;
      batches++;
      var batchEmbedded = 0;
      var batchFailed = 0;
      for (final chunk in batch) {
        if (_embedder == null) {
          debugPrint('[task][drain] aborted: embedder unloaded mid-run');
          embedder.logStatsSummary();
          _emit(IndexingDoneEvent(embedded: embedded, failed: failed));
          return;
        }
        try {
          final vec = await embedder.embed(chunk.text, isQuery: false);
          chunk.embedding = vec.toList(growable: false);
          repo.put(chunk);
          embedded++;
          batchEmbedded++;
          consecutiveFailures = 0;
        } on Object catch (e) {
          failed++;
          batchFailed++;
          consecutiveFailures++;
          if (failed <= 3 || failed % 50 == 0) {
            debugPrint('[task][drain] embed failed: $e');
          }
        }
        final isLastInBatch = chunk == batch.last;
        if (((embedded + failed) % 4 == 0) || isLastInBatch) {
          final stats = embedder.stats;
          final remainingNow = initialPending - (embedded + failed);
          _emit(
            IndexingProgressEvent(
              processed: embedded + failed,
              total: initialPending,
              avgMs: stats.avgMs,
              etaMs: (stats.avgMs * remainingNow).round(),
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        if (consecutiveFailures >= 10) {
          debugPrint(
            '[task][drain] aborting after $consecutiveFailures consecutive '
            'failures',
          );
          embedder.logStatsSummary();
          _emit(IndexingDoneEvent(embedded: embedded, failed: failed));
          return;
        }
      }
      final s = embedder.stats;
      final remaining = repo.countUnembedded();
      final etaMs = s.avgMs * remaining;
      debugPrint(
        '[task][drain] batch=$batches done in ${batchSw.elapsedMilliseconds}ms '
        '(+${batchEmbedded}ok/${batchFailed}err) '
        'progress=${embedded + failed}/$initialPending '
        'remaining=$remaining avg=${s.avgMs.toStringAsFixed(1)}ms '
        'eta=${(etaMs / 1000).toStringAsFixed(1)}s',
      );
    }

    embedder.logStatsSummary();
    debugPrint(
      '[task][drain] COMPLETE in '
      '${(drainSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s: '
      'embedded=$embedded failed=$failed batches=$batches',
    );
    _emit(IndexingDoneEvent(embedded: embedded, failed: failed));
  }

  Future<void> _handleSetSystemPrompt(Map<String, dynamic> map) async {
    final prompt = (map['prompt'] as String?)?.trim();
    final next = (prompt == null || prompt.isEmpty)
        ? _defaultSystemInstruction
        : prompt;
    if (next == _systemInstruction) return;
    _systemInstruction = next;
    _emit(const LogEvent(message: 'System prompt updated'));
    final model = _inferenceModel;
    if (model == null) return;
    await _resetChat();
  }

  Future<void> _ensureRoomForTurn(String newPrompt) async {
    final model = _inferenceModel;
    if (model == null || _chat == null) return;
    const responseReserve = 768;
    final budget = _currentMaxTokens - responseReserve;
    final newEst = _estimateTokens(newPrompt);
    if (_estimateSessionTokens() + newEst <= budget) return;

    final trimmed = _selectReplayTail(
      _sessionHistory,
      _currentMaxTokens,
      reserveForNextTurn: responseReserve + newEst + 256,
    );
    _emit(LogEvent(
      message: 'Trimming chat session — kept ${trimmed.length} of '
          '${_sessionHistory.length} prior turns (KV cache nearing limit)',
    ));
    await _disposeChat();
    _chat = await model.createChat(
      systemInstruction: _systemInstruction,
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      isThinking: _thinkingEnabled && _currentFamily.hasThoughts,
      modelType: _toFlutterGemmaModelType(_currentFamily),
    );
    _sessionHistory
      ..clear()
      ..addAll(trimmed);
    for (final m in trimmed) {
      try {
        await _chat!.addQueryChunk(Message(text: m.text, isUser: m.isUser));
      } on Object catch (e) {
        debugPrint('session trim replay halted: $e');
        break;
      }
    }
  }

  Future<void> _resetChat() async {
    final model = _inferenceModel;
    if (model == null) return;
    await _disposeChat();
    _sessionHistory.clear();
    _chat = await model.createChat(
      systemInstruction: _systemInstruction,
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      isThinking: _thinkingEnabled && _currentFamily.hasThoughts,
      modelType: _toFlutterGemmaModelType(_currentFamily),
    );
  }

  /// Tear down the currently-active chat + native session.
  ///
  /// CRITICAL: the underlying `FfiInferenceModel` caches the in-flight
  /// `createSession()` future in `_createCompleter` and short-circuits any
  /// subsequent call until the *session* fires its `onClose` callback. If
  /// we don't call `session.close()` before creating a new chat, the new
  /// chat shares the previous chat's KV cache — replaying history then
  /// overruns `FillAttentionMask` and segfaults inside libLiteRtLm.so.
  Future<void> _disposeChat() async {
    final chat = _chat;
    _chat = null;
    if (chat == null) return;
    try {
      await chat.session.stopGeneration();
    } on Object catch (_) {}
    try {
      await chat.session.close();
    } on Object catch (e) {
      debugPrint('chat session close error: $e');
    }
  }

  Future<void> _handleSwitchChat(Map<String, dynamic> map) async {
    await _awaitInit();
    final model = _inferenceModel;
    if (model == null) {
      _emit(
        const StatusEvent(
          phase: AssistantPhase.error,
          detail: 'No model loaded — load a model before switching chats',
        ),
      );
      return;
    }

    final systemInstruction =
        (map['systemInstruction'] as String?)?.trim().isNotEmpty == true
            ? map['systemInstruction'] as String
            : _defaultSystemInstruction;
    final family = ChatModelFamilyX.parse(map['chatFamily'] as String?);
    final rawHistory = map['history'];
    final history = rawHistory is List
        ? rawHistory
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (e) => (
                isUser: (e['role'] as String?) == 'user',
                text: (e['text'] as String?) ?? '',
              ),
            )
            .where((m) => m.text.isNotEmpty)
            .toList()
        : const <({bool isUser, String text})>[];

    final thinkingRequested = (map['thinking'] as bool?) ?? true;
    final isThinking = thinkingRequested && family.hasThoughts;

    _emit(const StatusEvent(phase: AssistantPhase.loading));
    _emit(LogEvent(
      message: 'Switching chat (${history.length} prior turns, '
          'thinking=${isThinking ? "on" : "off"})…',
    ));

    await _generationSubscription?.cancel();
    _generationSubscription = null;
    await _disposeChat();

    _systemInstruction = systemInstruction;
    _currentFamily = family;
    _thinkingEnabled = isThinking;

    _chat = await model.createChat(
      systemInstruction: systemInstruction,
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      isThinking: isThinking,
      modelType: _toFlutterGemmaModelType(family),
    );

    final replay = _selectReplayTail(history, _currentMaxTokens);
    if (replay.length < history.length) {
      _emit(LogEvent(
        message: 'Replaying last ${replay.length} of ${history.length} turns '
            '(KV cache = $_currentMaxTokens tokens)',
      ));
    }
    _sessionHistory.clear();
    var replayed = 0;
    for (final m in replay) {
      try {
        await _chat!.addQueryChunk(Message(text: m.text, isUser: m.isUser));
        _sessionHistory.add(m);
        replayed += 1;
      } on Object catch (e) {
        debugPrint('switchChat replay halted at $replayed turns: $e');
        break;
      }
    }

    _emit(const StatusEvent(phase: AssistantPhase.ready));
  }

  static const double _avgCharsPerToken = 2.5;

  static int _estimateTokens(String text) =>
      (text.length / _avgCharsPerToken).ceil();

  int _estimateSessionTokens() {
    var total = _estimateTokens(_systemInstruction) + 32;
    for (final m in _sessionHistory) {
      total += _estimateTokens(m.text) + 8;
    }
    return total;
  }

  List<({bool isUser, String text})> _selectReplayTail(
    List<({bool isUser, String text})> history,
    int maxTokens, {
    int reserveForNextTurn = 1024,
  }) {
    final budgetChars =
        ((maxTokens - reserveForNextTurn).clamp(256, maxTokens) *
                _avgCharsPerToken)
            .toInt();
    if (history.isEmpty) return const [];
    var chars = 0;
    var cut = history.length;
    for (var i = history.length - 1; i >= 0; i--) {
      final next = chars + history[i].text.length + 16;
      if (next > budgetChars) break;
      chars = next;
      cut = i;
    }
    while (cut < history.length && !history[cut].isUser) {
      cut += 1;
    }
    return history.sublist(cut);
  }

  ModelType _toFlutterGemmaModelType(ChatModelFamily family) => switch (family) {
        ChatModelFamily.gemma4 => ModelType.gemma4,
        ChatModelFamily.deepSeek => ModelType.deepSeek,
        ChatModelFamily.qwen => ModelType.qwen,
        ChatModelFamily.qwen3 => ModelType.qwen3,
        ChatModelFamily.general => ModelType.general,
      };

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'btn_stop') {
      unawaited(_handleStop());
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/assistant');
  }

  @override
  void onNotificationDismissed() {}

  Future<void> _handleInstall(Map<String, dynamic> map) async {
    if (_isInstalling) {
      _emit(const LogEvent(message: 'Install already in progress'));
      return;
    }
    _isInstalling = true;
    try {
      await _awaitInit();
      final url = map['url'] as String;
      final token = map['token'] as String?;
      final backendName = (map['backend'] as String?) ?? 'cpu';
      final loadAfterDownload = map['loadAfterDownload'] as bool? ?? true;
      final family = ChatModelFamilyX.parse(map['chatFamily'] as String?);
      final maxTokens = (map['maxTokens'] as num?)?.toInt() ?? 4096;

      _emit(const StatusEvent(phase: AssistantPhase.downloading));
      _emit(const ProgressEvent(percent: 0));

      if (loadAfterDownload) {
        await _disposeEngine();
      }

      _emit(LogEvent(message: 'Installing ${_filenameOf(url)} via flutter_gemma…'));
      final installation = await FlutterGemma.installModel(
        modelType: _toFlutterGemmaModelType(family),
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(url, token: token)
          .withProgress((p) {
        _emit(ProgressEvent(percent: p));
      }).install();

      _emit(const ProgressEvent(percent: 100));
      _emitModelsList();
      if (loadAfterDownload) {
        await _loadInferenceModel(
          modelPath: '', // already-installed via fromNetwork, path managed by fg
          backend: backendName,
          family: family,
          maxTokens: maxTokens,
          displayName: installation.modelId,
        );
      } else {
        _emit(LogEvent(message: 'Downloaded ${installation.modelId}'));
        _emit(const StatusEvent(phase: AssistantPhase.idle));
        unawaited(
          FlutterForegroundTask.updateService(
            notificationTitle: 'Download complete',
            notificationText: installation.modelId,
          ),
        );
      }
    } on Object catch (e, st) {
      debugPrint('Install error: $e\n$st');
      final msg = _humanError(e);
      _emit(StatusEvent(phase: AssistantPhase.error, detail: msg));
      unawaited(
        FlutterForegroundTask.updateService(
          notificationTitle: 'Download failed',
          notificationText: '$msg — tap install to resume.',
        ),
      );
    } finally {
      _isInstalling = false;
      _downloadCancel = null;
    }
  }

  String _filenameOf(String url) {
    final segs = Uri.parse(url).pathSegments;
    return segs.isEmpty ? url : segs.last;
  }

  Future<void> _downloadWithResume({
    required String url,
    required String savePath,
    required String? token,
    int maxAttempts = 4,
  }) async {
    final partPath = '$savePath.part';
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final probe = await _probe(url: url, headers: headers);
    final totalSize = probe.totalSize;
    final acceptsRange = probe.acceptsRange;

    final partFile = File(partPath);
    final finalFile = File(savePath);

    if (totalSize != null && partFile.existsSync()) {
      final existing = partFile.lengthSync();
      if (existing == totalSize) {
        await partFile.rename(savePath);
        _emitProgress(received: totalSize, total: totalSize);
        return;
      }
      if (existing > totalSize) {
        await partFile.delete();
      }
    }
    if (finalFile.existsSync()) return;

    Exception? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      _downloadCancel = dio.CancelToken();
      try {
        final existing =
            partFile.existsSync() ? partFile.lengthSync() : 0;
        final useRange = acceptsRange && existing > 0;
        if (existing > 0) {
          _emit(
            LogEvent(
              message: useRange
                  ? 'Resuming from ${_humanBytes(existing)}'
                  : 'Server does not support resume — restarting',
            ),
          );
          if (!useRange) {
            await partFile.delete();
          }
        }

        await _downloadOnce(
          url: url,
          partPath: partPath,
          headers: headers,
          rangeStart: useRange ? partFile.lengthSync() : 0,
          totalSize: totalSize,
        );

        if (totalSize != null &&
            partFile.existsSync() &&
            partFile.lengthSync() != totalSize) {
          throw StateError(
            'Incomplete download: ${partFile.lengthSync()}/$totalSize bytes',
          );
        }
        await partFile.rename(savePath);
        return;
      } on dio.DioException catch (e) {
        if (dio.CancelToken.isCancel(e)) {
          throw const _DownloadCancelled();
        }
        if (e.response?.statusCode == 401 ||
            e.response?.statusCode == 403) {
          throw _AuthFailure(
            'HuggingFace rejected the request (${e.response?.statusCode}). '
            'Check your token and accept the model license.',
          );
        }
        if (e.response?.statusCode == 416) {
          if (partFile.existsSync()) {
            await partFile.rename(savePath);
            return;
          }
        }
        lastError = e;
      } on _AuthFailure {
        rethrow;
      } on _DownloadCancelled {
        rethrow;
      } on Exception catch (e) {
        lastError = e;
      }

      if (attempt < maxAttempts - 1) {
        final delaySeconds = 1 << attempt;
        _emit(
          LogEvent(
            message: 'Retrying in ${delaySeconds}s '
                '(attempt ${attempt + 2}/$maxAttempts)…',
          ),
        );
        await Future<void>.delayed(Duration(seconds: delaySeconds));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw StateError('Download failed after $maxAttempts attempts');
  }

  Future<void> _downloadOnce({
    required String url,
    required String partPath,
    required Map<String, String> headers,
    required int rangeStart,
    required int? totalSize,
  }) async {
    final client = dio.Dio();
    var lastPercent = -1;
    final requestHeaders = <String, String>{
      ...headers,
      if (rangeStart > 0) 'Range': 'bytes=$rangeStart-',
    };
    await client.download(
      url,
      partPath,
      cancelToken: _downloadCancel,
      deleteOnError: false,
      fileAccessMode: rangeStart > 0
          ? dio.FileAccessMode.append
          : dio.FileAccessMode.write,
      options: dio.Options(
        headers: requestHeaders,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 5),
        validateStatus: (s) => s != null && s >= 200 && s < 400,
      ),
      onReceiveProgress: (count, _) {
        final received = rangeStart + count;
        if (totalSize == null || totalSize <= 0) {
          _emitProgress(received: received, total: null);
          return;
        }
        final pct = (received * 100 ~/ totalSize).clamp(0, 100);
        if (pct == lastPercent) return;
        lastPercent = pct;
        _emitProgress(received: received, total: totalSize);
      },
    );
  }

  Future<_Probe> _probe({
    required String url,
    required Map<String, String> headers,
  }) async {
    final client = dio.Dio();
    try {
      final response = await client.head<void>(
        url,
        cancelToken: _downloadCancel,
        options: dio.Options(
          headers: headers,
          followRedirects: true,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      final lenStr = response.headers.value('content-length');
      final acceptRanges = response.headers.value('accept-ranges');
      return _Probe(
        totalSize: lenStr == null ? null : int.tryParse(lenStr),
        acceptsRange: acceptRanges?.toLowerCase() == 'bytes',
      );
    } on dio.DioException catch (e) {
      if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403) {
        throw _AuthFailure(
          'HuggingFace rejected the request (${e.response?.statusCode}). '
          'Check your token and accept the model license.',
        );
      }
      return const _Probe(totalSize: null, acceptsRange: false);
    } on Object {
      return const _Probe(totalSize: null, acceptsRange: false);
    }
  }

  void _emitProgress({required int received, required int? total}) {
    final pct = (total == null || total <= 0)
        ? 0
        : (received * 100 ~/ total).clamp(0, 100);
    _emit(
      ProgressEvent(
        percent: pct,
        receivedBytes: received,
        totalBytes: total,
      ),
    );
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: 'Downloading model',
        notificationText: total == null
            ? _humanBytes(received)
            : '$pct% · ${_humanBytes(received)} / ${_humanBytes(total)}',
      ),
    );
  }

  String _humanBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  String _humanError(Object e) {
    if (e is dio.DioException) {
      return switch (e.type) {
        dio.DioExceptionType.connectionTimeout ||
        dio.DioExceptionType.sendTimeout ||
        dio.DioExceptionType.receiveTimeout =>
          'Network timeout',
        dio.DioExceptionType.connectionError => 'Network unreachable',
        dio.DioExceptionType.badResponse =>
          'Server error ${e.response?.statusCode ?? ''}'.trim(),
        _ => e.message ?? 'Download failed',
      };
    }
    return e.toString();
  }

  Future<void> _loadInferenceModel({
    required String modelPath,
    required String backend,
    required ChatModelFamily family,
    required int maxTokens,
    String? displayName,
  }) async {
    try {
      _emit(const StatusEvent(phase: AssistantPhase.loading));
      unawaited(
        FlutterForegroundTask.updateService(
          notificationTitle: 'Loading model',
          notificationText: 'Preparing the on-device playground…',
        ),
      );

      if (modelPath.isNotEmpty && File(modelPath).existsSync()) {
        _emit(LogEvent(message: 'Registering ${_filenameOf(modelPath)} with flutter_gemma…'));
        await FlutterGemma.installModel(
          modelType: _toFlutterGemmaModelType(family),
          fileType: ModelFileType.litertlm,
        ).fromFile(modelPath).install();
      }

      final preferredBackend = _parsePreferredBackend(backend);
      _inferenceModel = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
      );

      _currentModelPath = modelPath;
      _currentBackend = backend;
      _currentFamily = family;
      _currentMaxTokens = maxTokens;

      await _resetChat();

      final shownName = displayName ??
          (modelPath.isNotEmpty
              ? _filenameOf(modelPath)
              : 'active inference model');
      final sizeBytes = modelPath.isNotEmpty && File(modelPath).existsSync()
          ? File(modelPath).lengthSync()
          : null;
      _emit(
        ModelLoadedEvent(
          path: modelPath,
          name: shownName,
          sizeBytes: sizeBytes,
          backend: backend,
        ),
      );
      _emit(const StatusEvent(phase: AssistantPhase.ready));

      unawaited(
        FlutterForegroundTask.updateService(
          notificationTitle: 'Playground ready',
          notificationText:
              'Running $shownName on ${backend.toUpperCase()}.',
        ),
      );
    } on Object catch (e, st) {
      debugPrint('Load error: $e\n$st');
      _currentModelPath = null;
      _currentBackend = null;
      _emit(const ModelLoadedEvent());
      _emit(StatusEvent(phase: AssistantPhase.error, detail: e.toString()));
    }
  }

  String _composePrompt({
    required String prompt,
    required List<String> chunks,
  }) {
    if (chunks.isEmpty) return prompt;
    final buf = StringBuffer()
      ..writeln('Use the following context to answer the question. '
          'If the context does not contain the answer, say you are not sure.')
      ..writeln()
      ..writeln('--- Context ---');
    for (var i = 0; i < chunks.length; i++) {
      buf
        ..writeln('[${i + 1}] ${chunks[i].trim()}')
        ..writeln();
    }
    buf
      ..writeln('--- Question ---')
      ..writeln(prompt);
    return buf.toString();
  }

  Future<void> _handleGenerate(Map<String, dynamic> map) async {
    final requestId = map['requestId'] as String;
    final prompt = map['prompt'] as String;
    final rawContext = map['context'];
    final contextChunks = rawContext is List
        ? rawContext.map((e) => e.toString()).toList()
        : const <String>[];

    final chat = _chat;
    if (chat == null) {
      _emit(
        const StatusEvent(
          phase: AssistantPhase.error,
          detail: 'No model loaded',
        ),
      );
      return;
    }

    final composed = _composePrompt(prompt: prompt, chunks: contextChunks);

    _emit(const StatusEvent(phase: AssistantPhase.generating));
    if (contextChunks.isNotEmpty) {
      _emit(
        LogEvent(
          message: 'Retrieved ${contextChunks.length} context chunk'
              '${contextChunks.length == 1 ? '' : 's'} for this turn',
        ),
      );
    }
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: 'Generating…',
        notificationText: prompt.length > 60
            ? '${prompt.substring(0, 60)}…'
            : prompt,
        notificationButtons: const [
          NotificationButton(id: 'btn_stop', text: 'Stop'),
        ],
      ),
    );

    final textBuffer = StringBuffer();
    try {
      await _ensureRoomForTurn(composed);
      final liveChat = _chat;
      if (liveChat == null) {
        _emit(
          const StatusEvent(
            phase: AssistantPhase.error,
            detail: 'Chat session unavailable after trim',
          ),
        );
        return;
      }
      await liveChat.addQueryChunk(Message(text: composed, isUser: true));
      _sessionHistory.add((isUser: true, text: composed));

      final completer = Completer<void>();
      _generationSubscription = liveChat.generateChatResponseAsync().listen(
        (response) {
          switch (response) {
            case TextResponse(:final token):
              if (token.isEmpty) break;
              textBuffer.write(token);
              _emit(TokenEvent(requestId: requestId, token: token));
            case ThinkingResponse(:final content):
              if (content.isEmpty) break;
              _emit(
                ThinkingTokenEvent(requestId: requestId, token: content),
              );
            default:
              break;
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('Generation error: $e\n$st');
          _emit(StatusEvent(phase: AssistantPhase.error, detail: e.toString()));
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      final finalText = textBuffer.toString();
      if (finalText.isNotEmpty) {
        _sessionHistory.add((isUser: false, text: finalText));
      }
      _emit(DoneEvent(requestId: requestId, text: finalText));
      _emit(const StatusEvent(phase: AssistantPhase.ready));
    } on Object catch (e, st) {
      debugPrint('Generate error: $e\n$st');
      _emit(StatusEvent(phase: AssistantPhase.error, detail: e.toString()));
    } finally {
      await _generationSubscription?.cancel();
      _generationSubscription = null;
      unawaited(
        FlutterForegroundTask.updateService(
          notificationTitle: 'Playground ready',
          notificationText:
              'Running on-device flutter_gemma in foreground.',
          notificationButtons: const [],
        ),
      );
    }
  }

  Future<void> _handleStop() async {
    _downloadCancel?.cancel('user cancelled');
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    final session = _chat?.session;
    if (session != null) {
      try {
        await session.stopGeneration();
      } on Object catch (e) {
        debugPrint('stopGeneration error: $e');
      }
    }
    if (_inferenceModel != null) {
      _emit(const StatusEvent(phase: AssistantPhase.ready));
    } else {
      _emit(const StatusEvent(phase: AssistantPhase.idle));
    }
  }

  Future<void> _disposeEngine() async {
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    await _disposeChat();
    _sessionHistory.clear();
    await _inferenceModel?.close();
    _inferenceModel = null;
    _currentModelPath = null;
    _currentBackend = null;
    _emit(const ModelLoadedEvent());
  }

  Future<void> _handleLoadModel(Map<String, dynamic> map) async {
    await _awaitInit();
    final path = map['path'] as String;
    final backend = (map['backend'] as String?) ?? 'cpu';
    final family = ChatModelFamilyX.parse(map['chatFamily'] as String?);
    final maxTokens = (map['maxTokens'] as num?)?.toInt() ?? 4096;
    final file = File(path);
    if (!file.existsSync()) {
      _emit(
        const StatusEvent(
          phase: AssistantPhase.error,
          detail: 'Model file not found',
        ),
      );
      _emitModelsList();
      return;
    }
    if (_currentModelPath == path &&
        _currentBackend == backend &&
        _currentFamily == family &&
        _currentMaxTokens == maxTokens) {
      _emit(const StatusEvent(phase: AssistantPhase.ready));
      return;
    }
    await _disposeEngine();
    await _loadInferenceModel(
      modelPath: path,
      backend: backend,
      family: family,
      maxTokens: maxTokens,
    );
  }

  Future<void> _handleUnloadModel() async {
    if (_inferenceModel == null && _currentModelPath == null) {
      _emit(const StatusEvent(phase: AssistantPhase.idle));
      _emit(const ModelLoadedEvent());
      return;
    }
    _emit(const LogEvent(message: 'Unloading model…'));
    await _disposeEngine();
    _emit(const StatusEvent(phase: AssistantPhase.idle));
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: 'Playground ready',
        notificationText: 'No model loaded — open the app to pick one.',
      ),
    );
  }

  Future<void> _handleDeleteModel(Map<String, dynamic> map) async {
    await _awaitInit();
    final path = map['path'] as String;
    final file = File(path);
    if (_currentModelPath == path) {
      await _disposeEngine();
      _emit(const StatusEvent(phase: AssistantPhase.idle));
    }
    if (file.existsSync()) {
      try {
        await file.delete();
        _emit(
          LogEvent(message: 'Deleted ${file.uri.pathSegments.last}'),
        );
      } on Object catch (e) {
        _emit(
          StatusEvent(
            phase: AssistantPhase.error,
            detail: 'Delete failed: $e',
          ),
        );
      }
    }
    final part = File('$path.part');
    if (part.existsSync()) {
      try {
        await part.delete();
      } on Object {
        // best effort
      }
    }
    _emitModelsList();
  }

  Future<void> _handleListModels() async {
    try {
      await _awaitInit();
    } on TimeoutException {
      _emit(const ModelsListEvent(models: []));
      return;
    }
    _emitModelsList();
  }

  Future<void> _handleInstallEmbedder(Map<String, dynamic> map) async {
    if (_isInstalling) {
      _emit(const LogEvent(message: 'Install already in progress'));
      return;
    }
    _isInstalling = true;
    try {
      await _awaitInit();
      final modelUrl = map['modelUrl'] as String;
      final tokenizerUrl = map['tokenizerUrl'] as String;
      final token = map['token'] as String?;
      final loadAfterDownload = map['loadAfterDownload'] as bool? ?? true;
      final runtime = EmbedderRuntimeX.parse(map['runtime'] as String?);
      final backendStr = map['backend'] as String? ?? 'cpu';
      final sequenceLength = (map['sequenceLength'] as num?)?.toInt() ?? 512;
      final presetId = map['presetId'] as String?;

      _emit(const StatusEvent(phase: AssistantPhase.downloading));
      _emit(const ProgressEvent(percent: 0));

      switch (runtime) {
        case EmbedderRuntime.flutterGemma:
          await _installFlutterGemmaEmbedder(
            modelUrl: modelUrl,
            tokenizerUrl: tokenizerUrl,
            token: token,
            backend: backendStr,
            sequenceLength: sequenceLength,
            presetId: presetId,
            loadAfterDownload: loadAfterDownload,
          );
        case EmbedderRuntime.tflite:
          await _installTfliteEmbedder(
            modelUrl: modelUrl,
            tokenizerUrl: tokenizerUrl,
            token: token,
            backend: EmbedderBackendX.parse(backendStr),
            loadAfterDownload: loadAfterDownload,
          );
      }
    } on _DownloadCancelled {
      _emit(const StatusEvent(phase: AssistantPhase.idle, detail: 'Cancelled'));
    } on _AuthFailure catch (e) {
      _emit(StatusEvent(phase: AssistantPhase.error, detail: e.message));
    } on Object catch (e, st) {
      debugPrint('Embedder install error: $e\n$st');
      _emit(
        StatusEvent(
          phase: AssistantPhase.error,
          detail: _humanError(e),
        ),
      );
    } finally {
      _isInstalling = false;
      _downloadCancel = null;
    }
  }

  Future<void> _installTfliteEmbedder({
    required String modelUrl,
    required String tokenizerUrl,
    required String? token,
    required EmbedderBackend backend,
    required bool loadAfterDownload,
  }) async {
    final modelPath = await _resolveSavePath(modelUrl);
    final tokenizerPath = await _resolveSavePath(tokenizerUrl);

    final modelFile = File(modelPath);
    if (!modelFile.existsSync() || modelFile.lengthSync() == 0) {
      _emit(const LogEvent(message: 'Downloading embedder model…'));
      await _downloadWithResume(
        url: modelUrl,
        savePath: modelPath,
        token: token,
      );
    } else {
      _emit(const LogEvent(message: 'Embedder model already downloaded'));
    }

    final tokenizerFile = File(tokenizerPath);
    if (!tokenizerFile.existsSync() || tokenizerFile.lengthSync() == 0) {
      _emit(const LogEvent(message: 'Downloading tokenizer…'));
      await _downloadWithResume(
        url: tokenizerUrl,
        savePath: tokenizerPath,
        token: token,
      );
    } else {
      _emit(const LogEvent(message: 'Tokenizer already downloaded'));
    }

    _emit(const ProgressEvent(percent: 100));
    _emitModelsList();

    if (loadAfterDownload) {
      await _loadTfliteEmbedder(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        backend: backend,
      );
    } else {
      _emit(
        LogEvent(message: 'Downloaded ${modelFile.uri.pathSegments.last}'),
      );
      _emit(const StatusEvent(phase: AssistantPhase.idle));
    }
  }

  Future<void> _installFlutterGemmaEmbedder({
    required String modelUrl,
    required String tokenizerUrl,
    required String? token,
    required String backend,
    required int sequenceLength,
    required String? presetId,
    required bool loadAfterDownload,
  }) async {
    _emit(const LogEvent(message: 'Installing embedder via flutter_gemma…'));
    final descriptor = presetId ?? Uri.parse(modelUrl).pathSegments.last;
    final preferred = _parsePreferredBackend(backend);
    final embedder = await FlutterGemmaEmbedder.install(
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
      descriptor: descriptor,
      sequenceLength: sequenceLength,
      hfToken: token,
      preferredBackend: preferred,
      onModelProgress: (p) {
        _emit(ProgressEvent(percent: p));
      },
    );
    _emit(const ProgressEvent(percent: 100));
    _emitModelsList();
    if (loadAfterDownload) {
      _adoptFlutterGemmaEmbedder(embedder, descriptor: descriptor);
    } else {
      embedder.dispose();
      _emit(const StatusEvent(phase: AssistantPhase.idle));
    }
  }

  Future<void> _handleLoadEmbedder(Map<String, dynamic> map) async {
    await _awaitInit();
    final modelPath = map['modelPath'] as String;
    final tokenizerPath = map['tokenizerPath'] as String;
    final runtime = EmbedderRuntimeX.parse(map['runtime'] as String?);
    final backendStr = map['backend'] as String? ?? 'cpu';
    final sequenceLength = (map['sequenceLength'] as num?)?.toInt() ?? 512;
    final presetId = map['presetId'] as String?;
    switch (runtime) {
      case EmbedderRuntime.flutterGemma:
        await _loadFlutterGemmaEmbedder(
          modelPath: modelPath,
          tokenizerPath: tokenizerPath,
          descriptor: presetId ?? modelPath,
          backend: backendStr,
          sequenceLength: sequenceLength,
        );
      case EmbedderRuntime.tflite:
        await _loadTfliteEmbedder(
          modelPath: modelPath,
          tokenizerPath: tokenizerPath,
          backend: EmbedderBackendX.parse(backendStr),
        );
    }
  }

  Future<void> _loadTfliteEmbedder({
    required String modelPath,
    required String tokenizerPath,
    EmbedderBackend backend = EmbedderBackend.cpu,
  }) async {
    try {
      _emit(
        LogEvent(
          message: 'Loading tflite embedder on ${backend.name.toUpperCase()} '
              '(warming up)…',
        ),
      );
      _disposeEmbedder();
      _emit(const EmbedderLoadedEvent());
      final embedder = await EmbeddingGemmaEmbedder.load(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        backend: backend,
      );
      _embedder = embedder;
      _embedderModelPath = modelPath;
      _embedderTokenizerPath = tokenizerPath;
      _emit(
        EmbedderLoadedEvent(
          modelPath: modelPath,
          tokenizerPath: tokenizerPath,
          dim: embedder.embeddingDim,
          backend: embedder.backendName,
          runtime: embedder.runtime.id,
        ),
      );
      _requestDrain();
      final fallback = embedder.backend != backend
          ? ' (requested ${backend.name.toUpperCase()}, '
              'fell back to ${embedder.backend.name.toUpperCase()})'
          : '';
      _emit(
        LogEvent(
          message: 'Embedder ready on ${embedder.backendName.toUpperCase()}'
              '$fallback '
              '(${embedder.embeddingDim}-dim, seq=${embedder.sequenceLength}, '
              'runtime=tflite)',
        ),
      );
    } on Object catch (e, st) {
      debugPrint('tflite embedder load error: $e\n$st');
      _embedder = null;
      _embedderModelPath = null;
      _embedderTokenizerPath = null;
      _emit(const EmbedderLoadedEvent());
      _emit(
        StatusEvent(
          phase: AssistantPhase.error,
          detail: 'Embedder load failed: $e',
        ),
      );
    }
  }

  Future<void> _loadFlutterGemmaEmbedder({
    required String modelPath,
    required String tokenizerPath,
    required String descriptor,
    required String backend,
    required int sequenceLength,
  }) async {
    try {
      _emit(
        LogEvent(
          message: 'Loading flutter_gemma embedder on '
              '${backend.toUpperCase()}…',
        ),
      );
      _disposeEmbedder();
      _emit(const EmbedderLoadedEvent());
      final preferred = _parsePreferredBackend(backend);
      final embedder = await FlutterGemmaEmbedder.loadFromFile(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        descriptor: descriptor,
        sequenceLength: sequenceLength,
        preferredBackend: preferred,
      );
      _adoptFlutterGemmaEmbedder(
        embedder,
        descriptor: descriptor,
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
      );
    } on Object catch (e, st) {
      debugPrint('flutter_gemma embedder load error: $e\n$st');
      _embedder = null;
      _embedderModelPath = null;
      _embedderTokenizerPath = null;
      _emit(const EmbedderLoadedEvent());
      _emit(
        StatusEvent(
          phase: AssistantPhase.error,
          detail: 'Embedder load failed: $e',
        ),
      );
    }
  }

  void _adoptFlutterGemmaEmbedder(
    Embedder embedder, {
    required String descriptor,
    String? modelPath,
    String? tokenizerPath,
  }) {
    final reportedModelPath = modelPath ?? descriptor;
    final reportedTokenizerPath = tokenizerPath ?? descriptor;
    _embedder = embedder;
    _embedderModelPath = reportedModelPath;
    _embedderTokenizerPath = reportedTokenizerPath;
    _emit(
      EmbedderLoadedEvent(
        modelPath: reportedModelPath,
        tokenizerPath: reportedTokenizerPath,
        dim: embedder.embeddingDim,
        backend: embedder.backendName,
        runtime: embedder.runtime.id,
      ),
    );
    _requestDrain();
    _emit(
      LogEvent(
        message: 'Embedder ready on ${embedder.backendName.toUpperCase()} '
            '(${embedder.embeddingDim}-dim, seq=${embedder.sequenceLength}, '
            'runtime=flutter_gemma)',
      ),
    );
  }

  void _disposeEmbedder() {
    _embedder?.dispose();
    _embedder = null;
    _embedderModelPath = null;
    _embedderTokenizerPath = null;
  }

  PreferredBackend? _parsePreferredBackend(String? value) {
    return switch (value) {
      'gpu' => PreferredBackend.gpu,
      'cpu' => PreferredBackend.cpu,
      _ => null,
    };
  }

  Future<void> _handleUnloadEmbedder() async {
    _disposeEmbedder();
    _emit(const EmbedderLoadedEvent());
    _emit(const LogEvent(message: 'Embedder unloaded'));
  }

  Future<void> _handleEmbed(Map<String, dynamic> map) async {
    final requestId = map['requestId'] as String;
    final text = (map['text'] as String?) ?? '';
    final isQuery = (map['isQuery'] as bool?) ?? false;
    final embedder = _embedder;
    if (embedder == null) {
      _emit(
        EmbeddingEvent(
          requestId: requestId,
          vector: const [],
          error: 'No embedder loaded',
        ),
      );
      return;
    }
    if (text.trim().isEmpty) {
      _emit(
        EmbeddingEvent(
          requestId: requestId,
          vector: const [],
          error: 'Empty input',
        ),
      );
      return;
    }
    // Serialise embed calls to avoid concurrent interpreter access.
    while (_isEmbedding) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _isEmbedding = true;
    try {
      final vector = await embedder.embed(text, isQuery: isQuery);
      _emit(
        EmbeddingEvent(
          requestId: requestId,
          vector: vector.toList(growable: false),
        ),
      );
    } on Object catch (e, st) {
      debugPrint('Embed error: $e\n$st');
      _emit(
        EmbeddingEvent(
          requestId: requestId,
          vector: const [],
          error: e.toString(),
        ),
      );
    } finally {
      _isEmbedding = false;
    }
  }

  void _emitModelsList() {
    final dir = _modelsDir;
    if (dir == null || !dir.existsSync()) {
      _emit(const ModelsListEvent(models: []));
      return;
    }
    final entries = dir
        .listSync(followLinks: false)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.litertlm') ||
              f.path.endsWith('.tflite') ||
              f.path.endsWith('.model'),
        )
        .map((f) {
      return <String, dynamic>{
        'path': f.path,
        'name': f.uri.pathSegments.last,
        'size': f.lengthSync(),
      };
    }).toList()
      ..sort(
        (a, b) => (a['name']! as String).compareTo(b['name']! as String),
      );
    _emit(ModelsListEvent(models: entries));
  }

  Future<String> _resolveSavePath(String url) async {
    final dir = _modelsDir;
    if (dir == null) {
      throw StateError(
        'Assistant worker not initialised yet (no models directory).',
      );
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final segments = Uri.parse(url).pathSegments;
    final name = segments.isNotEmpty ? segments.last : 'model.litertlm';
    return '${dir.path}/$name';
  }

  void _emit(AssistantEvent event) {
    final payload = switch (event) {
      StatusEvent() => event.toMap(),
      ProgressEvent() => event.toMap(),
      TokenEvent() => event.toMap(),
      ThinkingTokenEvent() => event.toMap(),
      DoneEvent() => event.toMap(),
      LogEvent() => event.toMap(),
      ModelsListEvent() => event.toMap(),
      ModelLoadedEvent() => event.toMap(),
      EmbedderLoadedEvent() => event.toMap(),
      EmbeddingEvent() => event.toMap(),
      IndexingProgressEvent() => event.toMap(),
      IndexingDoneEvent() => event.toMap(),
    };
    FlutterForegroundTask.sendDataToMain(payload);
  }
}

class _Probe {
  const _Probe({required this.totalSize, required this.acceptsRange});

  final int? totalSize;
  final bool acceptsRange;
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

class _AuthFailure implements Exception {
  const _AuthFailure(this.message);

  final String message;
}

@pragma('vm:entry-point')
void assistantTaskCallback() {
  debugPrint('[task] assistantTaskCallback: setting task handler');
  FlutterForegroundTask.setTaskHandler(AssistantTaskHandler());
  debugPrint('[task] assistantTaskCallback: handler set');
}
