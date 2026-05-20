import 'package:flutter/material.dart';

class PromptInput extends StatefulWidget {
  const PromptInput({
    required this.onSubmit,
    required this.enabled,
    super.key,
  });

  final bool enabled;
  final Future<void> Function(String prompt) onSubmit;

  @override
  State<PromptInput> createState() => _PromptInputState();
}

class _PromptInputState extends State<PromptInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    await widget.onSubmit(text);
  }

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
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSubmit(),
                decoration: InputDecoration(
                  hintText: widget.enabled
                      ? 'Ask the on-device assistant…'
                      : 'Assistant not ready',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.enabled ? _handleSubmit : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
