import 'package:minicrm/features/context/domain/entities/document_chunk.dart';

/// Splits raw text into overlapping, roughly word-bounded chunks.
///
/// The default `200 token / 20 token overlap` strategy matches the project
/// brief (§5.2). Tokens here are approximated by whitespace-separated words
/// — good enough for paragraph-level retrieval without pulling in a real
/// tokenizer.
class TextChunker {
  const TextChunker({
    this.chunkSize = 200,
    this.overlap = 20,
  });

  final int chunkSize;
  final int overlap;

  List<DocumentChunk> chunk({
    required String title,
    required String text,
  }) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final step = chunkSize - overlap;
    final chunks = <DocumentChunk>[];

    var i = 0;
    var index = 0;
    while (i < words.length) {
      final end = (i + chunkSize).clamp(0, words.length);
      final slice = words.sublist(i, end).join(' ');
      chunks.add(
        DocumentChunk(
          documentTitle: title,
          text: slice,
          chunkIndex: index,
          createdAtMs: now,
        ),
      );
      index++;
      if (end == words.length) break;
      i += step;
    }
    return chunks;
  }
}
