import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/assistant/presentation/widgets/hf_token_card.dart';
import 'package:minicrm/features/assistant/presentation/widgets/models_view.dart';

class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assistantControllerProvider);
    final theme = Theme.of(context);
    final modelLoaded = state.currentModel != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Models')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ActiveModelBanner(
              modelLoaded: modelLoaded,
              modelName: state.currentModel?.name,
              backend: state.currentBackend,
              embedderLoaded: state.embedderLoaded,
            ),
            const SizedBox(height: 12),
            const HfTokenCard(),
            const SizedBox(height: 4),
            Text(
              'Manage models',
              style: theme.textTheme.titleMedium,
            ),
            const ModelsView(),
          ],
        ),
      ),
    );
  }
}

class _ActiveModelBanner extends StatelessWidget {
  const _ActiveModelBanner({
    required this.modelLoaded,
    required this.modelName,
    required this.backend,
    required this.embedderLoaded,
  });

  final bool modelLoaded;
  final String? modelName;
  final String? backend;
  final bool embedderLoaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = modelLoaded
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.errorContainer;
    final onColor = modelLoaded
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            modelLoaded ? Icons.check_circle : Icons.warning_amber_rounded,
            color: onColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelLoaded ? 'Model loaded' : 'No model loaded',
                  style:
                      theme.textTheme.titleSmall?.copyWith(color: onColor),
                ),
                Text(
                  modelLoaded
                      ? '$modelName · ${(backend ?? '').toUpperCase()}'
                          '${embedderLoaded ? ' · embedder ready' : ''}'
                      : 'Customers will get a placeholder reply until you '
                          'load a chat model below.',
                  style: theme.textTheme.bodySmall?.copyWith(color: onColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
