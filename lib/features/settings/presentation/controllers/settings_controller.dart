import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/settings/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final settingsRepositoryProvider = FutureProvider<SettingsRepository>(
  (ref) async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return SettingsRepository(prefs);
  },
);

class AssistantSettings extends Equatable {
  const AssistantSettings({
    required this.systemPrompt,
    required this.ragEnabled,
  });

  final String systemPrompt;
  final bool ragEnabled;

  AssistantSettings copyWith({String? systemPrompt, bool? ragEnabled}) {
    return AssistantSettings(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      ragEnabled: ragEnabled ?? this.ragEnabled,
    );
  }

  @override
  List<Object?> get props => [systemPrompt, ragEnabled];
}

class SettingsController extends AsyncNotifier<AssistantSettings> {
  SettingsRepository? _repo;

  @override
  Future<AssistantSettings> build() async {
    _repo = await ref.watch(settingsRepositoryProvider.future);
    return AssistantSettings(
      systemPrompt: _repo!.getSystemPrompt(),
      ragEnabled: _repo!.getRagEnabled(),
    );
  }

  Future<void> updateSystemPrompt(String value) async {
    final repo = _repo;
    if (repo == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await repo.resetSystemPrompt();
    } else {
      await repo.setSystemPrompt(trimmed);
    }
    final next = repo.getSystemPrompt();
    state = AsyncData(state.value!.copyWith(systemPrompt: next));
  }

  Future<void> resetSystemPrompt() async {
    final repo = _repo;
    if (repo == null) return;
    await repo.resetSystemPrompt();
    state = AsyncData(
      state.value!.copyWith(systemPrompt: SettingsRepository.defaultSystemPrompt),
    );
  }

  Future<void> setRagEnabled({required bool enabled}) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.setRagEnabled(value: enabled);
    state = AsyncData(state.value!.copyWith(ragEnabled: enabled));
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AssistantSettings>(
  SettingsController.new,
);
