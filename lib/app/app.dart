import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/app/router/app_router.dart';
import 'package:minicrm/app/theme/app_theme.dart';

class MiniCrmApp extends ConsumerWidget {
  const MiniCrmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'MiniCRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) => WithForegroundTask(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
