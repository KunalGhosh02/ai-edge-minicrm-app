import 'package:equatable/equatable.dart';

enum AssistantRole { user, assistant }

class AssistantMessage extends Equatable {
  const AssistantMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.isStreaming = false,
    this.thinking = '',
  });

  final String id;
  final AssistantRole role;
  final String text;
  final DateTime createdAt;
  final bool isStreaming;

  /// Reasoning content emitted before / interleaved with [text] (e.g.
  /// DeepSeek R1 `<think>...</think>`, Qwen 3 think blocks, Gemma 4 thought
  /// channel). Rendered in the collapsible "Thoughts" section of the bubble.
  final String thinking;

  bool get hasThinking => thinking.isNotEmpty;

  AssistantMessage append(String chunk) {
    return AssistantMessage(
      id: id,
      role: role,
      text: text + chunk,
      createdAt: createdAt,
      isStreaming: isStreaming,
      thinking: thinking,
    );
  }

  AssistantMessage appendThinking(String chunk) {
    return AssistantMessage(
      id: id,
      role: role,
      text: text,
      createdAt: createdAt,
      isStreaming: isStreaming,
      thinking: thinking + chunk,
    );
  }

  AssistantMessage finalize(String finalText) {
    return AssistantMessage(
      id: id,
      role: role,
      text: finalText.isEmpty ? text : finalText,
      createdAt: createdAt,
      thinking: thinking,
    );
  }

  @override
  List<Object?> get props => [id, role, text, createdAt, isStreaming, thinking];
}
