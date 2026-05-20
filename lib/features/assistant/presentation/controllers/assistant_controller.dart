import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/data/repositories/object_box_chat_history_repository.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_status.dart';
import 'package:minicrm/features/assistant/domain/entities/chat_thread.dart';
import 'package:minicrm/features/assistant/domain/entities/installed_model.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';
import 'package:minicrm/features/assistant/domain/repositories/chat_history_repository.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_providers.dart';
import 'package:minicrm/features/context/presentation/controllers/context_providers.dart';
import 'package:minicrm/features/settings/presentation/controllers/settings_controller.dart';
import 'package:uuid/uuid.dart';

class AssistantUiState extends Equatable {
  const AssistantUiState({
    required this.status,
    required this.messages,
    required this.installedModels,
    required this.workerLog,
    this.activeThread,
    this.currentModel,
    this.currentBackend,
    this.lastError,
    this.embedderLoaded = false,
    this.embedderLoading = false,
    this.embedderModelPath,
    this.embedderBackend,
  });

  const AssistantUiState.initial()
      : status = const AssistantIdle(),
        messages = const [],
        installedModels = const [],
        workerLog = const [],
        activeThread = null,
        currentModel = null,
        currentBackend = null,
        lastError = null,
        embedderLoaded = false,
        embedderLoading = false,
        embedderModelPath = null,
        embedderBackend = null;

  final AssistantStatus status;
  final List<AssistantMessage> messages;
  final List<InstalledModel> installedModels;
  final List<String> workerLog;
  final ChatThread? activeThread;
  final InstalledModel? currentModel;
  final String? currentBackend;
  final String? lastError;
  final bool embedderLoaded;
  final bool embedderLoading;
  final String? embedderModelPath;
  final String? embedderBackend;

  AssistantUiState copyWith({
    AssistantStatus? status,
    List<AssistantMessage>? messages,
    List<InstalledModel>? installedModels,
    List<String>? workerLog,
    ChatThread? activeThread,
    bool clearActiveThread = false,
    InstalledModel? currentModel,
    String? currentBackend,
    bool clearCurrentModel = false,
    String? lastError,
    bool clearError = false,
    bool? embedderLoaded,
    bool? embedderLoading,
    String? embedderModelPath,
    String? embedderBackend,
    bool clearEmbedder = false,
  }) {
    return AssistantUiState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      installedModels: installedModels ?? this.installedModels,
      workerLog: workerLog ?? this.workerLog,
      activeThread: clearActiveThread ? null : (activeThread ?? this.activeThread),
      currentModel: clearCurrentModel ? null : (currentModel ?? this.currentModel),
      currentBackend:
          clearCurrentModel ? null : (currentBackend ?? this.currentBackend),
      lastError: clearError ? null : (lastError ?? this.lastError),
      embedderLoaded:
          !clearEmbedder && (embedderLoaded ?? this.embedderLoaded),
      embedderLoading: embedderLoading ?? this.embedderLoading,
      embedderModelPath: clearEmbedder
          ? null
          : (embedderModelPath ?? this.embedderModelPath),
      embedderBackend: clearEmbedder
          ? null
          : (embedderBackend ?? this.embedderBackend),
    );
  }

  @override
  List<Object?> get props => [
        status,
        messages,
        installedModels,
        workerLog,
        activeThread,
        currentModel,
        currentBackend,
        lastError,
        embedderLoaded,
        embedderLoading,
        embedderModelPath,
        embedderBackend,
      ];
}

class AssistantController extends Notifier<AssistantUiState> {
  StreamSubscription<AssistantEvent>? _subscription;
  final Uuid _uuid = const Uuid();
  String? _streamingMessageId;
  Completer<void>? _embedderLoadCompleter;

  @override
  AssistantUiState build() {
    final service = ref.watch(assistantServiceProvider);
    unawaited(_subscription?.cancel());
    _subscription = service.events.listen(_onEvent);
    ref
      ..onDispose(() => unawaited(_subscription?.cancel()))
      ..listen(settingsControllerProvider, (prev, next) {
        final prevPrompt = prev?.value?.systemPrompt;
        final nextPrompt = next.value?.systemPrompt;
        if (nextPrompt != null && nextPrompt != prevPrompt) {
          unawaited(_service.setSystemPrompt(nextPrompt));
        }
      });

    return const AssistantUiState.initial();
  }

  AssistantService get _service => ref.read(assistantServiceProvider);

  Future<ChatHistoryRepository> get _historyRepo =>
      ref.read(chatHistoryRepositoryProvider.future);

  Future<String> _defaultSystemInstruction() async {
    final settings = await ref.read(settingsControllerProvider.future);
    return settings.systemPrompt;
  }

  ChatModelFamily _familyForCurrentModel() {
    final model = state.currentModel;
    if (model == null) return ChatModelFamily.general;
    return ModelPresets.matchByFileName(model.name)?.chatFamily ??
        ChatModelFamily.general;
  }

  /// Create a brand new chat thread with the current model's family +
  /// the user's configured system prompt. Opens it as the active thread.
  Future<ChatThread> createThread({String? title}) async {
    final repo = await _historyRepo;
    final systemInstruction = await _defaultSystemInstruction();
    final family = _familyForCurrentModel();
    final thread = await repo.createThread(
      title: title ?? 'New chat',
      systemInstruction: systemInstruction,
      chatFamily: family,
      modelId: state.currentModel?.name,
    );
    await openThread(thread.id);
    return thread;
  }

  /// Make [threadId] the active conversation: hydrate the message list
  /// from ObjectBox and tell the worker to recreate its chat session and
  /// replay the history through `addQueryChunk` so the KV cache is warm.
  Future<void> openThread(String threadId) async {
    final repo = await _historyRepo;
    final thread = await repo.getThread(threadId);
    if (thread == null) return;
    final messages = await repo.getMessages(threadId);
    state = state.copyWith(
      activeThread: thread,
      messages: messages,
      clearError: true,
    );
    if (state.currentModel != null) {
      await _service.switchChat(
        threadId: thread.id,
        systemInstruction: thread.systemInstruction,
        chatFamily: thread.chatFamily.id,
        history: [
          for (final m in messages)
            {
              'role': m.role == AssistantRole.user ? 'user' : 'assistant',
              'text': m.text,
            },
        ],
      );
    }
  }

  Future<void> deleteThread(String threadId) async {
    final repo = await _historyRepo;
    await repo.deleteThread(threadId);
    if (state.activeThread?.id == threadId) {
      state = state.copyWith(
        clearActiveThread: true,
        messages: const [],
      );
    }
  }

  Future<void> renameThread({
    required String threadId,
    required String title,
  }) async {
    final repo = await _historyRepo;
    final thread = await repo.getThread(threadId);
    if (thread == null) return;
    final updated = thread.copyWith(title: title, updatedAt: DateTime.now());
    await repo.updateThread(updated);
    if (state.activeThread?.id == threadId) {
      state = state.copyWith(activeThread: updated);
    }
  }

  Future<void> start() async {
    debugPrint('[assistant] controller.start: requesting permissions');
    final granted = await _service.requestPermissions();
    debugPrint('[assistant] controller.start: granted=$granted');
    if (!granted) {
      state = state.copyWith(
        status: const AssistantError('Notification permission denied'),
        lastError: 'Notification permission denied',
      );
      return;
    }
    debugPrint('[assistant] controller.start: starting service');
    await _service.start();
    debugPrint('[assistant] controller.start: service.start returned');
    unawaited(_pushCurrentSystemPrompt());
  }

  Future<void> _pushCurrentSystemPrompt() async {
    try {
      final settings = await ref.read(settingsControllerProvider.future);
      await _service.setSystemPrompt(settings.systemPrompt);
    } on Object catch (e) {
      debugPrint('[assistant] _pushCurrentSystemPrompt failed: $e');
    }
  }

  Future<void> stop() async {
    await _service.stop();
    state = state.copyWith(
      status: const AssistantIdle(),
      clearCurrentModel: true,
    );
  }

  Future<void> unloadModel() async {
    state = state.copyWith(
      status: const AssistantIdle(),
      clearCurrentModel: true,
      clearError: true,
    );
    await _service.unloadModel();
  }

  Future<void> installModel({
    required String url,
    required String backend,
    String? token,
    bool loadAfterDownload = true,
    String chatFamily = 'general',
    int maxTokens = 4096,
  }) async {
    state = state.copyWith(
      status: const AssistantDownloading(percent: 0),
      clearError: true,
    );
    await _service.installModel(
      url: url,
      backend: backend,
      token: token,
      loadAfterDownload: loadAfterDownload,
      chatFamily: chatFamily,
      maxTokens: maxTokens,
    );
  }

  Future<void> refreshInstalledModels() async {
    await _service.listInstalledModels();
  }

  Future<void> loadInstalledModel({
    required InstalledModel model,
    required String backend,
    String chatFamily = 'general',
    int maxTokens = 4096,
  }) async {
    state = state.copyWith(
      status: const AssistantLoading(),
      clearError: true,
    );
    await _service.loadInstalledModel(
      path: model.path,
      backend: backend,
      chatFamily: chatFamily,
      maxTokens: maxTokens,
    );
  }

  Future<void> deleteInstalledModel(InstalledModel model) async {
    await _service.deleteInstalledModel(path: model.path);
  }

  Future<void> installEmbedder({
    required String modelUrl,
    required String tokenizerUrl,
    String? token,
    bool loadAfterDownload = true,
    String runtime = 'tflite',
    String backend = 'cpu',
    int? sequenceLength,
    String? presetId,
  }) async {
    state = state.copyWith(
      status: const AssistantDownloading(percent: 0),
      clearError: true,
    );
    await _service.installEmbedder(
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
      token: token,
      loadAfterDownload: loadAfterDownload,
      runtime: runtime,
      backend: backend,
      sequenceLength: sequenceLength,
      presetId: presetId,
    );
  }

  Future<void> loadEmbedder({
    required String modelPath,
    required String tokenizerPath,
    String backend = 'cpu',
    String runtime = 'tflite',
    int? sequenceLength,
    String? presetId,
  }) async {
    final completer = Completer<void>();
    final previous = _embedderLoadCompleter;
    if (previous != null && !previous.isCompleted) {
      previous.completeError(
        StateError('Superseded by a newer embedder load request'),
      );
    }
    _embedderLoadCompleter = completer;
    state = state.copyWith(embedderLoading: true, clearError: true);
    try {
      await _service.loadEmbedder(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        backend: backend,
        runtime: runtime,
        sequenceLength: sequenceLength,
        presetId: presetId,
      );
      await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () =>
            throw TimeoutException('Embedder load timed out (>3 min).'),
      );
    } finally {
      if (identical(_embedderLoadCompleter, completer)) {
        _embedderLoadCompleter = null;
      }
      state = state.copyWith(embedderLoading: false);
    }
  }

  Future<void> unloadEmbedder() async {
    state = state.copyWith(
      embedderLoaded: false,
      clearEmbedder: true,
    );
    await _service.unloadEmbedder();
  }

  Future<void> send(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;

    if (state.activeThread == null) {
      await createThread();
    }

    final now = DateTime.now();
    final userMessage = AssistantMessage(
      id: _uuid.v4(),
      role: AssistantRole.user,
      text: trimmed,
      createdAt: now,
    );
    final assistantMessage = AssistantMessage(
      id: _uuid.v4(),
      role: AssistantRole.assistant,
      text: '',
      createdAt: now.add(const Duration(milliseconds: 1)),
      isStreaming: true,
    );
    _streamingMessageId = assistantMessage.id;

    state = state.copyWith(
      status: const AssistantGenerating(),
      messages: [...state.messages, userMessage, assistantMessage],
      clearError: true,
    );

    final activeThread = state.activeThread;
    if (activeThread != null) {
      try {
        final repo = await _historyRepo;
        await repo.appendMessage(
          threadId: activeThread.id,
          message: userMessage,
        );
        if (activeThread.title == 'New chat' || activeThread.title.isEmpty) {
          final title = trimmed.length > 40
              ? '${trimmed.substring(0, 40)}…'
              : trimmed;
          await renameThread(threadId: activeThread.id, title: title);
        }
      } on Object catch (e) {
        debugPrint('[assistant] persist user msg failed: $e');
      }
    }

    final contextChunks = await _retrieveContext(trimmed);

    try {
      await _service.generate(
        prompt: trimmed,
        contextChunks: contextChunks,
      );
    } on Object catch (e) {
      state = state.copyWith(
        status: AssistantError(e.toString()),
        lastError: e.toString(),
      );
    }
  }

  Future<void> stopGeneration() async {
    await _service.stopGeneration();
  }

  void _onEvent(AssistantEvent event) {
    switch (event) {
      case StatusEvent():
        state = state.copyWith(status: _statusFromEvent(event));
        if (event.phase == AssistantPhase.error) {
          final completer = _embedderLoadCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.completeError(
              event.detail ?? 'Embedder load failed',
            );
          }
        }
      case ProgressEvent():
        state = state.copyWith(
          status: AssistantDownloading(
            percent: event.percent,
            receivedBytes: event.receivedBytes,
            totalBytes: event.totalBytes,
          ),
        );
      case TokenEvent():
        _appendToken(event.token);
      case ThinkingTokenEvent():
        _appendThinking(event.token);
      case DoneEvent():
        _finalizeStreaming(event.text);
      case LogEvent():
        final next = [...state.workerLog, event.message];
        final trimmed =
            next.length > 50 ? next.sublist(next.length - 50) : next;
        state = state.copyWith(workerLog: trimmed);
      case ModelsListEvent():
        state = state.copyWith(
          installedModels: [
            for (final m in event.models) InstalledModel.fromMap(m),
          ],
        );
      case ModelLoadedEvent():
        if (event.path == null) {
          state = state.copyWith(clearCurrentModel: true);
        } else {
          state = state.copyWith(
            currentModel: InstalledModel(
              path: event.path!,
              name: event.name ?? event.path!.split('/').last,
              sizeBytes: event.sizeBytes ?? 0,
            ),
            currentBackend: event.backend,
          );
        }
      case EmbedderLoadedEvent():
        state = state.copyWith(
          embedderLoaded: event.isLoaded,
          embedderModelPath: event.modelPath,
          embedderBackend: event.backend,
          clearEmbedder: !event.isLoaded,
        );
        if (event.isLoaded) {
          final completer = _embedderLoadCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
      case EmbeddingEvent():
        break;
      case IndexingProgressEvent():
        break;
      case IndexingDoneEvent():
        break;
    }
  }

  AssistantStatus _statusFromEvent(StatusEvent event) {
    return switch (event.phase) {
      AssistantPhase.idle => const AssistantIdle(),
      AssistantPhase.downloading =>
        const AssistantDownloading(percent: 0),
      AssistantPhase.loading => const AssistantLoading(),
      AssistantPhase.ready => const AssistantReady(),
      AssistantPhase.generating => const AssistantGenerating(),
      AssistantPhase.error =>
        AssistantError(event.detail ?? 'Unknown error'),
      _ => state.status,
    };
  }

  void _appendToken(String token) {
    final id = _streamingMessageId;
    if (id == null) return;
    final updated = [
      for (final message in state.messages)
        if (message.id == id) message.append(token) else message,
    ];
    state = state.copyWith(messages: updated);
  }

  void _appendThinking(String token) {
    final id = _streamingMessageId;
    if (id == null) return;
    final updated = [
      for (final message in state.messages)
        if (message.id == id) message.appendThinking(token) else message,
    ];
    state = state.copyWith(messages: updated);
  }

  void _finalizeStreaming(String finalText) {
    final id = _streamingMessageId;
    if (id == null) return;
    final updated = [
      for (final message in state.messages)
        if (message.id == id) message.finalize(finalText) else message,
    ];
    state = state.copyWith(messages: updated, status: const AssistantReady());
    _streamingMessageId = null;
    final activeThread = state.activeThread;
    final finalized = updated.firstWhere(
      (m) => m.id == id,
      orElse: () => AssistantMessage(
        id: id,
        role: AssistantRole.assistant,
        text: finalText,
        createdAt: DateTime.now(),
      ),
    );
    if (activeThread != null) {
      unawaited(_persistAssistantMessage(activeThread.id, finalized));
    }
  }

  Future<void> _persistAssistantMessage(
    String threadId,
    AssistantMessage message,
  ) async {
    try {
      final repo = await _historyRepo;
      await repo.upsertMessage(threadId: threadId, message: message);
    } on Object catch (e) {
      debugPrint('[assistant] persist assistant msg failed: $e');
    }
  }

  Future<List<String>> _retrieveContext(String prompt) async {
    try {
      final settings = await ref.read(settingsControllerProvider.future);
      if (!settings.ragEnabled) return const [];
      final repo = await ref.read(documentChunkRepositoryProvider.future);

      if (state.embedderLoaded && repo.countWithEmbeddings() > 0) {
        try {
          final vec = await _service.embed(text: prompt, isQuery: true);
          if (vec.isNotEmpty) {
            final hits = repo.vectorSearch(vec, limit: 3);
            if (hits.isNotEmpty) {
              return [for (final h in hits) h.chunk.text];
            }
          }
        } on Object catch (e) {
          debugPrint('[assistant] vector retrieval failed, '
              'falling back to lexical: $e');
        }
      }

      final hits = repo.searchByKeywords(prompt, limit: 3);
      return [for (final c in hits) c.text];
    } on Object catch (e) {
      debugPrint('[assistant] _retrieveContext failed: $e');
      return const [];
    }
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantUiState>(
      AssistantController.new,
    );
