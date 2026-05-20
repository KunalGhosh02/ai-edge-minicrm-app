import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/service/foreground_assistant_service.dart';
import 'package:minicrm/features/assistant/domain/repositories/assistant_service.dart';

final assistantServiceProvider = Provider<AssistantService>((ref) {
  final service = ForegroundAssistantService();
  ref.onDispose(service.dispose);
  return service;
});
