import 'package:minicrm/features/assistant/domain/entities/assistant_message.dart';
import 'package:minicrm/features/assistant/domain/entities/chat_thread.dart';
import 'package:minicrm/features/assistant/domain/entities/model_preset.dart';

abstract interface class ChatHistoryRepository {
  Stream<List<ChatThread>> watchThreads();

  Stream<List<AssistantMessage>> watchMessages(String threadId);

  Future<List<ChatThread>> listThreads();

  Future<ChatThread?> getThread(String threadId);

  Future<ChatThread> createThread({
    required String title,
    required String systemInstruction,
    required ChatModelFamily chatFamily,
    String? modelId,
  });

  Future<void> updateThread(ChatThread thread);

  Future<void> deleteThread(String threadId);

  Future<List<AssistantMessage>> getMessages(String threadId);

  Future<void> appendMessage({
    required String threadId,
    required AssistantMessage message,
  });

  Future<void> upsertMessage({
    required String threadId,
    required AssistantMessage message,
  });
}
