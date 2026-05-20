import 'package:flutter/material.dart';
import 'package:minicrm/features/assistant/domain/entities/assistant_status.dart';

class AssistantStatusBanner extends StatelessWidget {
  const AssistantStatusBanner({required this.status, super.key});

  final AssistantStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, color) = _describe(theme);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          if (status is AssistantDownloading)
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                value: (status as AssistantDownloading).percent / 100,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }

  (IconData, String, Color) _describe(ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (status) {
      AssistantIdle() => (
          Icons.cloud_off_outlined,
          'Assistant not running',
          scheme.onSurfaceVariant,
        ),
      AssistantDownloading(
        :final percent,
        :final receivedBytes,
        :final totalBytes,
      ) =>
        (
          Icons.cloud_download_outlined,
          _downloadLabel(percent, receivedBytes, totalBytes),
          scheme.primary,
        ),
      AssistantLoading() => (
          Icons.memory,
          'Loading model into memory…',
          scheme.primary,
        ),
      AssistantReady() => (
          Icons.check_circle_outline,
          'Ready (foreground worker running)',
          scheme.tertiary,
        ),
      AssistantGenerating() => (
          Icons.auto_awesome,
          'Generating…',
          scheme.primary,
        ),
      AssistantError(:final message) => (
          Icons.error_outline,
          message,
          scheme.error,
        ),
    };
  }

  String _downloadLabel(int percent, int? received, int? total) {
    if (received == null || total == null || total <= 0) {
      return 'Downloading model… $percent%';
    }
    return 'Downloading… $percent% '
        '(${_humanBytes(received)} / ${_humanBytes(total)})';
  }

  String _humanBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
