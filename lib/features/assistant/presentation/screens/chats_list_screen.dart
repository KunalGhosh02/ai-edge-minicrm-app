import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/app/router/app_router.dart';
import 'package:minicrm/features/assistant/data/repositories/object_box_chat_history_repository.dart';
import 'package:minicrm/features/assistant/domain/entities/chat_thread.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/assistant/presentation/widgets/models_sheet.dart';

class ChatsListScreen extends ConsumerStatefulWidget {
  const ChatsListScreen({super.key});

  @override
  ConsumerState<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends ConsumerState<ChatsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(assistantControllerProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    final threadsAsync = ref.watch(chatThreadsProvider);
    final state = ref.watch(assistantControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Models',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => unawaited(ModelsSheet.show(context)),
          ),
        ],
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load chats: $e')),
        data: (threads) {
          if (threads.isEmpty) {
            return _EmptyChats(hasModel: state.currentModel != null);
          }
          return ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final thread = threads[index];
              return _ChatThreadTile(thread: thread);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onNewChat(context),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New chat'),
      ),
    );
  }

  Future<void> _onNewChat(BuildContext context) async {
    final controller = ref.read(assistantControllerProvider.notifier);
    final thread = await controller.createThread();
    if (!context.mounted) return;
    unawaited(context.push(AppRoute.assistantChat(thread.id)));
  }
}

class _ChatThreadTile extends ConsumerWidget {
  const _ChatThreadTile({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final initials = _initials(thread.title);
    return Dismissible(
      key: ValueKey(thread.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        unawaited(
          ref
              .read(assistantControllerProvider.notifier)
              .deleteThread(thread.id),
        );
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(initials),
        ),
        title: Text(
          thread.title.isEmpty ? 'Untitled' : thread.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatTimestamp(thread.updatedAt),
          style: theme.textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<_ThreadAction>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) => _onAction(context, ref, action),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ThreadAction.rename,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Rename'),
              ),
            ),
            PopupMenuItem(
              value: _ThreadAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
          ],
        ),
        onTap: () => context.push(AppRoute.assistantChat(thread.id)),
      ),
    );
  }

  static String _initials(String title) {
    final cleaned = title.trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    if (that == today) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final diff = today.difference(that).inDays;
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[dt.weekday - 1];
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This permanently deletes "${thread.title}" and its messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _ThreadAction action,
  ) async {
    switch (action) {
      case _ThreadAction.rename:
        final next = await _promptRename(context, thread.title);
        if (next == null || next.trim().isEmpty) return;
        await ref
            .read(assistantControllerProvider.notifier)
            .renameThread(threadId: thread.id, title: next.trim());
      case _ThreadAction.delete:
        if (await _confirmDelete(context)) {
          await ref
              .read(assistantControllerProvider.notifier)
              .deleteThread(thread.id);
        }
    }
  }

  Future<String?> _promptRename(BuildContext context, String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

enum _ThreadAction { rename, delete }

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.hasModel});

  final bool hasModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No chats yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              hasModel
                  ? 'Tap "New chat" below to start your first conversation.'
                  : 'Open Models to download a model, then start a new chat.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
