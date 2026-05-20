import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/core/storage/object_box_store.dart';
import 'package:minicrm/features/context/data/repositories/document_chunk_repository.dart';
import 'package:minicrm/features/context/data/services/pdf_text_extractor.dart';
import 'package:minicrm/features/context/domain/services/text_chunker.dart';

final documentChunkRepositoryProvider =
    FutureProvider<DocumentChunkRepository>((ref) async {
  final store = await ref.watch(objectBoxStoreProvider.future);
  return DocumentChunkRepository(store.store);
});

final textChunkerProvider = Provider<TextChunker>(
  (ref) => const TextChunker(),
);

final pdfTextExtractorProvider = Provider<PdfTextExtractorService>(
  (ref) => const PdfTextExtractorService(),
);
