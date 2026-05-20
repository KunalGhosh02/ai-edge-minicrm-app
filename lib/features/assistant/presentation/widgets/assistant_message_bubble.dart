import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';

class AssistantMessageBubble extends StatelessWidget {
  const AssistantMessageBubble({required this.message, super.key});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == AssistantRole.user;
    final bg = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fg = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.hasThinking)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ThoughtsPanel(
                  thinking: message.thinking,
                  isStreaming: message.isStreaming,
                  foreground: fg,
                ),
              ),
            _BubbleContent(message: message, foreground: fg),
            if (message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _BlinkingCursor(color: fg.withValues(alpha: 0.85)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThoughtsPanel extends StatefulWidget {
  const _ThoughtsPanel({
    required this.thinking,
    required this.isStreaming,
    required this.foreground,
  });

  final String thinking;
  final bool isStreaming;
  final Color foreground;

  @override
  State<_ThoughtsPanel> createState() => _ThoughtsPanelState();
}

class _ThoughtsPanelState extends State<_ThoughtsPanel> {
  bool? _userExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = widget.foreground.withValues(alpha: 0.7);
    final muted = widget.foreground.withValues(alpha: 0.55);
    final expanded = _userExpanded ?? widget.isStreaming;
    return Container(
      decoration: BoxDecoration(
        color: widget.foreground.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.foreground.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _userExpanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    widget.isStreaming ? 'Thinking…' : 'Thoughts',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                widget.thinking,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dim,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BubbleContent extends StatelessWidget {
  const _BubbleContent({required this.message, required this.foreground});

  final AssistantMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(color: foreground);

    if (message.text.isEmpty && message.isStreaming) {
      return const SizedBox(height: 4);
    }

    if (message.role == AssistantRole.user) {
      return Text(message.text, style: baseStyle);
    }

    return _RichAssistantContent(text: message.text, baseStyle: baseStyle);
  }
}

class _RichAssistantContent extends StatelessWidget {
  const _RichAssistantContent({required this.text, required this.baseStyle});

  final String text;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final html = md.markdownToHtml(
      text,
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: [md.InlineHtmlSyntax()],
      encodeHtml: false,
    );

    return HtmlWidget(
      html,
      textStyle: baseStyle,
      renderMode: RenderMode.column,
      onTapUrl: (_) => true,
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor({required this.color});

  final Color color;

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value < 0.5 ? 1.0 : 0.0,
          child: child,
        );
      },
      child: Container(
        width: 8,
        height: 16,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
