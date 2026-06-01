import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:minicrm/features/assistant/domain/repositories/hf_token_repository.dart';

class SecureHfTokenRepository implements HfTokenRepository {
  SecureHfTokenRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'hf_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final v = await _storage.read(key: _key);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> write(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(key: _key, value: trimmed);
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
