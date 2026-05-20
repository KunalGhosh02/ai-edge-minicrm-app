import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:minicrm/features/assistant/data/embedder/embedder.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

export 'package:minicrm/features/assistant/data/embedder/embedder_stats.dart';

enum EmbedderBackend { cpu, gpu }

extension EmbedderBackendX on EmbedderBackend {
  String get name => switch (this) {
        EmbedderBackend.cpu => 'cpu',
        EmbedderBackend.gpu => 'gpu',
      };

  static EmbedderBackend parse(String? value) => switch (value) {
        'gpu' => EmbedderBackend.gpu,
        _ => EmbedderBackend.cpu,
      };
}

/// On-device embedder backed by Google's EmbeddingGemma 300M
/// (litert-community TFLite build) + the official SentencePiece tokenizer.
///
/// Pipeline (matches the reference Android implementation):
/// 1. Prepend a task-specific prompt prefix to the input text.
/// 2. Tokenize with SentencePiece (BOS/EOS added by the gemma config).
/// 3. Pad / truncate to the model's sequence length and build the
///    attention mask.
/// 4. Run the TFLite interpreter on `[input_ids, attention_mask]`.
/// 5. Mean-pool the per-token hidden states using the attention mask.
/// 6. L2-normalise so cosine similarity reduces to a dot product.
class EmbeddingGemmaEmbedder implements Embedder {
  EmbeddingGemmaEmbedder._({
    required Interpreter interpreter,
    required SentencePieceTokenizer tokenizer,
    required this.modelPath,
    required this.tokenizerPath,
    required this.backend,
    required this.sequenceLength,
    required this.embeddingDim,
    required this.bosTokenId,
    required this.eosTokenId,
    required this.padTokenId,
    required this.inputIdsIndex,
    required this.attentionMaskIndex,
    required this.outputIsTokenLevel,
    Delegate? ownedDelegate,
  })  : _interpreter = interpreter,
        _tokenizer = tokenizer,
        _ownedDelegate = ownedDelegate;

  // The private constructor takes named parameters with their public types
  // (Interpreter / SentencePieceTokenizer) so the static `load` factory can
  // build instances in one expression without polluting call sites with
  // leading-underscore parameter names.
  // ignore_for_file: prefer_initializing_formals

  static const String _queryPrompt = 'task: search result | query: ';
  static const String _documentPrompt = 'title: none | text: ';

  final Interpreter _interpreter;
  final SentencePieceTokenizer _tokenizer;
  final Delegate? _ownedDelegate;

  @override
  final String modelPath;
  @override
  final String tokenizerPath;
  final EmbedderBackend backend;
  @override
  final int sequenceLength;
  @override
  final int embeddingDim;

  @override
  EmbedderRuntime get runtime => EmbedderRuntime.tflite;

  @override
  String get backendName => backend.name;
  final int bosTokenId;
  final int eosTokenId;
  final int padTokenId;
  final int inputIdsIndex;
  final int attentionMaskIndex;

  /// True when the model returns per-token hidden states `[1, seq, dim]`
  /// and we must mean-pool them ourselves. False when the model already
  /// returns a pooled `[1, dim]` sentence embedding.
  final bool outputIsTokenLevel;

  bool _disposed = false;
  _InvokeIsolate? _invokeIsolate;

  Int32List? _idsBuffer;
  Int32List? _maskBuffer;
  Uint8List? _idsBytesView;
  Uint8List? _maskBytesView;

  int _statsCount = 0;
  int _statsTotalMs = 0;
  int _statsTokenizeMs = 0;
  int _statsInvokeMs = 0;
  int _statsPostMs = 0;
  int _statsMinMs = 1 << 30;
  int _statsMaxMs = 0;
  final List<int> _statsRecentInvoke = <int>[];
  static const int _summaryEvery = 25;

  /// Snapshot of rolling embed statistics since the last reset.
  @override
  EmbedderStats get stats => EmbedderStats(
        count: _statsCount,
        totalMs: _statsTotalMs,
        tokenizeMs: _statsTokenizeMs,
        invokeMs: _statsInvokeMs,
        postMs: _statsPostMs,
        minMs: _statsCount == 0 ? 0 : _statsMinMs,
        maxMs: _statsMaxMs,
        p50InvokeMs: _percentile(_statsRecentInvoke, 0.5),
        p95InvokeMs: _percentile(_statsRecentInvoke, 0.95),
      );

  @override
  void resetStats() => _statsReset();

  void _statsReset() {
    _statsCount = 0;
    _statsTotalMs = 0;
    _statsTokenizeMs = 0;
    _statsInvokeMs = 0;
    _statsPostMs = 0;
    _statsMinMs = 1 << 30;
    _statsMaxMs = 0;
    _statsRecentInvoke.clear();
  }

  static int _percentile(List<int> samples, double p) {
    if (samples.isEmpty) return 0;
    final sorted = [...samples]..sort();
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  /// Load the embedder from local files. Both files must already exist
  /// on disk (download is handled separately by the worker).
  ///
  /// [backend] selects the accelerator:
  /// - [EmbedderBackend.cpu]: XNNPack delegate (default, works everywhere).
  /// - [EmbedderBackend.gpu]: Android GPU via OpenCL/OpenGL. Falls back to
  ///   CPU automatically if the GPU delegate fails to initialise (e.g. on
  ///   emulators without `libOpenCL.so`).
  static Future<EmbeddingGemmaEmbedder> load({
    required String modelPath,
    required String tokenizerPath,
    EmbedderBackend backend = EmbedderBackend.cpu,
    int numThreads = 4,
    bool warmup = true,
    bool useInvokeIsolate = false,
  }) async {
    final swAll = Stopwatch()..start();
    debugPrint(
      '[tflite][load] start backend=${backend.name} threads=$numThreads '
      'useInvokeIsolate=$useInvokeIsolate model=$modelPath',
    );
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw StateError('Embedder model file not found: $modelPath');
    }
    final tokenizerFile = File(tokenizerPath);
    if (!tokenizerFile.existsSync()) {
      throw StateError('Tokenizer file not found: $tokenizerPath');
    }
    final modelBytes = modelFile.lengthSync();
    final tokenizerBytes = tokenizerFile.lengthSync();
    debugPrint(
      '[tflite][load] files ok: '
      'model=${(modelBytes / 1024 / 1024).toStringAsFixed(1)}MB '
      'tokenizer=${(tokenizerBytes / 1024).toStringAsFixed(0)}KB',
    );

    final swStep = Stopwatch()..start();
    final tokenizer = SentencePieceTokenizer.fromModelFileSync(
      tokenizerPath,
      config: SentencePieceConfig.gemma,
    );
    final tokenizerMs = swStep.elapsedMilliseconds;
    debugPrint('[tflite][load] tokenizer loaded in ${tokenizerMs}ms');

    var effectiveBackend = backend;
    Delegate? ownedDelegate;
    final options = InterpreterOptions();
    swStep.reset();
    if (backend == EmbedderBackend.gpu && Platform.isAndroid) {
      try {
        final gpu = GpuDelegateV2(
          options: GpuDelegateOptionsV2(
            isPrecisionLossAllowed: true,
          ),
        );
        options.addDelegate(gpu);
        ownedDelegate = gpu;
        debugPrint(
          '[tflite][load] GPU delegate created in '
          '${swStep.elapsedMilliseconds}ms',
        );
      } on Object catch (e) {
        debugPrint('[tflite][load] GPU delegate failed: $e — falling back');
        effectiveBackend = EmbedderBackend.cpu;
        options.threads = numThreads;
      }
    } else {
      effectiveBackend = EmbedderBackend.cpu;
      options.threads = numThreads;
    }

    swStep.reset();
    Interpreter interpreter;
    try {
      interpreter = Interpreter.fromFile(modelFile, options: options);
    } on Object catch (e) {
      debugPrint('[tflite][load] interpreter.fromFile failed: $e');
      ownedDelegate?.delete();
      if (effectiveBackend != EmbedderBackend.cpu) {
        effectiveBackend = EmbedderBackend.cpu;
        final cpuOptions = InterpreterOptions()..threads = numThreads;
        debugPrint('[tflite][load] retrying with CPU only');
        interpreter = Interpreter.fromFile(modelFile, options: cpuOptions);
        ownedDelegate = null;
      } else {
        rethrow;
      }
    }
    final interpreterMs = swStep.elapsedMilliseconds;
    debugPrint(
      '[tflite][load] interpreter created in ${interpreterMs}ms '
      '(backend=${effectiveBackend.name})',
    );

    final inputTensors = interpreter.getInputTensors();
    if (inputTensors.isEmpty) {
      interpreter.close();
      throw StateError('Embedder model has no input tensors');
    }

    var inputIdsIndex = 0;
    var attentionMaskIndex = inputTensors.length > 1 ? 1 : 0;
    for (var i = 0; i < inputTensors.length; i++) {
      final name = inputTensors[i].name.toLowerCase();
      if (name.contains('mask')) {
        attentionMaskIndex = i;
      } else if (name.contains('input') || name.contains('ids')) {
        inputIdsIndex = i;
      }
    }
    final idsShape = inputTensors[inputIdsIndex].shape;
    final seqLen = idsShape.length >= 2 ? idsShape.last : 512;

    final outputTensors = interpreter.getOutputTensors();
    final outputTensor = outputTensors.first;
    final outShape = outputTensor.shape;
    final isTokenLevel = outShape.length >= 3;
    final dim = outShape.last;

    debugPrint(
      '[tflite][load] inputs=${inputTensors.length} '
      'outputs=${outputTensors.length} seqLen=$seqLen dim=$dim '
      'tokenLevelOutput=$isTokenLevel',
    );
    for (var i = 0; i < inputTensors.length; i++) {
      final t = inputTensors[i];
      debugPrint(
        '[tflite][load]   input[$i] name=${t.name} shape=${t.shape} '
        'bytes=${t.numBytes()}',
      );
    }
    for (var i = 0; i < outputTensors.length; i++) {
      final t = outputTensors[i];
      debugPrint(
        '[tflite][load]   output[$i] name=${t.name} shape=${t.shape} '
        'bytes=${t.numBytes()}',
      );
    }

    final vocab = tokenizer.vocab;
    final embedder = EmbeddingGemmaEmbedder._(
      interpreter: interpreter,
      tokenizer: tokenizer,
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      backend: effectiveBackend,
      sequenceLength: seqLen,
      embeddingDim: dim,
      bosTokenId: vocab.bosId,
      eosTokenId: vocab.eosId,
      padTokenId: vocab.padId >= 0 ? vocab.padId : 0,
      inputIdsIndex: inputIdsIndex,
      attentionMaskIndex: attentionMaskIndex,
      outputIsTokenLevel: isTokenLevel,
      ownedDelegate: ownedDelegate,
    );

    if (useInvokeIsolate) {
      swStep.reset();
      try {
        embedder._invokeIsolate =
            await _InvokeIsolate.start(interpreter.address);
        debugPrint(
          '[tflite][load] invoke isolate ready in '
          '${swStep.elapsedMilliseconds}ms',
        );
      } on Object catch (e) {
        debugPrint(
          '[tflite][load] invoke isolate failed: $e — '
          'falling back to inline invoke',
        );
      }
    }

    if (warmup) {
      swStep.reset();
      try {
        await embedder.embed('warmup', isQuery: false);
        debugPrint(
          '[tflite][load] warmup inference: ${swStep.elapsedMilliseconds}ms',
        );
        embedder._statsReset();
      } on Object catch (e) {
        embedder._warmupFailed = true;
        debugPrint('[tflite][load] warmup failed: $e');
      }
    }

    debugPrint(
      '[tflite][load] DONE in ${swAll.elapsedMilliseconds}ms '
      '(tokenizer=${tokenizerMs}ms interpreter=${interpreterMs}ms)',
    );
    return embedder;
  }

  @override
  bool get warmupFailed => _warmupFailed;
  bool _warmupFailed = false;

  @override
  Future<Float32List> embed(String text, {required bool isQuery}) async {
    if (_disposed) {
      throw StateError('Embedder has been disposed');
    }
    final sw = Stopwatch()..start();
    final prompt = isQuery ? _queryPrompt : _documentPrompt;
    final encoding = _tokenizer.encode(prompt + text);
    final rawIds = encoding.ids;
    final tokenizeMs = sw.elapsedMilliseconds;

    final ids = _idsBuffer ??= Int32List(sequenceLength);
    final mask = _maskBuffer ??= Int32List(sequenceLength);
    final idsBytes = _idsBytesView ??= ids.buffer.asUint8List();
    final maskBytes = _maskBytesView ??= mask.buffer.asUint8List();

    final take = math.min(rawIds.length, sequenceLength);
    for (var i = 0; i < take; i++) {
      ids[i] = rawIds[i];
      mask[i] = 1;
    }
    for (var i = take; i < sequenceLength; i++) {
      ids[i] = padTokenId;
      mask[i] = 0;
    }

    _interpreter.getInputTensor(inputIdsIndex).data = idsBytes;
    _interpreter.getInputTensor(attentionMaskIndex).data = maskBytes;
    final invokeStart = sw.elapsedMilliseconds;
    final invokeIsolate = _invokeIsolate;
    if (invokeIsolate != null) {
      await invokeIsolate.invoke();
    } else {
      _interpreter.invoke();
    }
    final invokeMs = sw.elapsedMilliseconds - invokeStart;

    final outBytes = _interpreter.getOutputTensor(0).data;
    final outFloats = Float32List.view(
      outBytes.buffer,
      outBytes.offsetInBytes,
      outBytes.lengthInBytes ~/ 4,
    );

    final pooled = Float32List(embeddingDim);
    if (outputIsTokenLevel) {
      var validTokens = 0;
      for (var t = 0; t < take; t++) {
        if (mask[t] == 0) continue;
        validTokens++;
        final off = t * embeddingDim;
        for (var d = 0; d < embeddingDim; d++) {
          pooled[d] += outFloats[off + d];
        }
      }
      if (validTokens > 0) {
        final inv = 1.0 / validTokens;
        for (var d = 0; d < embeddingDim; d++) {
          pooled[d] *= inv;
        }
      }
    } else {
      for (var d = 0; d < embeddingDim; d++) {
        pooled[d] = outFloats[d];
      }
    }

    var norm = 0.0;
    for (var d = 0; d < embeddingDim; d++) {
      norm += pooled[d] * pooled[d];
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      final inv = 1.0 / norm;
      for (var d = 0; d < embeddingDim; d++) {
        pooled[d] *= inv;
      }
    }
    final totalMs = sw.elapsedMilliseconds;
    final postMs = totalMs - tokenizeMs - invokeMs;

    _statsCount++;
    _statsTotalMs += totalMs;
    _statsTokenizeMs += tokenizeMs;
    _statsInvokeMs += invokeMs;
    _statsPostMs += postMs < 0 ? 0 : postMs;
    if (totalMs < _statsMinMs) _statsMinMs = totalMs;
    if (totalMs > _statsMaxMs) _statsMaxMs = totalMs;
    _statsRecentInvoke.add(invokeMs);
    if (_statsRecentInvoke.length > 200) {
      _statsRecentInvoke.removeAt(0);
    }

    debugPrint(
      '[tflite][embed] #$_statsCount tokens=$take total=${totalMs}ms '
      '(tokenize=${tokenizeMs}ms invoke=${invokeMs}ms post=${postMs}ms)',
    );
    if (_statsCount % _summaryEvery == 0) {
      logStatsSummary();
    }
    return pooled;
  }

  /// Print a one-line summary of rolling embed stats.
  @override
  void logStatsSummary() {
    final s = stats;
    if (s.count == 0) return;
    debugPrint(
      '[tflite][stats] n=${s.count} '
      'avg=${s.avgMs.toStringAsFixed(1)}ms '
      'min=${s.minMs}ms max=${s.maxMs}ms '
      'avgTokenize=${s.avgTokenizeMs.toStringAsFixed(1)}ms '
      'avgInvoke=${s.avgInvokeMs.toStringAsFixed(1)}ms '
      'avgPost=${s.avgPostMs.toStringAsFixed(1)}ms '
      'p50Invoke=${s.p50InvokeMs}ms p95Invoke=${s.p95InvokeMs}ms',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_statsCount > 0) {
      logStatsSummary();
    }
    _invokeIsolate?.close();
    _invokeIsolate = null;
    _interpreter.close();
    _ownedDelegate?.delete();
  }
}

class _InvokeIsolateState {
  Completer<void>? pending;
}

class _InvokeIsolate {
  _InvokeIsolate._(
    this._isolate,
    this._sendPort,
    this._receivePort,
    this._sub,
    this._state,
  );

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final StreamSubscription<dynamic> _sub;
  final _InvokeIsolateState _state;
  bool _closed = false;

  static Future<_InvokeIsolate> start(int interpreterAddress) async {
    final replyPort = ReceivePort();
    final readyCompleter = Completer<SendPort>();
    final state = _InvokeIsolateState();

    // Subscription ownership is transferred to the returned _InvokeIsolate
    // and cancelled in its close() method.
    // ignore: cancel_subscriptions
    final sub = replyPort.listen((dynamic msg) {
      if (msg is SendPort) {
        if (!readyCompleter.isCompleted) readyCompleter.complete(msg);
        return;
      }
      if (msg == 'done') {
        final pending = state.pending;
        state.pending = null;
        pending?.complete();
        return;
      }
      if (msg is List && msg.length == 2 && msg[0] == 'error') {
        final pending = state.pending;
        state.pending = null;
        pending?.completeError(StateError('invoke isolate: ${msg[1]}'));
      }
    });

    final isolate = await Isolate.spawn<_IsolateInit>(
      _entry,
      _IsolateInit(replyPort.sendPort, interpreterAddress),
      debugName: 'tflite-invoke',
    );
    final sendPort = await readyCompleter.future;
    return _InvokeIsolate._(isolate, sendPort, replyPort, sub, state);
  }

  Future<void> invoke() {
    if (_closed) {
      return Future<void>.error(StateError('invoke isolate is closed'));
    }
    if (_state.pending != null) {
      return Future<void>.error(
        StateError('invoke isolate is busy with a previous invoke'),
      );
    }
    final completer = Completer<void>();
    _state.pending = completer;
    _sendPort.send('invoke');
    return completer.future;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _sendPort.send('close');
    } on Object {
      _state.pending = null;
    }
    unawaited(_sub.cancel());
    _receivePort.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static void _entry(_IsolateInit init) {
    final port = ReceivePort();
    init.replyPort.send(port.sendPort);
    final interpreter = Interpreter.fromAddress(init.interpreterAddress);
    port.listen((dynamic msg) {
      if (msg == 'invoke') {
        try {
          interpreter.invoke();
          init.replyPort.send('done');
        } on Object catch (e) {
          init.replyPort.send(<Object>['error', e.toString()]);
        }
      } else if (msg == 'close') {
        port.close();
      }
    });
  }
}

class _IsolateInit {
  _IsolateInit(this.replyPort, this.interpreterAddress);
  final SendPort replyPort;
  final int interpreterAddress;
}
