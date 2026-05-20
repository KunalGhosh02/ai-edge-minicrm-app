import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfExtractionResult {
  const PdfExtractionResult({
    required this.text,
    required this.pageCount,
  });

  final String text;
  final int pageCount;
}

class PdfExtractionException implements Exception {
  const PdfExtractionException(this.message);

  final String message;

  @override
  String toString() => 'PdfExtractionException: $message';
}

class PdfTextExtractorService {
  const PdfTextExtractorService();

  Future<PdfExtractionResult> extractFromPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw const PdfExtractionException('PDF file not found');
    }
    final bytes = await file.readAsBytes();
    return compute(_extract, bytes);
  }

  Future<PdfExtractionResult> extractFromBytes(Uint8List bytes) =>
      compute(_extract, bytes);
}

PdfExtractionResult _extract(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(document);
    final raw = extractor.extractText();
    final cleaned = _normalise(raw);
    return PdfExtractionResult(
      text: cleaned,
      pageCount: document.pages.count,
    );
  } finally {
    document.dispose();
  }
}

String _normalise(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .toList();
  final buf = StringBuffer();
  var blankRun = 0;
  for (final line in lines) {
    if (line.isEmpty) {
      blankRun++;
      if (blankRun <= 1) buf.writeln();
      continue;
    }
    blankRun = 0;
    buf.writeln(line);
  }
  return buf.toString().trim();
}
