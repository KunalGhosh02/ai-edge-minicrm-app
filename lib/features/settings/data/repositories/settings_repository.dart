import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  static const String _kSystemPrompt = 'assistant.system_prompt';
  static const String _kRagEnabled = 'assistant.rag_enabled';
  static const String _kEmbeddingModelPath = 'assistant.embedding_model_path';

  static const String defaultSystemPrompt =
      'You are MiniCRM, an on-device customer support assistant. '
      'Answer clearly and concisely using the provided context when available. '
      'If the context does not contain the answer, say you are not sure '
      'rather than guessing.';

  final SharedPreferences _prefs;

  String getSystemPrompt() {
    return _prefs.getString(_kSystemPrompt) ?? defaultSystemPrompt;
  }

  Future<void> setSystemPrompt(String value) async {
    await _prefs.setString(_kSystemPrompt, value);
  }

  Future<void> resetSystemPrompt() async {
    await _prefs.remove(_kSystemPrompt);
  }

  bool getRagEnabled() => _prefs.getBool(_kRagEnabled) ?? true;

  Future<void> setRagEnabled({required bool value}) async {
    await _prefs.setBool(_kRagEnabled, value);
  }

  String? getEmbeddingModelPath() => _prefs.getString(_kEmbeddingModelPath);

  Future<void> setEmbeddingModelPath(String? path) async {
    if (path == null) {
      await _prefs.remove(_kEmbeddingModelPath);
    } else {
      await _prefs.setString(_kEmbeddingModelPath, path);
    }
  }
}
