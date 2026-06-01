import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/bus/chat_event_bus.dart';
import 'package:minicrm/features/assistant/data/service/foreground_assistant_service.dart';
import 'package:minicrm/features/assistant/data/subscribers/llm_driver_subscriber.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';
import 'package:minicrm/features/assistant/domain/repositories/rag_retriever.dart';
import 'package:minicrm/features/context/presentation/controllers/context_providers.dart';
import 'package:minicrm/features/settings/presentation/controllers/settings_controller.dart';

final assistantServiceProvider = Provider<AssistantService>((ref) {
  final service = ForegroundAssistantService();
  ref.onDispose(service.dispose);
  return service;
});

final ragRetrieverProvider = Provider<RagRetriever>(
  (ref) => (prompt) => _retrieveFromDocumentChunks(ref, prompt),
);

Future<List<String>> _retrieveFromDocumentChunks(
  Ref ref,
  String prompt,
) async {
  try {
    final settings = await ref.read(settingsControllerProvider.future);
    if (!settings.ragEnabled) return const [];
    final repo = await ref.read(documentChunkRepositoryProvider.future);
    final service = ref.read(assistantServiceProvider);
    if (repo.countWithEmbeddings() > 0) {
      try {
        final vec = await service.embed(text: prompt, isQuery: true);
        if (vec.isNotEmpty) {
          final hits = repo.vectorSearch(vec, limit: 3);
          if (hits.isNotEmpty) {
            return [for (final h in hits) h.chunk.text];
          }
        }
      } on Object catch (e) {
        debugPrint('[rag] vector retrieval failed, lexical fallback: $e');
      }
    }
    final hits = repo.searchByKeywords(prompt, limit: 3);
    return [for (final c in hits) c.text];
  } on Object catch (e) {
    debugPrint('[rag] retrieve failed: $e');
    return const [];
  }
}

final llmDriverSubscriberProvider = Provider<LlmDriverSubscriber>((ref) {
  final sub = LlmDriverSubscriber(
    ref.watch(chatEventBusProvider),
    ref.watch(assistantServiceProvider),
    ref.watch(ragRetrieverProvider),
  )..start();
  ref.onDispose(sub.dispose);
  return sub;
});
