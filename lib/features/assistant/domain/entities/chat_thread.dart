import 'package:equatable/equatable.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';

class ChatThread extends Equatable {
  const ChatThread({
    required this.id,
    required this.title,
    required this.systemInstruction,
    required this.chatFamily,
    required this.createdAt,
    required this.updatedAt,
    this.modelId,
  });

  final String id;
  final String title;
  final String systemInstruction;
  final ChatModelFamily chatFamily;
  final String? modelId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatThread copyWith({
    String? title,
    String? systemInstruction,
    ChatModelFamily? chatFamily,
    String? modelId,
    DateTime? updatedAt,
  }) =>
      ChatThread(
        id: id,
        title: title ?? this.title,
        systemInstruction: systemInstruction ?? this.systemInstruction,
        chatFamily: chatFamily ?? this.chatFamily,
        modelId: modelId ?? this.modelId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        systemInstruction,
        chatFamily,
        modelId,
        createdAt,
        updatedAt,
      ];
}
