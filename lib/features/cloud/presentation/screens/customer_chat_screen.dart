import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:minicrm/features/cloud/data/repositories/firestore_customer_session_repository.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_message.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_session.dart';
import 'package:minicrm/features/cloud/presentation/controllers/auth_controller.dart';
import 'package:uuid/uuid.dart';

class CustomerChatScreen extends ConsumerStatefulWidget {
  const CustomerChatScreen({required this.customerId, super.key});

  final String customerId;

  @override
  ConsumerState<CustomerChatScreen> createState() =>
      _CustomerChatScreenState();
}

class _CustomerChatScreenState extends ConsumerState<CustomerChatScreen> {
  static const _uuid = Uuid();

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _sendManualReply(String userId) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final repo = ref.read(customerSessionRepositoryProvider);
    try {
      await repo.appendAssistantMessage(
        userId: userId,
        customerId: widget.customerId,
        message: CustomerMessage(
          id: _uuid.v4(),
          sender: CustomerSender.assistant,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      _input.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleTakeover({
    required String userId,
    required bool current,
  }) async {
    final repo = ref.read(customerSessionRepositoryProvider);
    await repo.setSessionTakenOver(
      userId: userId,
      customerId: widget.customerId,
      takenOver: !current,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authStatus = ref.watch(authControllerProvider).status;
    if (authStatus is! AuthSignedIn) {
      return const Scaffold(
        body: Center(child: Text('Sign in to view customer sessions.')),
      );
    }
    final uid = authStatus.user.uid;
    final repo = ref.watch(customerSessionRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<CustomerSession?>(
          stream: repo.watchSession(userId: uid, customerId: widget.customerId),
          builder: (context, snap) {
            final session = snap.data;
            final name = session?.customerName ?? widget.customerId;
            return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
          },
        ),
        actions: [
          StreamBuilder<CustomerSession?>(
            stream: repo.watchSession(
              userId: uid,
              customerId: widget.customerId,
            ),
            builder: (context, snap) {
              final takenOver = snap.data?.takenOver ?? false;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    const Text('Take over'),
                    Switch(
                      value: takenOver,
                      onChanged: (_) => unawaited(
                        _toggleTakeover(userId: uid, current: takenOver),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TakeoverBanner(customerId: widget.customerId),
            Expanded(
              child: StreamBuilder<List<CustomerMessage>>(
                stream: repo.watchMessages(
                  userId: uid,
                  customerId: widget.customerId,
                ),
                builder: (context, snap) {
                  final messages = snap.data ?? const <CustomerMessage>[];
                  if (snap.connectionState == ConnectionState.waiting &&
                      messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (messages.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No messages yet. When the customer sends one, '
                          'the bot replies automatically — unless you take '
                          'over above.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) {
                      unawaited(_scroll.animateTo(
                        _scroll.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      ));
                    }
                  });
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: messages[index]),
                  );
                },
              ),
            ),
            _Composer(
              controller: _input,
              sending: _sending,
              onSend: () => _sendManualReply(uid),
            ),
          ],
        ),
      ),
    );
  }
}

class _TakeoverBanner extends ConsumerWidget {
  const _TakeoverBanner({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authControllerProvider).status;
    if (authStatus is! AuthSignedIn) return const SizedBox.shrink();
    final uid = authStatus.user.uid;
    final repo = ref.watch(customerSessionRepositoryProvider);
    return StreamBuilder<CustomerSession?>(
      stream: repo.watchSession(
        userId: uid,
        customerId: customerId,
      ),
      builder: (context, snap) {
        final takenOver = snap.data?.takenOver ?? false;
        if (!takenOver) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Container(
          width: double.infinity,
          color: theme.colorScheme.tertiaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'You are responding manually. The bot will not auto-reply on this '
            'session until you toggle Take over off.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final CustomerMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssistant = message.sender == CustomerSender.assistant;
    final bg = isAssistant
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.primary;
    final fg = isAssistant
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onPrimary;
    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(color: fg),
          child: isAssistant
              ? HtmlWidget(
                  md.markdownToHtml(
                    message.text,
                    extensionSet: md.ExtensionSet.gitHubWeb,
                    inlineSyntaxes: [md.InlineHtmlSyntax()],
                    encodeHtml: false,
                  ),
                  textStyle:
                      theme.textTheme.bodyMedium!.copyWith(color: fg),
                  renderMode: RenderMode.column,
                  onTapUrl: (_) => true,
                )
              : Text(message.text),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a reply as the assistant…',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
