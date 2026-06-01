import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/context/data/services/pdf_text_extractor.dart';
import 'package:minicrm/features/context/presentation/controllers/context_controller.dart';
import 'package:minicrm/features/context/presentation/controllers/context_providers.dart';

class ContextScreen extends ConsumerWidget {
  const ContextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(contextControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Context'),
        actions: [
          IconButton(
            tooltip: 'Re-embed all (after loading a new embedder)',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(
              ref.read(contextControllerProvider.notifier).reindexAll(),
            ),
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add document'),
        onPressed: () => _showAddSheet(context, ref),
      ),
      body: SafeArea(
        top: false,
        child: stateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to open context store: $e'),
            ),
          ),
          data: (state) {
            if (state.documents.isEmpty && !state.indexing.isRunning) {
              return const _EmptyContext();
            }
            final assistant = ref.watch(assistantControllerProvider);
            final missing = state.totalChunks - state.embeddedChunks;
            final showIndexCta = missing > 0 &&
                !state.indexing.isRunning &&
                assistant.embedderLoaded;
            final showLoadEmbedderCta = missing > 0 &&
                !state.indexing.isRunning &&
                !assistant.embedderLoaded;
            return Column(
              children: [
                _ContextSummary(
                  documentCount: state.documents.length,
                  chunkCount: state.totalChunks,
                  embeddedChunks: state.embeddedChunks,
                ),
                if (state.indexing.isRunning)
                  _IndexingBar(state: state.indexing)
                else if (showIndexCta)
                  _IndexCta(
                    missing: missing,
                    onIndex: () => unawaited(
                      ref
                          .read(contextControllerProvider.notifier)
                          .reindexAll(),
                    ),
                  )
                else if (showLoadEmbedderCta)
                  _LoadEmbedderCta(missing: missing),
                Expanded(
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: state.documents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final doc = state.documents[i];
                      return _DocumentCard(
                        document: doc,
                        onDelete: () => unawaited(
                          ref
                              .read(contextControllerProvider.notifier)
                              .removeDocument(doc.title),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddDocumentSheet(),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all context?'),
        content: const Text(
          'This removes every document and chunk from the on-device vector '
          'store. The model files are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(contextControllerProvider.notifier).clearAll();
  }
}

class _EmptyContext extends StatelessWidget {
  const _EmptyContext();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No context yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add document" to paste plain text or import a PDF. '
              'Documents are chunked and stored in the on-device ObjectBox '
              'vector store, ready for RAG.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextSummary extends StatelessWidget {
  const _ContextSummary({
    required this.documentCount,
    required this.chunkCount,
    required this.embeddedChunks,
  });

  final int documentCount;
  final int chunkCount;
  final int embeddedChunks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverage = chunkCount == 0
        ? 0
        : ((embeddedChunks / chunkCount) * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$documentCount document${documentCount == 1 ? '' : 's'} · '
            '$chunkCount chunk${chunkCount == 1 ? '' : 's'} stored on device',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            chunkCount == 0
                ? 'No embeddings indexed yet.'
                : '$embeddedChunks of $chunkCount chunks indexed for vector '
                    'search ($coverage%). Lexical fallback is used for the rest.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: embeddedChunks == chunkCount && chunkCount > 0
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexingBar extends StatelessWidget {
  const _IndexingBar({required this.state});

  final IndexingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Embedding chunks · ${state.processed} / ${state.total}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: state.total == 0 ? null : state.progress,
          ),
        ],
      ),
    );
  }
}

class _IndexCta extends StatelessWidget {
  const _IndexCta({required this.missing, required this.onIndex});

  final int missing;
  final VoidCallback onIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(
            Icons.bolt_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$missing chunk${missing == 1 ? '' : 's'} not yet indexed. '
              'Embedder is loaded — index now to enable semantic search.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onIndex,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Index now'),
          ),
        ],
      ),
    );
  }
}

class _LoadEmbedderCta extends StatelessWidget {
  const _LoadEmbedderCta({required this.missing});

  final int missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$missing chunk${missing == 1 ? '' : 's'} stored without '
              'embeddings. Load an embedder from the Playground > Models sheet '
              'to enable semantic search; indexing will start automatically.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onDelete,
  });

  final ContextDocument document;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(document.title),
        subtitle: Text(
          '${document.chunks.length} chunk'
          '${document.chunks.length == 1 ? '' : 's'} · '
          '${document.totalCharacters} chars',
        ),
        trailing: IconButton(
          tooltip: 'Delete document',
          icon: Icon(
            Icons.delete_outline,
            color: theme.colorScheme.error,
          ),
          onPressed: onDelete,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final chunk in document.chunks.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '#${chunk.chunkIndex}: ${chunk.text}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (document.chunks.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${document.chunks.length - 3} more chunks',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _AddDocumentSheet extends ConsumerStatefulWidget {
  const _AddDocumentSheet();

  @override
  ConsumerState<_AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends ConsumerState<_AddDocumentSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  bool _submitting = false;
  bool _extracting = false;
  String? _pdfStatus;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) return;
    setState(() => _submitting = true);
    final added = await ref
        .read(contextControllerProvider.notifier)
        .addDocument(
          title: _titleController.text,
          text: body,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $added chunk${added == 1 ? '' : 's'} to context.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickAndExtractPdf() async {
    if (_extracting) return;
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: false,
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open picker: $e')),
      );
      return;
    }
    final path = picked?.files.singleOrNull?.path;
    final name = picked?.files.singleOrNull?.name;
    if (path == null) return;

    setState(() {
      _extracting = true;
      _pdfStatus = 'Extracting text from $name…';
    });
    try {
      final extractor = ref.read(pdfTextExtractorProvider);
      final result = await extractor.extractFromPath(path);
      if (!mounted) return;
      if (result.text.isEmpty) {
        setState(() {
          _extracting = false;
          _pdfStatus = 'No selectable text found in $name '
              '(scanned PDFs are not supported).';
        });
        return;
      }
      _titleController.text = _stripPdfExt(name ?? path);
      _bodyController.text = result.text;
      setState(() {
        _extracting = false;
        _pdfStatus = 'Extracted ${result.text.length} chars '
            'from ${result.pageCount} page'
            '${result.pageCount == 1 ? '' : 's'}. '
            'Review and save to chunk and embed.';
      });
    } on PdfExtractionException catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _pdfStatus = 'Failed: ${e.message}';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _pdfStatus = 'Failed: $e';
      });
    }
  }

  static String _stripPdfExt(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return name.substring(0, name.length - 4);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final busy = _submitting || _extracting;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + keyboardInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add document', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : _pickAndExtractPdf,
                icon: _extracting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _extracting ? 'Extracting…' : 'Import from PDF',
                ),
              ),
              if (_pdfStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _pdfStatus!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'FAQ · Pricing, Refund policy, …',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Document body',
                  hintText:
                      'Paste plain text or import a PDF above. Will be chunked '
                      '(≈200 words, 20-word overlap) and stored in ObjectBox.',
                ),
                minLines: 6,
                maxLines: 16,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_submitting ? 'Saving…' : 'Save document'),
                  onPressed: busy ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
