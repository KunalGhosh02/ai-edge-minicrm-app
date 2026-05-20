import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/domain/entities/installed_model.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';

class ModelsSheet extends ConsumerStatefulWidget {
  const ModelsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ModelsSheet(),
    );
  }

  @override
  ConsumerState<ModelsSheet> createState() => _ModelsSheetState();
}

class _ModelsSheetState extends ConsumerState<ModelsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref
            .read(assistantControllerProvider.notifier)
            .refreshInstalledModels(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // Hide tokenizer companion files from the user-facing list; they are
    // managed automatically alongside the embedder .tflite.
    final installed = state.installedModels
        .where((m) => !m.name.endsWith('.model'))
        .toList();
    final installedNames = installed.map((m) => m.name).toSet();
    final availablePresets = ModelPresets.all
        .where((p) => !installedNames.contains(ModelPresets.fileNameOf(p)))
        .toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: 16 + keyboardInset,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Models',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SectionHeader(
              title: 'Installed (${installed.length})',
              action: installed.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () {
                        unawaited(
                          ref
                              .read(assistantControllerProvider.notifier)
                              .refreshInstalledModels(),
                        );
                      },
                    ),
            ),
            if (installed.isEmpty)
              const _EmptyInstalled()
            else
              for (final model in installed)
                _InstalledModelTile(
                  model: model,
                  isActive: state.currentModel?.path == model.path,
                  activeBackend:
                      state.currentModel?.path == model.path
                          ? state.currentBackend
                          : null,
                  embedderLoadedPath:
                      state.embedderLoaded ? state.embedderModelPath : null,
                  embedderActiveBackend:
                      state.embedderLoaded ? state.embedderBackend : null,
                  allInstalled: state.installedModels,
                ),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Available (${availablePresets.length})'),
            const SizedBox(height: 6),
            Text(
              'Downloads auto-resume on failure — tap install again to '
              'continue. The selected backend is used the first time the model '
              'loads; you can switch later from the installed list.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _InstallNewSection(availablePresets: availablePresets),
          ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        ?action,
      ],
    );
  }
}

class _EmptyInstalled extends StatelessWidget {
  const _EmptyInstalled();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "No models on this device yet. Pick one from 'Available' below to "
        "download it. Files live in the app's private storage and are "
        'auto-loaded the next time you open the assistant.',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _InstalledModelTile extends ConsumerStatefulWidget {
  const _InstalledModelTile({
    required this.model,
    required this.isActive,
    required this.activeBackend,
    required this.embedderLoadedPath,
    required this.embedderActiveBackend,
    required this.allInstalled,
  });

  final InstalledModel model;
  final bool isActive;
  final String? activeBackend;

  /// Path of the currently loaded embedder model (.tflite), or null.
  final String? embedderLoadedPath;

  /// Backend (`cpu` / `gpu`) reported by the currently loaded embedder.
  final String? embedderActiveBackend;

  /// Full list of installed files including hidden tokenizers; used to
  /// resolve the embedder's sentencepiece.model companion.
  final List<InstalledModel> allInstalled;

  @override
  ConsumerState<_InstalledModelTile> createState() =>
      _InstalledModelTileState();
}

class _InstalledModelTileState extends ConsumerState<_InstalledModelTile> {
  late String _backend = widget.activeBackend ?? 'cpu';
  late String _embedderBackend =
      widget.embedderActiveBackend ?? widget.activeBackend ?? 'cpu';

  @override
  void didUpdateWidget(_InstalledModelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeBackend != null &&
        widget.activeBackend != oldWidget.activeBackend) {
      _backend = widget.activeBackend!;
    }
    if (widget.embedderActiveBackend != null &&
        widget.embedderActiveBackend != oldWidget.embedderActiveBackend) {
      _embedderBackend = widget.embedderActiveBackend!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = ModelPresets.matchByFileName(widget.model.name);
    final displayName = preset?.name ?? widget.model.name;
    final isEmbedding = preset?.kind == ModelKind.embedding ||
        widget.model.name.endsWith('.tflite');
    final isEmbedderLoaded =
        isEmbedding && widget.embedderLoadedPath == widget.model.path;
    final isHeavyEmbedder =
        isEmbedding && widget.model.name.contains('seq2048');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isActive
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: widget.isActive
            ? Border.all(color: theme.colorScheme.tertiary, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: theme.textTheme.titleSmall),
                    Text(
                      '${widget.model.humanSize} · ${widget.model.name}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isEmbedding)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    isEmbedderLoaded ? Icons.check_circle : Icons.scatter_plot,
                    size: 16,
                    color: isEmbedderLoaded
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary,
                  ),
                  label: Text(
                    isEmbedderLoaded
                        ? 'Loaded · '
                            '${(widget.embedderActiveBackend ?? '').toUpperCase()}'
                        : 'Embedding',
                  ),
                )
              else if (widget.isActive)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  label: Text(
                    'Active · ${(widget.activeBackend ?? '').toUpperCase()}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (isEmbedding)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isHeavyEmbedder) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Long-context (seq 2048) build. Each embed pads '
                            'to 2048 tokens — 4x slower and 4x more memory '
                            'than seq 512. Often crashes on devices with '
                            '<6 GB RAM. Recommended: delete this and install '
                            '“EmbeddingGemma 300M (seq 512)” from the '
                            'presets list.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  isEmbedderLoaded
                      ? 'Embedder is loaded and used for RAG retrieval.'
                      : 'Pick a backend, then tap Load to enable semantic '
                          'search over your context documents.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (!isEmbedderLoaded)
                      Expanded(
                        child: _BackendDropdown(
                          value: _embedderBackend,
                          allowNpu: false,
                          onChanged: (v) =>
                              setState(() => _embedderBackend = v),
                        ),
                      )
                    else
                      const Expanded(child: SizedBox.shrink()),
                    if (!isEmbedderLoaded && _embedderBackend == 'gpu') ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'EmbeddingGemma uses ops that the GPU '
                            'delegate cannot run (broadcasting ADD/MUL, '
                            'EMBEDDING_LOOKUP, FULLY_CONNECTED v12). About '
                            '98% of the graph falls back to CPU and the '
                            'GPU↔CPU memory copies make it slower than '
                            'pure CPU on most devices. Prefer CPU.',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    if (isEmbedderLoaded)
                      IconButton(
                        tooltip: 'Unload embedder',
                        icon: Icon(
                          Icons.eject_outlined,
                          color: theme.colorScheme.secondary,
                        ),
                        onPressed: _onUnloadEmbedder,
                      )
                    else
                      Consumer(
                        builder: (context, ref, _) {
                          final loading = ref.watch(
                            assistantControllerProvider
                                .select((s) => s.embedderLoading),
                          );
                          final canLoad = !loading &&
                              _resolveTokenizerPath() != null;
                          return FilledButton.tonalIcon(
                            onPressed: canLoad ? _onLoadEmbedder : null,
                            icon: loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(loading ? 'Loading…' : 'Load'),
                          );
                        },
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Delete',
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      onPressed: _onDelete,
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _BackendDropdown(
                    value: _backend,
                    onChanged: (v) => setState(() => _backend = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _canLoad ? _onLoad : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_canLoad ? 'Load' : 'Loaded'),
                ),
                if (widget.isActive) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Unload model',
                    icon: Icon(
                      Icons.eject_outlined,
                      color: theme.colorScheme.secondary,
                    ),
                    onPressed: _onUnload,
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: _onDelete,
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool get _canLoad => !widget.isActive || widget.activeBackend != _backend;

  void _onLoad() {
    final preset = ModelPresets.matchByFileName(widget.model.name);
    unawaited(
      ref.read(assistantControllerProvider.notifier).loadInstalledModel(
            model: widget.model,
            backend: _backend,
            chatFamily: preset?.chatFamily.id ?? 'general',
            maxTokens: preset?.maxTokens ?? 4096,
          ),
    );
    Navigator.of(context).pop();
  }

  void _onUnload() {
    unawaited(ref.read(assistantControllerProvider.notifier).unloadModel());
    Navigator.of(context).pop();
  }

  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text(
          '${widget.model.name} (${widget.model.humanSize}) will be removed '
          'from this device. You can re-download it later.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(assistantControllerProvider.notifier)
        .deleteInstalledModel(widget.model);
    // For embedders, also nuke the tokenizer companion.
    final tokenizerPath = _resolveTokenizerPath();
    if (tokenizerPath != null) {
      await ref
          .read(assistantControllerProvider.notifier)
          .deleteInstalledModel(
            InstalledModel(
              path: tokenizerPath,
              name: tokenizerPath.split('/').last,
              sizeBytes: 0,
            ),
          );
    }
  }

  /// Resolves the sentencepiece tokenizer companion that sits next to
  /// the embedder .tflite file.
  String? _resolveTokenizerPath() {
    if (!widget.model.name.endsWith('.tflite')) return null;
    for (final m in widget.allInstalled) {
      if (m.name.endsWith('.model')) return m.path;
    }
    return null;
  }

  Future<void> _onLoadEmbedder() async {
    final tokenizerPath = _resolveTokenizerPath();
    if (tokenizerPath == null) return;
    final preset = ModelPresets.matchByFileName(widget.model.name);
    final runtime = preset?.runtime ?? EmbedderRuntimeKind.tflite;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(assistantControllerProvider.notifier).loadEmbedder(
            modelPath: widget.model.path,
            tokenizerPath: tokenizerPath,
            backend: _embedderBackend,
            runtime: runtime.id,
            sequenceLength: preset?.sequenceLength,
            presetId: preset?.id,
          );
      if (navigator.mounted) {
        navigator.pop();
      }
    } on Object catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('Embedder load failed: $e')),
      );
    }
  }

  void _onUnloadEmbedder() {
    unawaited(ref.read(assistantControllerProvider.notifier).unloadEmbedder());
    Navigator.of(context).pop();
  }
}

class _InstallNewSection extends ConsumerStatefulWidget {
  const _InstallNewSection({required this.availablePresets});

  final List<ModelPreset> availablePresets;

  @override
  ConsumerState<_InstallNewSection> createState() =>
      _InstallNewSectionState();
}

class _InstallNewSectionState extends ConsumerState<_InstallNewSection> {
  static const String _customId = 'custom';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  String? _selectedId;
  String _backend = 'cpu';

  @override
  void initState() {
    super.initState();
    if (widget.availablePresets.isNotEmpty) {
      _applyPreset(widget.availablePresets.first);
    } else {
      _selectCustom();
    }
  }

  @override
  void didUpdateWidget(_InstallNewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stillAvailable = widget.availablePresets
        .any((p) => p.id == _selectedId);
    if (!stillAvailable && _selectedId != _customId) {
      if (widget.availablePresets.isNotEmpty) {
        _applyPreset(widget.availablePresets.first);
      } else {
        _selectCustom();
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _applyPreset(ModelPreset preset) {
    setState(() {
      _selectedId = preset.id;
      _urlController.text = preset.url;
    });
  }

  void _selectCustom() {
    setState(() {
      _selectedId = _customId;
      _urlController.text = '';
    });
  }

  ModelPreset? get _currentPreset {
    if (_selectedId == _customId || _selectedId == null) return null;
    return widget.availablePresets
        .firstWhere((p) => p.id == _selectedId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _currentPreset;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.availablePresets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'All curated presets are installed. Paste a custom .litertlm '
                'URL below to add another.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in widget.availablePresets)
                ChoiceChip(
                  label: Text('${p.name} · ${p.humanSize}'),
                  selected: _selectedId == p.id,
                  onSelected: (_) => _applyPreset(p),
                ),
              ChoiceChip(
                label: const Text('Custom .litertlm URL'),
                selected: _selectedId == _customId,
                onSelected: (_) => _selectCustom(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (preset?.description != null)
            _InfoBanner(
              icon: Icons.info_outline,
              text: preset!.description!,
            ),
          if (preset?.requiresAuth ?? false) ...[
            const SizedBox(height: 8),
            _InfoBanner(
              icon: Icons.lock_outline,
              text: 'Gated model: paste a HuggingFace token below and accept '
                  'the license on the model page first.',
              color: theme.colorScheme.tertiary,
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Model URL (.litertlm)',
            ),
            maxLines: 3,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'URL is required'
                : null,
          ),
          const SizedBox(height: 12),
          _BackendDropdown(
            value: _backend,
            onChanged: (v) => setState(() => _backend = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'HuggingFace token (optional)',
              hintText: 'hf_...',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download & install'),
              onPressed: _onSubmit,
            ),
          ),
        ],
      ),
    );
  }

  void _onSubmit() {
    if (!_formKey.currentState!.validate()) return;
    final url = _urlController.text.trim();
    final preset = ModelPresets.matchByUrl(url);
    final isEmbedding = preset?.kind == ModelKind.embedding;
    final token = _tokenController.text.trim().isEmpty
        ? null
        : _tokenController.text.trim();

    if (isEmbedding && preset?.tokenizerUrl != null) {
      unawaited(
        ref.read(assistantControllerProvider.notifier).installEmbedder(
              modelUrl: url,
              tokenizerUrl: preset!.tokenizerUrl!,
              token: token,
              runtime: preset.runtime.id,
              backend: _backend,
              sequenceLength: preset.sequenceLength,
              presetId: preset.id,
            ),
      );
    } else {
      unawaited(
        ref.read(assistantControllerProvider.notifier).installModel(
              url: url,
              backend: _backend,
              token: token,
              loadAfterDownload: !isEmbedding,
              chatFamily: preset?.chatFamily.id ?? 'general',
              maxTokens: preset?.maxTokens ?? 4096,
            ),
      );
    }
    Navigator.of(context).pop();
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendDropdown extends StatelessWidget {
  const _BackendDropdown({
    required this.value,
    required this.onChanged,
    this.allowNpu = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool allowNpu;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Backend',
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: 'cpu', child: Text('CPU')),
        const DropdownMenuItem(value: 'gpu', child: Text('GPU (Android)')),
        if (allowNpu)
          const DropdownMenuItem(value: 'npu', child: Text('NPU')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
