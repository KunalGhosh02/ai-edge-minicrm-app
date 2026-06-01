import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/presentation/controllers/hf_token_controller.dart';

class HfTokenCard extends ConsumerWidget {
  const HfTokenCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokenAsync = ref.watch(hfTokenProvider);
    final hasToken = tokenAsync.maybeWhen(
      data: (t) => t != null && t.isNotEmpty,
      orElse: () => false,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  hasToken ? Icons.verified_user : Icons.lock_outline,
                  color: hasToken
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  'HuggingFace token',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (hasToken)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    label: const Text('Saved'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasToken
                  ? 'Used automatically when installing gated models. Stored '
                      'in the device keystore — never leaves this device.'
                  : 'Required for Gemma / EmbeddingGemma. Create a read-only '
                      'token at huggingface.co/settings/tokens, accept the '
                      'model license, then paste it here. Stored in the '
                      'device keystore.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (hasToken) ...[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Replace'),
                      onPressed: () => _onConfigure(context, ref),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear saved token',
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    onPressed: () => _onClear(context, ref),
                  ),
                ] else
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Set up token'),
                      onPressed: () => _onConfigure(context, ref),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onConfigure(BuildContext context, WidgetRef ref) async {
    final token = await showDialog<String>(
      context: context,
      builder: (_) => const _HfTokenDialog(),
    );
    if (token == null) return;
    await ref.read(hfTokenProvider.notifier).save(token);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(token.isEmpty ? 'Token cleared' : 'Token saved'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear saved token?'),
        content: const Text(
          'You will need to paste the token again to install gated models.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hfTokenProvider.notifier).clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Token cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _HfTokenDialog extends ConsumerStatefulWidget {
  const _HfTokenDialog();

  @override
  ConsumerState<_HfTokenDialog> createState() => _HfTokenDialogState();
}

class _HfTokenDialogState extends ConsumerState<_HfTokenDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    unawaited(_prefill());
  }

  Future<void> _prefill() async {
    final current = ref.read(hfTokenProvider).value;
    if (current != null && mounted) {
      _controller.text = current;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('HuggingFace token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste a read-only token from '
            'huggingface.co/settings/tokens. Accept the model license on '
            'each gated model page before installing.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'hf_...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
