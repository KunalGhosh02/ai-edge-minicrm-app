import 'package:equatable/equatable.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';

enum ChatChannel { local, cloud }

class ChatTurnHistory extends Equatable {
  const ChatTurnHistory({required this.role, required this.text});

  final String role;
  final String text;

  @override
  List<Object?> get props => [role, text];
}

sealed class ChatEvent extends Equatable {
  const ChatEvent({
    required this.threadId,
    required this.channel,
  });

  final String threadId;
  final ChatChannel channel;

  @override
  List<Object?> get props => [threadId, channel];
}

final class UserMessageSubmitted extends ChatEvent {
  const UserMessageSubmitted({
    required super.threadId,
    required this.message,
    super.channel = ChatChannel.local,
    this.replayHistory = const [],
    this.systemInstruction,
    this.chatFamily = 'general',
    this.thinkingEnabled = true,
  });

  final AssistantMessage message;
  final List<ChatTurnHistory> replayHistory;
  final String? systemInstruction;
  final String chatFamily;
  final bool thinkingEnabled;

  @override
  List<Object?> get props => [
        threadId,
        channel,
        message,
        replayHistory,
        systemInstruction,
        chatFamily,
        thinkingEnabled,
      ];
}

final class AssistantStarted extends ChatEvent {
  const AssistantStarted({
    required super.threadId,
    required this.messageId,
    super.channel = ChatChannel.local,
  });

  final String messageId;

  @override
  List<Object?> get props => [threadId, channel, messageId];
}

final class AssistantToken extends ChatEvent {
  const AssistantToken({
    required super.threadId,
    required this.messageId,
    required this.token,
    super.channel = ChatChannel.local,
  });

  final String messageId;
  final String token;

  @override
  List<Object?> get props => [threadId, channel, messageId, token];
}

final class AssistantThinkingToken extends ChatEvent {
  const AssistantThinkingToken({
    required super.threadId,
    required this.messageId,
    required this.token,
    super.channel = ChatChannel.local,
  });

  final String messageId;
  final String token;

  @override
  List<Object?> get props => [threadId, channel, messageId, token];
}

final class AssistantCompleted extends ChatEvent {
  const AssistantCompleted({
    required super.threadId,
    required this.message,
    super.channel = ChatChannel.local,
  });

  final AssistantMessage message;

  @override
  List<Object?> get props => [threadId, channel, message];
}

final class AssistantFailed extends ChatEvent {
  const AssistantFailed({
    required super.threadId,
    required this.error,
    this.messageId,
    super.channel = ChatChannel.local,
  });

  final String? messageId;
  final String error;

  @override
  List<Object?> get props => [threadId, channel, messageId, error];
}
