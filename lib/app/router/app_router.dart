import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/features/assistant/presentation/screens/assistant_screen.dart';
import 'package:minicrm/features/assistant/presentation/screens/chats_list_screen.dart';
import 'package:minicrm/features/assistant/presentation/screens/models_screen.dart';
import 'package:minicrm/features/cloud/presentation/screens/cloud_setup_screen.dart';
import 'package:minicrm/features/cloud/presentation/screens/customer_chat_screen.dart';
import 'package:minicrm/features/context/presentation/screens/context_screen.dart';
import 'package:minicrm/features/home/presentation/screens/home_screen.dart';
import 'package:minicrm/features/settings/presentation/screens/system_prompt_screen.dart';

abstract final class AppRoute {
  static const String home = '/';
  static const String assistant = '/assistant';
  static const String models = '/models';
  static const String context = '/context';
  static const String systemPrompt = '/system-prompt';
  static const String cloudSetup = '/cloud-setup';

  static String assistantChat(String threadId) => '/assistant/chat/$threadId';

  static String customerChat(String customerId) =>
      '/cloud-setup/sessions/$customerId';
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
        path: AppRoute.models,
        name: 'models',
        builder: (context, state) => const ModelsScreen(),
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
      GoRoute(
        path: AppRoute.cloudSetup,
        name: 'cloud-setup',
        builder: (context, state) => const CloudSetupScreen(),
        routes: [
          GoRoute(
            path: 'sessions/:customerId',
            name: 'customer-chat',
            builder: (context, state) => CustomerChatScreen(
              customerId: state.pathParameters['customerId']!,
            ),
          ),
        ],
      ),
    ],
  );
});
