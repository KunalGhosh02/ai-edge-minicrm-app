import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/app/router/app_router.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_status.dart';
import 'package:minicrm/features/assistant/domain/entities/installed_model.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/assistant/presentation/widgets/assistant_message_bubble.dart';
import 'package:minicrm/features/assistant/presentation/widgets/assistant_status_banner.dart';
import 'package:minicrm/features/assistant/presentation/widgets/prompt_input.dart';
import 'package:minicrm/features/settings/presentation/controllers/settings_controller.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({required this.threadId, super.key});

  final String threadId;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(assistantControllerProvider.notifier).start();
      await ref
          .read(assistantControllerProvider.notifier)
          .openThread(widget.threadId);
    });
  }

  @override
  void didUpdateWidget(covariant AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      unawaited(
        ref
            .read(assistantControllerProvider.notifier)
            .openThread(widget.threadId),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);

    ref.listen(assistantControllerProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    final isReady = state.status is AssistantReady;
    final isGenerating = state.status is AssistantGenerating;

    final isLoading = state.status is AssistantLoading;
    final title = state.activeThread?.title ?? 'Playground';

    final family = state.activeThread?.chatFamily;
    final familySupportsThinking = family != null && family.hasThoughts;
    final settingsAsync = ref.watch(settingsControllerProvider);
    final thinkingEnabled = settingsAsync.value?.thinkingEnabled ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (familySupportsThinking)
            IconButton(
              tooltip: thinkingEnabled
                  ? 'Thinking: on (tap to disable)'
                  : 'Thinking: off (tap to enable)',
              icon: Icon(
                thinkingEnabled
                    ? Icons.psychology
                    : Icons.psychology_outlined,
              ),
              onPressed: () => unawaited(
                ref
                    .read(settingsControllerProvider.notifier)
                    .setThinkingEnabled(enabled: !thinkingEnabled),
              ),
            ),
          IconButton(
            tooltip: 'Stop worker',
            icon: const Icon(Icons.power_settings_new),
            onPressed: controller.stop,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              AssistantStatusBanner(status: state.status),
          if (state.currentModel != null)
            _CurrentModelStrip(
              model: state.currentModel!,
              backend: state.currentBackend,
              onChange: () => context.push(AppRoute.models),
            ),
          if (state.workerLog.isNotEmpty) _WorkerLogStrip(log: state.workerLog),
          Expanded(
            child: state.messages.isEmpty
                ? _EmptyAssistant(
                    hasModel: state.currentModel != null,
                    installedCount: state.installedModels.length,
                    onOpenModels: () => context.push(AppRoute.models),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      return AssistantMessageBubble(
                        message: state.messages[index],
                      );
                    },
                  ),
          ),
          if (isGenerating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextButton.icon(
                onPressed: controller.stopGeneration,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop generation'),
              ),
            ),
              const Divider(height: 1),
              PromptInput(
                enabled: isReady,
                onSubmit: controller.send,
              ),
            ],
          ),
          if (isLoading)
            const _LoadingOverlay(),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading model into memory…',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'This can take 10–60 seconds. Larger models need more '
                  'time and may briefly stall the UI while native code '
                  'initialises.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerLogStrip extends StatelessWidget {
  const _WorkerLogStrip({required this.log});

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastFew = log.length > 3 ? log.sublist(log.length - 3) : log;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lastFew)
            Text(
              '› $line',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentModelStrip extends StatelessWidget {
  const _CurrentModelStrip({
    required this.model,
    required this.backend,
    required this.onChange,
  });

  final InstalledModel model;
  final String? backend;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = ModelPresets.matchByFileName(model.name);
    final label = preset?.name ?? model.name;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.memory, size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label · ${(backend ?? '').toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _EmptyAssistant extends StatelessWidget {
  const _EmptyAssistant({
    required this.hasModel,
    required this.installedCount,
    required this.onOpenModels,
  });

  final bool hasModel;
  final int installedCount;
  final VoidCallback onOpenModels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cta = hasModel
        ? 'Type a message below to start a chat.'
        : installedCount == 0
            ? 'No models installed yet — open Models to download one.'
            : 'Open Models to load one of your $installedCount downloaded '
                'models.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'On-device playground',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              cta,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (!hasModel) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpenModels,
                icon: const Icon(Icons.dns_outlined),
                label: const Text('Open models'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
