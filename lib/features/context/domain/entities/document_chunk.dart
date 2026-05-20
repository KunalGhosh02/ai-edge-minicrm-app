import 'package:objectbox/objectbox.dart';

@Entity()
class DocumentChunk {
  DocumentChunk({
    required this.documentTitle,
    required this.text,
    required this.chunkIndex,
    required this.createdAtMs,
    this.id = 0,
    this.embedding,
  });

  @Id()
  int id;

  @Index()
  String documentTitle;

  String text;

  int chunkIndex;

  int createdAtMs;

  /// L2-normalised sentence embedding produced by the on-device
  /// embedder (e.g. EmbeddingGemma 300M, 768 dims).
  /// HNSW index uses cosine distance — for unit-length vectors this
  /// matches dot-product similarity.
  @HnswIndex(
    dimensions: 768,
    distanceType: VectorDistanceType.cosine,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;
}
