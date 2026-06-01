import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/domain/events/chat_event.dart';
import 'package:rxdart/subjects.dart';

class ChatEventBus {
  ChatEventBus() : _subject = PublishSubject<ChatEvent>();

  final PublishSubject<ChatEvent> _subject;

  Stream<ChatEvent> get events => _subject.stream;

  void publish(ChatEvent event) {
    if (_subject.isClosed) return;
    _subject.add(event);
  }

  Future<void> dispose() => _subject.close();
}

final chatEventBusProvider = Provider<ChatEventBus>((ref) {
  final bus = ChatEventBus();
  ref.onDispose(bus.dispose);
  return bus;
});
