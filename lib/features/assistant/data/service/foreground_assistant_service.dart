import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/data/task/assistant_task_handler.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ForegroundAssistantService implements AssistantService {
  ForegroundAssistantService({Uuid? uuid}) : _uuid = uuid ?? const Uuid() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  static const int _serviceId = 17317;

  final Uuid _uuid;
  final StreamController<AssistantEvent> _eventsController =
      StreamController<AssistantEvent>.broadcast();
  final Map<String, _PendingGeneration> _pending = {};
  final Map<String, Completer<List<double>>> _pendingEmbeddings = {};
  bool _initialized = false;
  bool _workerInitSent = false;
  bool _serviceKnownRunning = false;
  String? _cachedModelsDir;
  String? _cachedCacheDir;

  @override
  Stream<AssistantEvent> get events => _eventsController.stream;

  @override
  bool get isRunning => _initialized;

  void _onTaskData(Object data) {
    final event = AssistantEvent.tryParse(data);
    if (event == null) return;
    _eventsController.add(event);

    if (event is TokenEvent) {
      _pending[event.requestId]?.buffer.write(event.token);
    } else if (event is DoneEvent) {
      final pending = _pending.remove(event.requestId);
      if (pending != null && !pending.completer.isCompleted) {
        final text = event.text.isNotEmpty
            ? event.text
            : pending.buffer.toString();
        pending.completer.complete(text);
      }
    } else if (event is EmbeddingEvent) {
      final completer = _pendingEmbeddings.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        if (event.error != null) {
          completer.completeError(StateError(event.error!));
        } else {
          completer.complete(event.vector);
        }
      }
    } else if (event is StatusEvent && event.phase == AssistantPhase.error) {
      for (final pending in _pending.values) {
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            StateError(event.detail ?? 'Assistant error'),
          );
        }
      }
      _pending.clear();
    }
  }

  @override
  Future<bool> requestPermissions() async {
    debugPrint('[assistant] requestPermissions: checking notifications');
    final notification =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notification != NotificationPermission.granted) {
      debugPrint('[assistant] requestPermissions: requesting notifications');
      final result = await FlutterForegroundTask.requestNotificationPermission();
      if (result != NotificationPermission.granted) {
        debugPrint('[assistant] requestPermissions: notifications denied');
        return false;
      }
    }

    if (Platform.isAndroid) {
      debugPrint('[assistant] requestPermissions: battery opt');
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
    debugPrint('[assistant] requestPermissions: granted');
    return true;
  }

  @override
  Future<void> start() async {
    debugPrint('[assistant] start: initialized=$_initialized');
    if (!_initialized) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'minicrm_assistant',
          channelName: 'MiniCRM playground',
          channelDescription:
              'Keeps the on-device LiteRT-LM model warm in the foreground.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      _initialized = true;
    }

    debugPrint('[assistant] start: checking isRunningService');
    final running = await FlutterForegroundTask.isRunningService;
    debugPrint('[assistant] start: isRunning=$running');
    if (running) {
      debugPrint('[assistant] start: already running, syncing state');
      _serviceKnownRunning = true;
      await _sendInit(force: true);
      return;
    }
    _workerInitSent = false;
    _serviceKnownRunning = false;
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'Playground ready',
      notificationText: 'Tap to open the playground.',
      callback: assistantTaskCallback,
    );
    _serviceKnownRunning = true;
    debugPrint('[assistant] start: service started, sending init');
    await _sendInit(force: true);
  }

  Future<void> _sendInit({bool force = false}) async {
    if (_workerInitSent && !force) return;

    if (_cachedModelsDir == null || _cachedCacheDir == null) {
      debugPrint('[assistant] _sendInit: resolving docs dir');
      final Directory docs;
      try {
        docs = await getApplicationDocumentsDirectory().timeout(
          const Duration(seconds: 5),
        );
      } on TimeoutException catch (e, st) {
        debugPrint('[assistant] _sendInit: docs dir timeout: $e\n$st');
        _eventsController.add(
          const StatusEvent(
            phase: AssistantPhase.error,
            detail: 'path_provider unavailable — run `flutter clean && '
                'flutter pub get && flutter run` to rebuild the plugin '
                'registrant.',
          ),
        );
        return;
      } on Object catch (e, st) {
        debugPrint('[assistant] _sendInit: docs dir error: $e\n$st');
        _eventsController.add(
          StatusEvent(
            phase: AssistantPhase.error,
            detail: 'Failed to resolve docs dir: $e',
          ),
        );
        return;
      }

      final modelsDir = Directory('${docs.path}/models');
      final cacheDir = Directory('${docs.path}/litert_cache');
      if (!modelsDir.existsSync()) {
        modelsDir.createSync(recursive: true);
      }
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      _cachedModelsDir = modelsDir.path;
      _cachedCacheDir = cacheDir.path;
      debugPrint(
        '[assistant] _sendInit: models=$_cachedModelsDir cache=$_cachedCacheDir',
      );
    }

    FlutterForegroundTask.sendDataToTask(
      InitCommand(
        modelsDir: _cachedModelsDir!,
        cacheDir: _cachedCacheDir!,
      ).toMap(),
    );
    _workerInitSent = true;
  }

  @override
  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    _workerInitSent = false;
    _serviceKnownRunning = false;
  }

  @override
  Future<void> installModel({
    required String url,
    required String backend,
    String? token,
    bool loadAfterDownload = true,
    String chatFamily = 'general',
    int maxTokens = 4096,
  }) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      InstallModelCommand(
        url: url,
        backend: backend,
        token: token,
        loadAfterDownload: loadAfterDownload,
        chatFamily: chatFamily,
        maxTokens: maxTokens,
      ).toMap(),
    );
  }

  @override
  Future<String> generate({
    required String prompt,
    List<String> contextChunks = const [],
  }) async {
    await _ensureRunning();
    final requestId = _uuid.v4();
    final pending = _PendingGeneration();
    _pending[requestId] = pending;
    FlutterForegroundTask.sendDataToTask(
      GenerateCommand(
        requestId: requestId,
        prompt: prompt,
        contextChunks: contextChunks,
      ).toMap(),
    );
    return pending.completer.future;
  }

  @override
  Future<void> setSystemPrompt(String prompt) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    FlutterForegroundTask.sendDataToTask(
      SetSystemPromptCommand(prompt: prompt).toMap(),
    );
  }

  @override
  Future<void> stopGeneration() async {
    FlutterForegroundTask.sendDataToTask(
      const StopGenerationCommand().toMap(),
    );
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(pending.buffer.toString());
      }
    }
    _pending.clear();
  }

  @override
  Future<void> switchChat({
    required String threadId,
    required String systemInstruction,
    required String chatFamily,
    required List<Map<String, String>> history,
    bool thinking = true,
  }) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      SwitchChatCommand(
        threadId: threadId,
        systemInstruction: systemInstruction,
        chatFamily: chatFamily,
        history: history,
        thinking: thinking,
      ).toMap(),
    );
  }

  @override
  Future<void> listInstalledModels() async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(const ListModelsCommand().toMap());
  }

  @override
  Future<void> loadInstalledModel({
    required String path,
    required String backend,
    String chatFamily = 'general',
    int maxTokens = 4096,
  }) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      LoadModelCommand(
        path: path,
        backend: backend,
        chatFamily: chatFamily,
        maxTokens: maxTokens,
      ).toMap(),
    );
  }

  @override
  Future<void> unloadModel() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    FlutterForegroundTask.sendDataToTask(const UnloadModelCommand().toMap());
  }

  @override
  Future<void> deleteInstalledModel({required String path}) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      DeleteModelCommand(path: path).toMap(),
    );
  }

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
  }) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      InstallEmbedderCommand(
        modelUrl: modelUrl,
        tokenizerUrl: tokenizerUrl,
        token: token,
        loadAfterDownload: loadAfterDownload,
        runtime: runtime,
        backend: backend,
        sequenceLength: sequenceLength,
        presetId: presetId,
      ).toMap(),
    );
  }

  @override
  Future<void> loadEmbedder({
    required String modelPath,
    required String tokenizerPath,
    String backend = 'cpu',
    String runtime = 'tflite',
    int? sequenceLength,
    String? presetId,
  }) async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      LoadEmbedderCommand(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        backend: backend,
        runtime: runtime,
        sequenceLength: sequenceLength,
        presetId: presetId,
      ).toMap(),
    );
  }

  @override
  Future<void> unloadEmbedder() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    FlutterForegroundTask.sendDataToTask(
      const UnloadEmbedderCommand().toMap(),
    );
  }

  @override
  Future<List<double>> embed({
    required String text,
    bool isQuery = false,
  }) async {
    await _ensureRunning();
    final requestId = _uuid.v4();
    final completer = Completer<List<double>>();
    _pendingEmbeddings[requestId] = completer;
    FlutterForegroundTask.sendDataToTask(
      EmbedCommand(
        requestId: requestId,
        text: text,
        isQuery: isQuery,
      ).toMap(),
    );
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pendingEmbeddings.remove(requestId);
        throw TimeoutException('Embedding request timed out');
      },
    );
  }

  @override
  Future<void> enqueueEmbeddings() async {
    await _ensureRunning();
    FlutterForegroundTask.sendDataToTask(
      const EnqueueEmbeddingsCommand().toMap(),
    );
  }

  Future<void> _ensureRunning() async {
    if (_serviceKnownRunning && _workerInitSent) return;
    if (await FlutterForegroundTask.isRunningService) {
      _serviceKnownRunning = true;
      await _sendInit();
      return;
    }
    _workerInitSent = false;
    _serviceKnownRunning = false;
    await start();
  }

  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await _eventsController.close();
  }
}

class _PendingGeneration {
  _PendingGeneration();

  final Completer<String> completer = Completer<String>();
  final StringBuffer buffer = StringBuffer();
}
