import 'dart:typed_data';

import 'package:minicrm/features/assistant/data/embedder/embedder_stats.dart';

export 'package:minicrm/features/assistant/data/embedder/embedder_stats.dart';

enum EmbedderRuntime { tflite, flutterGemma }

extension EmbedderRuntimeX on EmbedderRuntime {
  String get id => switch (this) {
        EmbedderRuntime.tflite => 'tflite',
        EmbedderRuntime.flutterGemma => 'flutter_gemma',
      };

  static EmbedderRuntime parse(String? value) => switch (value) {
        'flutter_gemma' => EmbedderRuntime.flutterGemma,
        _ => EmbedderRuntime.tflite,
      };
}

abstract interface class Embedder {
  EmbedderRuntime get runtime;
  int get embeddingDim;
  int get sequenceLength;
  String get backendName;

  String get modelPath;
  String get tokenizerPath;

  bool get warmupFailed;
  EmbedderStats get stats;

  Future<Float32List> embed(String text, {required bool isQuery});
  void resetStats();
  void logStatsSummary();
  void dispose();
}
