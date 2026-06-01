import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/assistant/data/repositories/secure_hf_token_repository.dart';
import 'package:minicrm/features/assistant/domain/repositories/hf_token_repository.dart';

final hfTokenRepositoryProvider = Provider<HfTokenRepository>((ref) {
  return SecureHfTokenRepository();
});

final hfTokenProvider = AsyncNotifierProvider<HfTokenController, String?>(
  HfTokenController.new,
);

class HfTokenController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    return ref.read(hfTokenRepositoryProvider).read();
  }

  Future<void> save(String token) async {
    final repo = ref.read(hfTokenRepositoryProvider);
    await repo.write(token);
    state = AsyncValue.data(token.trim().isEmpty ? null : token.trim());
  }

  Future<void> clear() async {
    await ref.read(hfTokenRepositoryProvider).clear();
    state = const AsyncValue.data(null);
  }
}
