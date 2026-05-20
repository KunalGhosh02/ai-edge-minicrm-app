import 'package:objectbox/objectbox.dart';

@Entity()
class ChatThreadBox {
  ChatThreadBox({
    required this.threadId,
    required this.title,
    required this.systemInstruction,
    required this.chatFamily,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.modelId,
    this.id = 0,
  });

  @Id()
  int id;

  @Index(type: IndexType.value)
  @Unique()
  String threadId;

  String title;

  String systemInstruction;

  String chatFamily;

  String? modelId;

  int createdAtMs;

  int updatedAtMs;
}

@Entity()
class ChatMessageBox {
  ChatMessageBox({
    required this.messageId,
    required this.threadId,
    required this.role,
    required this.text,
    required this.createdAtMs,
    this.thinking = '',
    this.id = 0,
  });

  @Id()
  int id;

  @Index(type: IndexType.value)
  @Unique()
  String messageId;

  @Index(type: IndexType.value)
  String threadId;

  /// 0 = user, 1 = assistant
  int role;

  String text;

  String thinking;

  int createdAtMs;
}
