import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/app/router/app_router.dart';

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
              const SizedBox(height: 16),
              _NavCard(
                icon: Icons.smart_toy_outlined,
                title: 'Assistant',
                subtitle:
                    'Chat with the on-device LiteRT-LM model in a foreground worker.',
                onTap: () => context.push(AppRoute.assistant),
              ),
              const SizedBox(height: 8),
              _NavCard(
                icon: Icons.library_books_outlined,
                title: 'Context',
                subtitle:
                    'Add knowledge base documents that the assistant can retrieve.',
                onTap: () => context.push(AppRoute.context),
              ),
              const SizedBox(height: 8),
              _NavCard(
                icon: Icons.tune,
                title: 'System prompt',
                subtitle: 'Edit the instruction the model receives on every turn.',
                onTap: () => context.push(AppRoute.systemPrompt),
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
