import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/features/assistant/presentation/screens/assistant_screen.dart';
import 'package:minicrm/features/assistant/presentation/screens/chats_list_screen.dart';
import 'package:minicrm/features/context/presentation/screens/context_screen.dart';
import 'package:minicrm/features/home/presentation/screens/home_screen.dart';
import 'package:minicrm/features/settings/presentation/screens/system_prompt_screen.dart';

abstract final class AppRoute {
  static const String home = '/';
  static const String assistant = '/assistant';
  static const String context = '/context';
  static const String systemPrompt = '/system-prompt';

  static String assistantChat(String threadId) => '/assistant/chat/$threadId';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.home,
    routes: [
      GoRoute(
        path: AppRoute.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoute.assistant,
        name: 'assistant',
        builder: (context, state) => const ChatsListScreen(),
        routes: [
          GoRoute(
            path: 'chat/:threadId',
            name: 'assistant-chat',
            builder: (context, state) => AssistantScreen(
              threadId: state.pathParameters['threadId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.context,
        name: 'context',
        builder: (context, state) => const ContextScreen(),
      ),
      GoRoute(
        path: AppRoute.systemPrompt,
        name: 'system-prompt',
        builder: (context, state) => const SystemPromptScreen(),
      ),
    ],
  );
});
