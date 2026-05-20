import 'package:equatable/equatable.dart';

enum ModelKind { generation, embedding }

/// Generation-model family. Drives the `<think>` / `<|channel>thought\n`
/// tag parser inside flutter_gemma so the worker can emit reasoning
/// content separately from the final answer.
enum ChatModelFamily {
  general,
  gemma4,
  deepSeek,
  qwen,
  qwen3,
}

extension ChatModelFamilyX on ChatModelFamily {
  String get id => switch (this) {
        ChatModelFamily.general => 'general',
        ChatModelFamily.gemma4 => 'gemma4',
        ChatModelFamily.deepSeek => 'deepSeek',
        ChatModelFamily.qwen => 'qwen',
        ChatModelFamily.qwen3 => 'qwen3',
      };

  bool get hasThoughts => switch (this) {
        ChatModelFamily.deepSeek => true,
        ChatModelFamily.qwen3 => true,
        ChatModelFamily.gemma4 => true,
        ChatModelFamily.qwen => false,
        ChatModelFamily.general => false,
      };

  static ChatModelFamily parse(String? value) => switch (value) {
        'gemma4' => ChatModelFamily.gemma4,
        'deepSeek' => ChatModelFamily.deepSeek,
        'qwen' => ChatModelFamily.qwen,
        'qwen3' => ChatModelFamily.qwen3,
        _ => ChatModelFamily.general,
      };
}

enum EmbedderRuntimeKind { tflite, flutterGemma }

extension EmbedderRuntimeKindX on EmbedderRuntimeKind {
  String get id => switch (this) {
        EmbedderRuntimeKind.tflite => 'tflite',
        EmbedderRuntimeKind.flutterGemma => 'flutter_gemma',
      };
}

class ModelPreset extends Equatable {
  const ModelPreset({
    required this.id,
    required this.name,
    required this.url,
    required this.sizeBytes,
    this.kind = ModelKind.generation,
    this.requiresAuth = false,
    this.description,
    this.tokenizerUrl,
    this.runtime = EmbedderRuntimeKind.tflite,
    this.sequenceLength,
    this.chatFamily = ChatModelFamily.general,
    this.maxTokens = 4096,
  });

  final String id;
  final String name;
  final String url;
  final int sizeBytes;
  final ModelKind kind;
  final bool requiresAuth;
  final String? description;

  /// For embedding presets: companion sentencepiece tokenizer that must be
  /// downloaded alongside the model file. Null for generation presets.
  final String? tokenizerUrl;

  /// For embedding presets: which inference runtime to use.
  /// Generation presets always run through flutter_gemma and ignore this.
  final EmbedderRuntimeKind runtime;

  /// For embedding presets: maximum input sequence length the model was
  /// exported with. Used for UI display and chunk truncation hints.
  final int? sequenceLength;

  /// For generation presets: model family. Drives chat formatting and the
  /// `<think>` / `<thought>` tag parser inside flutter_gemma.
  final ChatModelFamily chatFamily;

  /// For generation presets: KV-cache window (input + output tokens).
  /// Defaults to 4k — matches the q8 ekv4096 quants we ship.
  final int maxTokens;

  String get humanSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  List<Object?> get props => [
        id,
        name,
        url,
        sizeBytes,
        kind,
        requiresAuth,
        description,
        tokenizerUrl,
        runtime,
        sequenceLength,
        chatFamily,
        maxTokens,
      ];
}

abstract final class ModelPresets {
  static String fileNameOf(ModelPreset preset) =>
      Uri.parse(preset.url).pathSegments.last;

  static ModelPreset? matchByFileName(String fileName) {
    for (final p in all) {
      if (fileNameOf(p) == fileName) return p;
    }
    return null;
  }

  static ModelPreset? matchByUrl(String url) {
    for (final p in all) {
      if (p.url == url) return p;
    }
    return null;
  }

  static const ModelPreset qwen3Small = ModelPreset(
    id: 'qwen3_06b',
    name: 'Qwen 3 0.6B',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    sizeBytes: 614236160,
    chatFamily: ChatModelFamily.qwen3,
    description: 'Smallest general-purpose chat. Apache-2.0, no auth.',
  );

  static const ModelPreset qwen25 = ModelPreset(
    id: 'qwen25_15b',
    name: 'Qwen 2.5 1.5B Instruct',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    sizeBytes: 1597931520,
    chatFamily: ChatModelFamily.qwen,
    description:
        'Balanced quality / size. 4k context, q8. Apache-2.0, no auth.',
  );

  static const ModelPreset deepseekR1 = ModelPreset(
    id: 'deepseek_r1_15b',
    name: 'DeepSeek R1 Distill Qwen 1.5B',
    url:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
    sizeBytes: 1833451520,
    chatFamily: ChatModelFamily.deepSeek,
    description:
        'Reasoning / chain-of-thought. 4k context, q8. MIT, no auth.',
  );

  static const ModelPreset gemma4E2b = ModelPreset(
    id: 'gemma4_e2b',
    name: 'Gemma 4 E2B Instruct',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    chatFamily: ChatModelFamily.gemma4,
    description: 'Google flagship multimodal. Apache-2.0, ungated.',
  );

  static const ModelPreset gemma4E4b = ModelPreset(
    id: 'gemma4_e4b',
    name: 'Gemma 4 E4B Instruct',
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
    chatFamily: ChatModelFamily.gemma4,
    description: 'Highest quality, ~5 GB RAM at load. Apache-2.0.',
  );

  static const ModelPreset embeddingGemma300mSeq512 = ModelPreset(
    id: 'embeddinggemma_300m_seq512',
    name: 'EmbeddingGemma 300M (seq 512, tflite)',
    url:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq512_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    sizeBytes: 187117520,
    kind: ModelKind.embedding,
    requiresAuth: true,
    runtime: EmbedderRuntimeKind.tflite,
    sequenceLength: 512,
    description:
        'Legacy tflite_flutter path. 768-dim, 512-token sequence, '
        'mixed-precision .tflite (~178 MB) + SentencePiece tokenizer (~5 MB). '
        'Synchronous FFI: blocks the worker isolate per embed. '
        'Prefer the flutter_gemma variant below.',
  );

  static const ModelPreset embeddingGemma300mSeq2048 = ModelPreset(
    id: 'embeddinggemma_300m_seq2048',
    name: 'EmbeddingGemma 300M (seq 2048, tflite, advanced)',
    url:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq2048_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    sizeBytes: 195912440,
    kind: ModelKind.embedding,
    requiresAuth: true,
    runtime: EmbedderRuntimeKind.tflite,
    sequenceLength: 2048,
    description:
        'Long-context variant for whole-paragraph chunks. 768-dim, '
        '2048-token sequence, mixed-precision .tflite (~187 MB). '
        '4x more compute and memory per embed; can OOM on devices '
        'with <6 GB RAM. Prefer the seq-512 build unless you really '
        'need long chunks.',
  );

  static const ModelPreset embeddingGemma300mFlutterGemmaSeq256 = ModelPreset(
    id: 'embeddinggemma_300m_fg_seq256',
    name: 'EmbeddingGemma 300M (seq 256, flutter_gemma)',
    url:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    sizeBytes: 178257920,
    kind: ModelKind.embedding,
    requiresAuth: true,
    runtime: EmbedderRuntimeKind.flutterGemma,
    sequenceLength: 256,
    description:
        'Recommended default. 768-dim, 256-token sequence, runs through '
        'LiteRT FFI in the flutter_gemma plugin: non-blocking native '
        'inference, GPU delegate works, no synchronous Dart stalls. '
        'Requires a HuggingFace token and Gemma license acceptance.',
  );

  static const ModelPreset embeddingGemma300mFlutterGemmaSeq512 = ModelPreset(
    id: 'embeddinggemma_300m_fg_seq512',
    name: 'EmbeddingGemma 300M (seq 512, flutter_gemma)',
    url:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq512_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    sizeBytes: 187117520,
    kind: ModelKind.embedding,
    requiresAuth: true,
    runtime: EmbedderRuntimeKind.flutterGemma,
    sequenceLength: 512,
    description:
        'Longer-context variant for paragraph-sized chunks. 768-dim, '
        '512-token sequence, runs through LiteRT FFI in flutter_gemma. '
        'Slightly more compute than seq-256. Requires a HuggingFace '
        'token and Gemma license acceptance.',
  );

  static const List<ModelPreset> all = [
    qwen3Small,
    qwen25,
    deepseekR1,
    gemma4E2b,
    gemma4E4b,
    embeddingGemma300mFlutterGemmaSeq256,
    embeddingGemma300mFlutterGemmaSeq512,
    embeddingGemma300mSeq512,
    embeddingGemma300mSeq2048,
  ];

  static List<ModelPreset> get generationPresets =>
      all.where((p) => p.kind == ModelKind.generation).toList();

  static List<ModelPreset> get embeddingPresets =>
      all.where((p) => p.kind == ModelKind.embedding).toList();

  static ModelPreset get defaultPreset => qwen3Small;

  static ModelPreset get defaultEmbeddingPreset =>
      embeddingGemma300mFlutterGemmaSeq256;
}
