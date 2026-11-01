import 'dart:ui' show Rect, Size;
import 'extracted_page_geometry.dart';

/// Represents a single text line recognized by the local OCR engine.
class OcrLine {
  final String text;
  final double confidence;
  final Rect box; // Normalized coordinates: left, top, width, height in [0, 1]

  const OcrLine({
    required this.text,
    required this.confidence,
    required this.box,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'confidence': confidence,
    'box': {
      'x': box.left,
      'y': box.top,
      'width': box.width,
      'height': box.height,
    },
  };

  factory OcrLine.fromJson(Map<String, dynamic> json) {
    final b = json['box'] as Map<String, dynamic>? ?? {};
    return OcrLine(
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      box: Rect.fromLTWH(
        (b['x'] as num?)?.toDouble() ?? 0.0,
        (b['y'] as num?)?.toDouble() ?? 0.0,
        (b['width'] as num?)?.toDouble() ?? 0.0,
        (b['height'] as num?)?.toDouble() ?? 0.0,
      ),
    );
  }
}

/// Represents the recognized OCR output for a single page.
class OcrPageResult {
  final String imagePath;
  final int width;
  final int height;
  final double durationMs;
  final List<OcrLine> lines;
  final String? error;

  const OcrPageResult({
    required this.imagePath,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.lines,
    this.error,
  });

  bool get hasError => error != null && error!.isNotEmpty;
  bool get isEmpty => lines.isEmpty;

  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'width': width,
    'height': height,
    'durationMs': durationMs,
    'lines': lines.map((l) => l.toJson()).toList(),
    if (error != null) 'error': error,
  };

  factory OcrPageResult.fromJson(Map<String, dynamic> json) {
    return OcrPageResult(
      imagePath: json['imagePath'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toDouble() ?? 0.0,
      lines: (json['lines'] as List<dynamic>? ?? [])
          .map((item) => OcrLine.fromJson(item as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
    );
  }

  /// Converts this OCR page result into the standard [ExtractedPageGeometry]
  /// used by the Digital Books layout and semantic reconstruction pipeline.
  ExtractedPageGeometry toExtractedPageGeometry({
    required int pageIndex,
    required Size pageSize,
  }) {
    var lineIdx = 0;
    final extractedLines = lines.map((ocrLine) {
      final absLeft = (ocrLine.box.left * pageSize.width).clamp(0.0, pageSize.width);
      final absTop = (ocrLine.box.top * pageSize.height).clamp(0.0, pageSize.height);
      final absWidth = (ocrLine.box.width * pageSize.width).clamp(0.0, pageSize.width - absLeft);
      final absHeight = (ocrLine.box.height * pageSize.height).clamp(0.0, pageSize.height - absTop);

      // Estimate approximate font size from line height
      final estFontSize = (absHeight * 0.80).clamp(8.0, 32.0);

      // Split into words for word-level geometry
      final wordsList = ocrLine.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final words = <ExtractedTextWord>[];
      if (wordsList.isNotEmpty && absWidth > 0) {
        final approxWordWidth = absWidth / wordsList.length;
        for (int wIdx = 0; wIdx < wordsList.length; wIdx++) {
          words.add(ExtractedTextWord(
            bounds: Rect.fromLTWH(
              absLeft + (wIdx * approxWordWidth),
              absTop,
              approxWordWidth * 0.9,
              absHeight,
            ),
            text: wordsList[wIdx],
          ));
        }
      }

      return ExtractedTextLine(
        bounds: Rect.fromLTWH(absLeft, absTop, absWidth, absHeight),
        text: ocrLine.text,
        fontSize: estFontSize,
        fontName: 'AppleVisionOCR',
        lineIndex: lineIdx++,
        pageIndex: pageIndex,
        words: words,
      );
    }).toList();

    return ExtractedPageGeometry(
      pageIndex: pageIndex,
      pageSize: pageSize,
      lines: extractedLines,
      images: const [],
      layerType: PageLayerType.nativeText,
      charCount: extractedLines.fold(0, (sum, l) => sum + l.text.length),
    );
  }
}
