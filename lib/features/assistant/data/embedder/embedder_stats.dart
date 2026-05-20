class EmbedderStats {
  const EmbedderStats({
    required this.count,
    required this.totalMs,
    required this.tokenizeMs,
    required this.invokeMs,
    required this.postMs,
    required this.minMs,
    required this.maxMs,
    required this.p50InvokeMs,
    required this.p95InvokeMs,
  });

  final int count;
  final int totalMs;
  final int tokenizeMs;
  final int invokeMs;
  final int postMs;
  final int minMs;
  final int maxMs;
  final int p50InvokeMs;
  final int p95InvokeMs;

  double get avgMs => count == 0 ? 0 : totalMs / count;
  double get avgTokenizeMs => count == 0 ? 0 : tokenizeMs / count;
  double get avgInvokeMs => count == 0 ? 0 : invokeMs / count;
  double get avgPostMs => count == 0 ? 0 : postMs / count;
}
