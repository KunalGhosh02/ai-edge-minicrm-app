import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/data/repositories/object_box_chat_history_repository.dart';
import 'package:minicrm/features/assistant/data/subscribers/chat_persistence_subscriber.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_status.dart';
import 'package:minicrm/features/assistant/domain/entities/chat_thread.dart';
import 'package:minicrm/features/assistant/domain/entities/installed_model.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';
import 'package:minicrm/features/assistant/domain/repositories/chat_history_repository.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_providers.dart';
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
  StreamSubscription<AssistantEvent>? _serviceSubscription;
  StreamSubscription<ChatEvent>? _busSubscription;
  StreamSubscription<List<AssistantMessage>>? _messagesSubscription;
  final Uuid _uuid = const Uuid();
  Completer<void>? _embedderLoadCompleter;

  List<AssistantMessage> _persistedMessages = const [];
  AssistantMessage? _inFlightAssistantMessage;

  @override
  AssistantUiState build() {
    final service = ref.watch(assistantServiceProvider);
    final bus = ref.watch(chatEventBusProvider);
    ref
      ..watch(chatPersistenceSubscriberProvider)
      ..watch(llmDriverSubscriberProvider);

    unawaited(_serviceSubscription?.cancel());
    unawaited(_busSubscription?.cancel());
    _serviceSubscription = service.events.listen(_onWorkerEvent);
    _busSubscription = bus.events.listen(_onChatEvent);

    ref
      ..onDispose(() {
        unawaited(_serviceSubscription?.cancel());
        unawaited(_busSubscription?.cancel());
        unawaited(_messagesSubscription?.cancel());
      })
      ..listen(settingsControllerProvider, (prev, next) {
        final prevPrompt = prev?.value?.systemPrompt;
        final nextPrompt = next.value?.systemPrompt;
        if (nextPrompt != null && nextPrompt != prevPrompt) {
          unawaited(_service.setSystemPrompt(nextPrompt));
        }
        final prevThinking = prev?.value?.thinkingEnabled;
        final nextThinking = next.value?.thinkingEnabled;
        if (nextThinking != null && nextThinking != prevThinking) {
          ref.read(llmDriverSubscriberProvider).invalidateWorkerSession();
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

  Future<void> openThread(String threadId) async {
    ref.read(llmDriverSubscriberProvider).abortInFlight();
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _persistedMessages = const [];
    _inFlightAssistantMessage = null;

    final repo = await _historyRepo;
    final thread = await repo.getThread(threadId);
    if (thread == null) return;
    final messages = await repo.getMessages(threadId);
    _persistedMessages = messages;
    state = state.copyWith(
      activeThread: thread,
      messages: messages,
      clearError: true,
    );

    _messagesSubscription = repo
        .watchMessages(threadId)
        .listen((rows) => _onDbMessages(threadId, rows));
  }

  Future<void> deleteThread(String threadId) async {
    final repo = await _historyRepo;
    await repo.deleteThread(threadId);
    if (state.activeThread?.id == threadId) {
      await _messagesSubscription?.cancel();
      _messagesSubscription = null;
      _persistedMessages = const [];
      _inFlightAssistantMessage = null;
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
    ref.read(llmDriverSubscriberProvider).invalidateWorkerSession();
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
    ref.read(llmDriverSubscriberProvider).invalidateWorkerSession();
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
    final activeThread = state.activeThread;
    if (activeThread == null) return;

    final userMessage = AssistantMessage(
      id: _uuid.v4(),
      role: AssistantRole.user,
      text: trimmed,
      createdAt: DateTime.now(),
    );

    if (activeThread.title == 'New chat' || activeThread.title.isEmpty) {
      final title = trimmed.length > 40
          ? '${trimmed.substring(0, 40)}…'
          : trimmed;
      unawaited(renameThread(threadId: activeThread.id, title: title));
    }

    state = state.copyWith(clearError: true);
    final history = <ChatTurnHistory>[
      for (final m in state.messages)
        ChatTurnHistory(
          role: m.role == AssistantRole.user ? 'user' : 'assistant',
          text: m.text,
        ),
    ];
    final settings = await ref.read(settingsControllerProvider.future);
    ref.read(chatEventBusProvider).publish(
          UserMessageSubmitted(
            threadId: activeThread.id,
            message: userMessage,
            replayHistory: history,
            systemInstruction: activeThread.systemInstruction,
            chatFamily: activeThread.chatFamily.id,
            thinkingEnabled: settings.thinkingEnabled,
          ),
        );
  }

  Future<void> stopGeneration() async {
    await _service.stopGeneration();
  }

  void _onChatEvent(ChatEvent event) {
    if (event.channel != ChatChannel.local) return;
    if (event.threadId != state.activeThread?.id) return;
    switch (event) {
      case UserMessageSubmitted():
        state = state.copyWith(status: const AssistantGenerating());
      case AssistantStarted():
        _inFlightAssistantMessage = AssistantMessage(
          id: event.messageId,
          role: AssistantRole.assistant,
          text: '',
          createdAt: DateTime.now(),
          isStreaming: true,
        );
        _emitMessages();
      case AssistantToken():
        final current = _inFlightAssistantMessage;
        if (current == null || current.id != event.messageId) return;
        _inFlightAssistantMessage = current.append(event.token);
        _emitMessages();
      case AssistantThinkingToken():
        final current = _inFlightAssistantMessage;
        if (current == null || current.id != event.messageId) return;
        _inFlightAssistantMessage = current.appendThinking(event.token);
        _emitMessages();
      case AssistantCompleted():
        _inFlightAssistantMessage = event.message;
        _emitMessages();
      case AssistantFailed():
        _inFlightAssistantMessage = null;
        state = state.copyWith(
          status: AssistantError(event.error),
          lastError: event.error,
        );
        _emitMessages();
    }
  }

  void _onDbMessages(String threadId, List<AssistantMessage> messages) {
    if (state.activeThread?.id != threadId) return;
    _persistedMessages = messages;
    final inflight = _inFlightAssistantMessage;
    if (inflight != null && messages.any((m) => m.id == inflight.id)) {
      _inFlightAssistantMessage = null;
    }
    _emitMessages();
  }

  void _emitMessages() {
    final inflight = _inFlightAssistantMessage;
    final merged = inflight == null
        ? _persistedMessages
        : [..._persistedMessages, inflight];
    state = state.copyWith(messages: merged);
  }

  void _onWorkerEvent(AssistantEvent event) {
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
      case TokenEvent() || ThinkingTokenEvent() || DoneEvent():
        break;
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
      case EmbeddingEvent() ||
            IndexingProgressEvent() ||
            IndexingDoneEvent():
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
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantUiState>(
      AssistantController.new,
    );
