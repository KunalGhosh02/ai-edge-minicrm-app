import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/ipc/assistant_ipc.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_providers.dart';
import 'package:minicrm/features/context/data/repositories/document_chunk_repository.dart';
import 'package:minicrm/features/context/domain/entities/document_chunk.dart';
import 'package:minicrm/features/context/domain/services/text_chunker.dart';
import 'package:minicrm/features/context/presentation/controllers/context_providers.dart';

class ContextDocument extends Equatable {
  const ContextDocument({
    required this.title,
    required this.chunks,
  });

  final String title;
  final List<DocumentChunk> chunks;

  int get totalCharacters =>
      chunks.fold<int>(0, (sum, c) => sum + c.text.length);

  int get embeddedChunks =>
      chunks.where((c) => c.embedding != null && c.embedding!.isNotEmpty).length;

  @override
  List<Object?> get props => [title, chunks.length, totalCharacters];
}

enum IndexingPhase { idle, embedding, error }

class IndexingState extends Equatable {
  const IndexingState({
    this.phase = IndexingPhase.idle,
    this.processed = 0,
    this.total = 0,
    this.error,
  });

  final IndexingPhase phase;
  final int processed;
  final int total;
  final String? error;

  bool get isRunning => phase == IndexingPhase.embedding;
  double get progress => total == 0 ? 0 : processed / total;

  @override
  List<Object?> get props => [phase, processed, total, error];
}

class ContextState extends Equatable {
  const ContextState({
    required this.documents,
    required this.totalChunks,
    required this.embeddedChunks,
    required this.indexing,
  });

  const ContextState.empty()
      : documents = const [],
        totalChunks = 0,
        embeddedChunks = 0,
        indexing = const IndexingState();

  final List<ContextDocument> documents;
  final int totalChunks;
  final int embeddedChunks;
  final IndexingState indexing;

  ContextState copyWith({
    List<ContextDocument>? documents,
    int? totalChunks,
    int? embeddedChunks,
    IndexingState? indexing,
  }) =>
      ContextState(
        documents: documents ?? this.documents,
        totalChunks: totalChunks ?? this.totalChunks,
        embeddedChunks: embeddedChunks ?? this.embeddedChunks,
        indexing: indexing ?? this.indexing,
      );

  @override
  List<Object?> get props =>
      [documents, totalChunks, embeddedChunks, indexing];
}

class ContextController extends AsyncNotifier<ContextState> {
  DocumentChunkRepository? _repo;
  TextChunker? _chunker;
  AssistantService? _assistant;
  StreamSubscription<AssistantEvent>? _eventsSub;
  Timer? _refreshDebounce;

  @override
  Future<ContextState> build() async {
    _repo = await ref.watch(documentChunkRepositoryProvider.future);
    _chunker = ref.watch(textChunkerProvider);
    _assistant = ref.watch(assistantServiceProvider);

    unawaited(_eventsSub?.cancel());
    _eventsSub = _assistant!.events.listen(_onAssistantEvent);
    ref
      ..onDispose(() {
        unawaited(_eventsSub?.cancel());
        _refreshDebounce?.cancel();
      })
      ..listen<AssistantUiState>(assistantControllerProvider, (prev, next) {
        final wasLoaded = prev?.embedderLoaded ?? false;
        final isLoaded = next.embedderLoaded;
        if (!wasLoaded && isLoaded) {
          unawaited(_kickWorkerIfPending());
        }
      });

    if (ref.read(assistantControllerProvider).embedderLoaded) {
      unawaited(_kickWorkerIfPending());
    }

    return _read();
  }

  void _onAssistantEvent(AssistantEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case IndexingProgressEvent(:final processed, :final total):
        final cached = state.value ?? _read();
        state = AsyncData(
          cached.copyWith(
            indexing: IndexingState(
              phase: IndexingPhase.embedding,
              processed: processed,
              total: total,
            ),
          ),
        );
        _scheduleRefresh();
      case IndexingDoneEvent():
        state = AsyncData(_read(indexing: const IndexingState()));
      case _:
        break;
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!ref.mounted) return;
      final cached = state.value;
      state = AsyncData(_read(indexing: cached?.indexing));
    });
  }

  Future<void> _kickWorkerIfPending() async {
    final repo = _repo;
    final assistant = _assistant;
    if (repo == null || assistant == null) return;
    final pending = repo.countUnembedded();
    if (pending == 0) return;
    _markIndexingStart(pending);
    await assistant.enqueueEmbeddings();
  }

  void _markIndexingStart(int pending) {
    final cached = state.value;
    if (cached == null) return;
    state = AsyncData(
      cached.copyWith(
        indexing: IndexingState(
          phase: IndexingPhase.embedding,
          processed: 0,
          total: pending,
        ),
      ),
    );
  }

  ContextState _read({IndexingState? indexing}) {
    final repo = _repo!;
    final grouped = repo.groupedByDocument();
    final docs = [
      for (final entry in grouped.entries)
        ContextDocument(title: entry.key, chunks: entry.value),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return ContextState(
      documents: docs,
      totalChunks: repo.countAll(),
      embeddedChunks: repo.countWithEmbeddings(),
      indexing: indexing ?? state.value?.indexing ?? const IndexingState(),
    );
  }

  Future<int> addDocument({
    required String title,
    required String text,
  }) async {
    final repo = _repo;
    final chunker = _chunker;
    final assistant = _assistant;
    if (repo == null || chunker == null) return 0;
    final cleanTitle = title.trim().isEmpty
        ? 'Untitled (${DateTime.now().toIso8601String()})'
        : title.trim();
    repo.removeDocument(cleanTitle);
    final chunks = chunker.chunk(title: cleanTitle, text: text);
    if (chunks.isEmpty) {
      state = AsyncData(_read());
      return 0;
    }

    repo.putMany(chunks);
    state = AsyncData(_read());

    if (assistant != null) {
      _markIndexingStart(repo.countUnembedded());
      await assistant.enqueueEmbeddings();
    }
    return chunks.length;
  }

  Future<void> removeDocument(String title) async {
    _repo?.removeDocument(title);
    state = AsyncData(_read());
  }

  Future<void> clearAll() async {
    _repo?.removeAll();
    state = AsyncData(_read());
  }

  Future<void> reindexAll() async {
    final repo = _repo;
    final assistant = _assistant;
    if (repo == null || assistant == null) return;
    final chunks = repo.all();
    if (chunks.isEmpty) return;
    for (final chunk in chunks) {
      chunk.embedding = null;
    }
    repo.putMany(chunks);
    state = AsyncData(_read());
    _markIndexingStart(chunks.length);
    await assistant.enqueueEmbeddings();
  }
}

final contextControllerProvider =
    AsyncNotifierProvider<ContextController, ContextState>(
  ContextController.new,
);
