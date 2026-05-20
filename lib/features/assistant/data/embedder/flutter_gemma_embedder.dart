import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:minicrm/features/assistant/data/embedder/embedder.dart';

class FlutterGemmaEmbedder implements Embedder {
  FlutterGemmaEmbedder._({
    required this._model,
    required this.descriptor,
    required this.embeddingDim,
    required this.sequenceLength,
    required this.backendName,
  });

  static const int _summaryEvery = 25;

  static Future<FlutterGemmaEmbedder> install({
    required String modelUrl,
    required String tokenizerUrl,
    required String descriptor,
    required int sequenceLength,
    String? hfToken,
    PreferredBackend? preferredBackend,
    void Function(int progress)? onModelProgress,
    void Function(int progress)? onTokenizerProgress,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[FlutterGemmaEmbedder] installing $descriptor');

    await FlutterGemma.installEmbedder()
        .modelFromNetwork(modelUrl, token: hfToken)
        .tokenizerFromNetwork(tokenizerUrl, token: hfToken)
        .withModelProgress((p) => onModelProgress?.call(p))
        .withTokenizerProgress((p) => onTokenizerProgress?.call(p))
        .install();

    debugPrint(
      '[FlutterGemmaEmbedder] install complete in ${sw.elapsedMilliseconds}ms',
    );

    final model = await FlutterGemma.getActiveEmbedder(
      preferredBackend: preferredBackend,
    );

    final dim = await model.getDimension();
    debugPrint(
      '[FlutterGemmaEmbedder] embedder ready dim=$dim backend='
      '${preferredBackend?.name ?? 'default'} total=${sw.elapsedMilliseconds}ms',
    );

    return FlutterGemmaEmbedder._(
      model: model,
      descriptor: descriptor,
      embeddingDim: dim,
      sequenceLength: sequenceLength,
      backendName: preferredBackend?.name ?? 'cpu',
    );
  }

  /// Register an already-downloaded model + tokenizer pair with the
  /// flutter_gemma model manager and create an active embedder. Used when
  /// the files came from the legacy tflite downloader (i.e. they live in
  /// our own `models/` directory) and flutter_gemma has never seen them.
  ///
  /// Idempotent: calling this with the same files just sets the active
  /// model and returns a fresh `EmbeddingModel`.
  static Future<FlutterGemmaEmbedder> loadFromFile({
    required String modelPath,
    required String tokenizerPath,
    required String descriptor,
    required int sequenceLength,
    PreferredBackend? preferredBackend,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint(
      '[FlutterGemmaEmbedder] loadFromFile descriptor=$descriptor '
      'model=$modelPath tokenizer=$tokenizerPath',
    );

    await FlutterGemma.installEmbedder()
        .modelFromFile(modelPath)
        .tokenizerFromFile(tokenizerPath)
        .install();

    final model = await FlutterGemma.getActiveEmbedder(
      preferredBackend: preferredBackend,
    );
    final dim = await model.getDimension();
    debugPrint(
      '[FlutterGemmaEmbedder] loadFromFile ready dim=$dim backend='
      '${preferredBackend?.name ?? 'default'} total=${sw.elapsedMilliseconds}ms',
    );

    return FlutterGemmaEmbedder._(
      model: model,
      descriptor: descriptor,
      embeddingDim: dim,
      sequenceLength: sequenceLength,
      backendName: preferredBackend?.name ?? 'cpu',
    );
  }

  final EmbeddingModel _model;
  final String descriptor;

  @override
  final int embeddingDim;

  @override
  final int sequenceLength;

  @override
  final String backendName;

  @override
  EmbedderRuntime get runtime => EmbedderRuntime.flutterGemma;

  @override
  String get modelPath => descriptor;

  @override
  String get tokenizerPath => descriptor;

  @override
  bool get warmupFailed => false;

  bool _disposed = false;

  int _statsCount = 0;
  int _statsTotalMs = 0;
  int _statsMinMs = 1 << 30;
  int _statsMaxMs = 0;
  final List<int> _recent = <int>[];

  @override
  EmbedderStats get stats {
    final ms = List<int>.from(_recent)..sort();
    int pick(double frac) {
      if (ms.isEmpty) return 0;
      final idx = (ms.length * frac).clamp(0, ms.length - 1).floor();
      return ms[idx];
    }

    return EmbedderStats(
      count: _statsCount,
      totalMs: _statsTotalMs,
      tokenizeMs: 0,
      invokeMs: _statsTotalMs,
      postMs: 0,
      minMs: _statsCount == 0 ? 0 : _statsMinMs,
      maxMs: _statsMaxMs,
      p50InvokeMs: pick(0.5),
      p95InvokeMs: pick(0.95),
    );
  }

  @override
  Future<Float32List> embed(String text, {required bool isQuery}) async {
    if (_disposed) {
      throw StateError('FlutterGemmaEmbedder used after dispose');
    }
    final sw = Stopwatch()..start();
    final vec = await _model.generateEmbedding(
      text,
      taskType: isQuery ? TaskType.retrievalQuery : TaskType.retrievalDocument,
    );
    final ms = sw.elapsedMilliseconds;
    _trackStats(ms);

    final out = Float32List(vec.length);
    for (var i = 0; i < vec.length; i++) {
      out[i] = vec[i];
    }
    if (ms > 200) {
      debugPrint(
        '[FlutterGemmaEmbedder] slow embed total=${ms}ms len=${text.length}',
      );
    }
    if (_statsCount % _summaryEvery == 0) {
      logStatsSummary();
    }
    return out;
  }

  void _trackStats(int ms) {
    _statsCount++;
    _statsTotalMs += ms;
    if (ms < _statsMinMs) _statsMinMs = ms;
    if (ms > _statsMaxMs) _statsMaxMs = ms;
    _recent.add(ms);
    if (_recent.length > 64) {
      _recent.removeAt(0);
    }
  }

  @override
  void resetStats() {
    _statsCount = 0;
    _statsTotalMs = 0;
    _statsMinMs = 1 << 30;
    _statsMaxMs = 0;
    _recent.clear();
  }

  @override
  void logStatsSummary() {
    final s = stats;
    if (s.count == 0) return;
    debugPrint(
      '[FlutterGemmaEmbedder] stats count=${s.count} '
      'avg=${s.avgMs.toStringAsFixed(1)}ms '
      'min=${s.minMs}ms max=${s.maxMs}ms '
      'p50=${s.p50InvokeMs}ms p95=${s.p95InvokeMs}ms',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_statsCount > 0) {
      logStatsSummary();
    }
    unawaited(
      _model.close().catchError((Object e) {
        debugPrint('[FlutterGemmaEmbedder] dispose error: $e');
      }),
    );
  }
}
