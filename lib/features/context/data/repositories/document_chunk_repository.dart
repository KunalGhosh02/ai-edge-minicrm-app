import 'package:minicrm/features/context/domain/entities/document_chunk.dart';
import 'package:minicrm/objectbox.g.dart';

/// Result of a similarity search, with the underlying chunk and its
/// distance score (lower = more similar for cosine distance).
class ChunkHit {
  const ChunkHit({required this.chunk, required this.score});

  final DocumentChunk chunk;
  final double score;
}

class DocumentChunkRepository {
  DocumentChunkRepository(this._store);

  final Store _store;

  Box<DocumentChunk> get _box => _store.box<DocumentChunk>();

  List<DocumentChunk> all() {
    final query = _box.query().order(DocumentChunk_.createdAtMs).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Map<String, List<DocumentChunk>> groupedByDocument() {
    final out = <String, List<DocumentChunk>>{};
    for (final chunk in all()) {
      out.putIfAbsent(chunk.documentTitle, () => []).add(chunk);
    }
    return out;
  }

  int countAll() => _box.count();

  int countWithEmbeddings() {
    final query = _box
        .query(DocumentChunk_.embedding.notNull())
        .build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  int countUnembedded() {
    final query = _box
        .query(DocumentChunk_.embedding.isNull())
        .build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  /// Returns up to [limit] chunks that have no embedding yet, ordered by
  /// creation time so older chunks get processed first.
  List<DocumentChunk> findUnembedded({int limit = 16}) {
    final query = _box
        .query(DocumentChunk_.embedding.isNull())
        .order(DocumentChunk_.createdAtMs)
        .build()
      ..limit = limit;
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  int putMany(List<DocumentChunk> chunks) {
    return _box.putMany(chunks).length;
  }

  int put(DocumentChunk chunk) => _box.put(chunk);

  bool removeDocument(String title) {
    final query = _box
        .query(DocumentChunk_.documentTitle.equals(title))
        .build();
    try {
      final ids = query.findIds();
      final removed = _box.removeMany(ids);
      return removed > 0;
    } finally {
      query.close();
    }
  }

  void removeAll() {
    _box.removeAll();
  }

  /// Approximate nearest-neighbour search backed by the HNSW index on
  /// [DocumentChunk.embedding].
  ///
  /// [queryVector] must be the same dimensionality as the index (see the
  /// annotation on [DocumentChunk.embedding]). For best quality, pass an
  /// L2-normalised vector matching the indexed vectors.
  ///
  /// [maxResultCount] doubles as the HNSW `ef` parameter; we then
  /// truncate to [limit] for the caller.
  List<ChunkHit> vectorSearch(
    List<double> queryVector, {
    int limit = 3,
    int maxResultCount = 32,
  }) {
    if (queryVector.isEmpty) return const [];
    final query = _box
        .query(
          DocumentChunk_.embedding.nearestNeighborsF32(
            queryVector,
            maxResultCount,
          ),
        )
        .build()
      ..limit = limit;
    try {
      final results = query.findWithScores();
      return [
        for (final r in results) ChunkHit(chunk: r.object, score: r.score),
      ];
    } finally {
      query.close();
    }
  }

  /// Naive lexical fallback used when no embedder is loaded yet.
  List<DocumentChunk> searchByKeywords(String query, {int limit = 3}) {
    final tokens = query
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'))
        .where((t) => t.length > 2)
        .toSet();
    if (tokens.isEmpty) return const [];
    final chunks = all();
    final scored = <(DocumentChunk, int)>[];
    for (final c in chunks) {
      final text = c.text.toLowerCase();
      var hits = 0;
      for (final t in tokens) {
        if (text.contains(t)) hits++;
      }
      if (hits > 0) scored.add((c, hits));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored.take(limit)) s.$1];
  }
}
