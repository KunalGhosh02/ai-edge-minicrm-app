import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/app/router/app_router.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        FlutterForegroundTask.minimizeApp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MiniCRM Support Bot'),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroCard(),
              const SizedBox(height: 12),
              const _ModelStatusCard(),
              const SizedBox(height: 16),
              _NavCard(
                icon: Icons.smart_toy_outlined,
                title: 'Playground',
                subtitle:
                    'Chat with the on-device LiteRT-LM model in a foreground worker.',
                onTap: () => context.push(AppRoute.assistant),
              ),
              const SizedBox(height: 8),
              _NavCard(
                icon: Icons.library_books_outlined,
                title: 'Context',
                subtitle:
                    'Add knowledge base documents the playground can retrieve.',
                onTap: () => context.push(AppRoute.context),
              ),
              const SizedBox(height: 8),
              _NavCard(
                icon: Icons.tune,
                title: 'System prompt',
                subtitle:
                    'Edit the instruction the model receives on every turn.',
                onTap: () => context.push(AppRoute.systemPrompt),
              ),
              const SizedBox(height: 8),
              _NavCard(
                icon: Icons.cloud_sync_outlined,
                title: 'Set up Support Bot',
                subtitle:
                    'Connect Firebase Auth + Firestore so chats can sync to the cloud.',
                onTap: () => context.push(AppRoute.cloudSetup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: const Icon(Icons.shield_outlined),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'On-device AI support',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Zero cloud API cost. Queries never leave this device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelStatusCard extends ConsumerWidget {
  const _ModelStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(assistantControllerProvider);
    final chatLoaded = state.currentModel != null;
    final embedderLoaded = state.embedderLoaded;
    final bg = chatLoaded
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.errorContainer;
    final fg = chatLoaded
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onErrorContainer;

    final chatDetail = chatLoaded
        ? '${state.currentModel!.name} · '
            '${(state.currentBackend ?? '').toUpperCase()}'
        : 'No chat model — customers get a placeholder reply';

    final embedderDetail = embedderLoaded
        ? '${_embedderName(state.embedderModelPath)} · '
            '${(state.embedderBackend ?? '').toUpperCase()}'
        : 'No embedder — RAG falls back to keyword search';

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoute.models),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                chatLoaded
                    ? Icons.check_circle
                    : Icons.warning_amber_rounded,
                color: fg,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Models',
                      style: theme.textTheme.titleSmall?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 2),
                    _StatusLine(
                      icon: chatLoaded
                          ? Icons.smart_toy
                          : Icons.smart_toy_outlined,
                      label: 'Chat',
                      detail: chatDetail,
                      color: fg,
                    ),
                    const SizedBox(height: 2),
                    _StatusLine(
                      icon: embedderLoaded
                          ? Icons.scatter_plot
                          : Icons.scatter_plot_outlined,
                      label: 'Embedder',
                      detail: embedderDetail,
                      color: fg,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  static String _embedderName(String? path) {
    if (path == null) return '';
    final file = path.split('/').last;
    return file.replaceAll('.tflite', '');
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: detail,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
