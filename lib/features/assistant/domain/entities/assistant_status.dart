import 'package:equatable/equatable.dart';

sealed class AssistantStatus extends Equatable {
  const AssistantStatus();

  @override
  List<Object?> get props => const [];
}

final class AssistantIdle extends AssistantStatus {
  const AssistantIdle();
}

final class AssistantDownloading extends AssistantStatus {
  const AssistantDownloading({
    required this.percent,
    this.receivedBytes,
    this.totalBytes,
  });

  final int percent;
  final int? receivedBytes;
  final int? totalBytes;

  @override
  List<Object?> get props => [percent, receivedBytes, totalBytes];
}

final class AssistantLoading extends AssistantStatus {
  const AssistantLoading();
}

final class AssistantReady extends AssistantStatus {
  const AssistantReady();
}

final class AssistantGenerating extends AssistantStatus {
  const AssistantGenerating();
}

final class AssistantError extends AssistantStatus {
  const AssistantError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
