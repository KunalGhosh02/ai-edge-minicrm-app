import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/settings/data/repositories/settings_repository.dart';
import 'package:minicrm/features/settings/presentation/controllers/settings_controller.dart';

class SystemPromptScreen extends ConsumerStatefulWidget {
  const SystemPromptScreen({super.key});

  @override
  ConsumerState<SystemPromptScreen> createState() => _SystemPromptScreenState();
}

class _SystemPromptScreenState extends ConsumerState<SystemPromptScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _initialized = false;
  bool _dirty = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hydrate(String prompt) {
    if (_initialized) return;
    _controller.text = prompt;
    _controller.addListener(() {
      final dirty = _controller.text != prompt;
      if (dirty != _dirty) setState(() => _dirty = dirty);
    });
    _initialized = true;
  }

  Future<void> _save() async {
    await ref
        .read(settingsControllerProvider.notifier)
        .updateSystemPrompt(_controller.text);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('System prompt saved. New chats use it immediately.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _resetToDefault() async {
    _controller.text = SettingsRepository.defaultSystemPrompt;
    await ref.read(settingsControllerProvider.notifier).resetSystemPrompt();
    if (!mounted) return;
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('System prompt'),
        actions: [
          IconButton(
            tooltip: 'Restore default',
            icon: const Icon(Icons.restart_alt),
            onPressed: _initialized ? _resetToDefault : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load settings: $e'),
            ),
          ),
          data: (settings) {
            _hydrate(settings.systemPrompt);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _InfoCard(
                    text:
                        'Sent to the model on every conversation. Keep it tight: '
                        "state the assistant's role, tone, and any hard "
                        'constraints. RAG snippets are appended after this '
                        'prompt automatically when retrieval finds matches.',
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: 'System prompt',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use RAG (context retrieval)'),
                    subtitle: Text(
                      'When enabled, top-3 matching chunks are injected before '
                      'the user turn. Disable to compare the model with and '
                      'without context.',
                      style: theme.textTheme.bodySmall,
                    ),
                    value: settings.ragEnabled,
                    onChanged: (v) => unawaited(
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setRagEnabled(enabled: v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_dirty ? 'Save changes' : 'Saved'),
                      onPressed: _dirty ? _save : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
