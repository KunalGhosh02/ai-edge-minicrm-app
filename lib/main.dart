import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await FlutterGemma.initialize();
  try {
    await Firebase.initializeApp();
  } on Object catch (e) {
    debugPrint('[main] Firebase.initializeApp skipped: $e');
  }
  runApp(
    const ProviderScope(
      child: MiniCrmApp(),
    ),
  );
}
