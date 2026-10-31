import 'dart:math' as math;
import 'dart:ui' show Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfFontStyle;
import '../models/extracted_page_geometry.dart';
import 'reading_order_resolver.dart';

/// A reconstructed paragraph composed of one or more spatially and semantically unified text lines.
class ReconstructedParagraph {
  final String text;
  final int startPageIndex;
  final int endPageIndex;
  final Rect boundingBox;
  final double fontSize;
  final List<PdfFontStyle> fontStyles;
  final bool isBold;
  final bool isItalic;
  final int lineCount;
  final List<ExtractedTextLine> sourceLines;
  final bool startsWithIndent;
  final bool isDialogue;
  final bool isIsolated; // e.g. single line surrounded by large gaps

  const ReconstructedParagraph({
    required this.text,
    required this.startPageIndex,
    required this.endPageIndex,
    required this.boundingBox,
    required this.fontSize,
    required this.fontStyles,
    required this.isBold,
    required this.isItalic,
    required this.lineCount,
    required this.sourceLines,
    this.startsWithIndent = false,
    this.isDialogue = false,
    this.isIsolated = false,
  });
}

/// D2: Reconstructs coherent paragraphs from ordered text lines using spatial gaps,
/// indentations, punctuation continuity, and de-hyphenation.
class ParagraphReconstructor {
  /// Punctuation marks that signal sentence or paragraph completion.
  static final RegExp _sentenceTerminators = RegExp(r'[.!?…»”"][)\]"\s]*$');

  /// Dialogue openers: quotation marks, em-dash, guillemets.
  static final RegExp _dialogueOpeners = RegExp(r'^(["“‘«—\-]|--\s)');

  /// Reconstructs paragraphs across all pages of a document.
  static List<ReconstructedParagraph> reconstructDocument(
    List<PageReadingOrderResult> pageResults,
  ) {
    final allParagraphs = <ReconstructedParagraph>[];
    ReconstructedParagraphBuilder? currentBuilder;

    for (int pIdx = 0; pIdx < pageResults.length; pIdx++) {
      final pageResult = pageResults[pIdx];
      final lines = pageResult.orderedLines;
      if (lines.isEmpty) continue;

      // Filter out obvious running headers and footers to protect paragraph stitching
      final filteredLines = <ExtractedTextLine>[];
      for (final line in lines) {
        if (_isPageNumberOrRunningChrome(line)) {
          // If there's an ongoing builder, finish it before chrome
          if (currentBuilder != null && currentBuilder.lines.isNotEmpty) {
            allParagraphs.add(currentBuilder.build());
            currentBuilder = null;
          }
          // Chrome is preserved as its own single-line paragraph so classifier can handle it
          allParagraphs.add(
            ReconstructedParagraphBuilder(line).build(),
          );
        } else {
          filteredLines.add(line);
        }
      }

      if (filteredLines.isEmpty) continue;

      // Calculate the typical (modal) line height and line gap for this page
      final modalMetrics = _calculatePageLineMetrics(filteredLines);

      for (int i = 0; i < filteredLines.length; i++) {
        final line = filteredLines[i];

        if (currentBuilder == null) {
          currentBuilder = ReconstructedParagraphBuilder(line);
          continue;
        }

        final prevLine = currentBuilder.lastLine;
        final shouldBreak = _shouldBreakParagraph(
          prevLine: prevLine,
          currentLine: line,
          prevPage: prevLine.pageIndex,
          currentPage: line.pageIndex,
          modalLineGap: modalMetrics.modalGap,
          modalLineHeight: modalMetrics.modalHeight,
        );

        if (shouldBreak) {
          allParagraphs.add(currentBuilder.build());
          currentBuilder = ReconstructedParagraphBuilder(line);
        } else {
          currentBuilder.appendLine(line);
        }
      }
    }

    if (currentBuilder != null && currentBuilder.lines.isNotEmpty) {
      allParagraphs.add(currentBuilder.build());
    }

    return allParagraphs;
  }

  /// Reconstructs paragraphs for a single page in isolation.
  static List<ReconstructedParagraph> reconstructPage(
    PageReadingOrderResult pageResult,
  ) {
    return reconstructDocument([pageResult]);
  }

  /// Determines whether a new paragraph should begin between prevLine and currentLine.
  static bool _shouldBreakParagraph({
    required ExtractedTextLine prevLine,
    required ExtractedTextLine currentLine,
    required int prevPage,
    required int currentPage,
    required double modalLineGap,
    required double modalLineHeight,
  }) {
    // 1. Font size change: Headings or captions with distinct font sizes never merge into body text
    final fontDiff = (currentLine.fontSize - prevLine.fontSize).abs();
    if (fontDiff >= 1.5) {
      return true;
    }

    // 2. Bold / Italic transition: e.g. bold heading above plain text body
    if (prevLine.isBold != currentLine.isBold && fontDiff >= 0.8) {
      return true;
    }

    // 3. Dialogue check: If current line starts with dialogue quotation, start new paragraph
    final currentTrimmed = currentLine.text.trim();
    if (_dialogueOpeners.hasMatch(currentTrimmed)) {
      // If previous line completed a thought, definitely break
      if (_sentenceTerminators.hasMatch(prevLine.text.trim())) {
        return true;
      }
    }

    // 4. Same page vertical gap analysis
    if (prevPage == currentPage) {
      final verticalGap = currentLine.bounds.top - prevLine.bounds.bottom;

      // If gap is negative or very small, lines are overlapping or same baseline (handled by reading order)
      // If gap is noticeably larger than modal line spacing (e.g. > 1.4x), it's a paragraph break
      final threshold = math.max(modalLineGap * 1.45, 6.0);
      if (verticalGap > threshold) {
        return true;
      }

      // 5. First-line Indentation signal:
      // If current line starts noticeably further right than previous line (first-line indent)
      final indentDiff = currentLine.bounds.left - prevLine.bounds.left;
      if (indentDiff >= 9.0 && _sentenceTerminators.hasMatch(prevLine.text.trim())) {
        return true;
      }

      // 6. Right margin termination signal:
      // If previous line ended short (right edge is far from column width) and ended with punctuation
      final prevLineEndedPunctuation = _sentenceTerminators.hasMatch(prevLine.text.trim());
      final widthRatio = prevLine.bounds.width / math.max(currentLine.bounds.width, 1.0);
      if (prevLineEndedPunctuation && widthRatio < 0.75 && verticalGap >= modalLineGap * 0.9) {
        return true;
      }
    } else {
      // 7. Across page boundary:
      // If previous page ended with sentence-ending punctuation AND current page line starts capitalized, break
      final prevEndsSentence = _sentenceTerminators.hasMatch(prevLine.text.trim());
      final startsCapital = currentTrimmed.isNotEmpty &&
          currentTrimmed[0].toUpperCase() == currentTrimmed[0] &&
          currentTrimmed[0].toLowerCase() != currentTrimmed[0];

      if (prevEndsSentence && startsCapital) {
        return true;
      }

      // If previous line was a short heading or title
      if (prevLine.fontSize > 13.0 || prevLine.isBold) {
        return true;
      }
    }

    // Default: lines belong to the same continuing paragraph!
    return false;
  }

  /// Calculates modal line height and vertical gap between adjacent lines.
  static _LineMetrics _calculatePageLineMetrics(List<ExtractedTextLine> lines) {
    if (lines.length < 2) {
      return _LineMetrics(modalHeight: 12.0, modalGap: 4.0);
    }

    final heights = <double>[];
    final gaps = <double>[];

    for (int i = 0; i < lines.length - 1; i++) {
      final a = lines[i];
      final b = lines[i + 1];
      heights.add(a.bounds.height);

      final gap = b.bounds.top - a.bounds.bottom;
      if (gap > 0 && gap < 30) {
        gaps.add(gap);
      }
    }

    final modalHeight = heights.isNotEmpty ? _findMedian(heights) : 12.0;
    final modalGap = gaps.isNotEmpty ? _findMedian(gaps) : 4.0;

    return _LineMetrics(modalHeight: modalHeight, modalGap: modalGap);
  }

  static double _findMedian(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  /// Identifies obvious standalone page numbers or headers for isolating during paragraph joining.
  static bool _isPageNumberOrRunningChrome(ExtractedTextLine line) {
    final trimmed = line.text.trim();
    if (RegExp(r'^(page\s+\d+(\s+of\s+\d+)?|\d+)$', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    if (line.bounds.top < 65.0 && line.fontSize <= 9.0 && trimmed.length < 60) {
      return true;
    }
    return false;
  }
}

class _LineMetrics {
  final double modalHeight;
  final double modalGap;
  _LineMetrics({required this.modalHeight, required this.modalGap});
}

/// Helper class to accumulate text lines and build a unified ReconstructedParagraph.
class ReconstructedParagraphBuilder {
  final List<ExtractedTextLine> lines = [];

  ReconstructedParagraphBuilder(ExtractedTextLine initialLine) {
    lines.add(initialLine);
  }

  ExtractedTextLine get lastLine => lines.last;

  void appendLine(ExtractedTextLine line) {
    lines.add(line);
  }

  ReconstructedParagraph build() {
    if (lines.isEmpty) {
      throw StateError('Cannot build paragraph from empty lines');
    }

    final buffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final text = line.text.trim();

      if (i == 0) {
        buffer.write(text);
      } else {
        final prevText = lines[i - 1].text.trim();
        // De-hyphenation: if prev line ends with '-' preceded by a lowercase letter
        if (prevText.endsWith('-') &&
            prevText.length >= 2 &&
            RegExp(r'[a-z]-$').hasMatch(prevText) &&
            text.isNotEmpty &&
            RegExp(r'^[a-z]').hasMatch(text)) {
          // Remove trailing hyphen from buffer and append continuation without space
          final currentBufferStr = buffer.toString();
          buffer.clear();
          buffer.write(currentBufferStr.substring(0, currentBufferStr.length - 1));
          buffer.write(text);
        } else {
          buffer.write(' ');
          buffer.write(text);
        }
      }
    }

    // Compute bounding box spanning all lines
    double minLeft = lines.first.bounds.left;
    double minTop = lines.first.bounds.top;
    double maxRight = lines.first.bounds.right;
    double maxBottom = lines.first.bounds.bottom;

    for (final l in lines) {
      minLeft = math.min(minLeft, l.bounds.left);
      minTop = math.min(minTop, l.bounds.top);
      maxRight = math.max(maxRight, l.bounds.right);
      maxBottom = math.max(maxBottom, l.bounds.bottom);
    }

    final firstLine = lines.first;
    final isBold = lines.every((l) => l.isBold);
    final isItalic = lines.every((l) => l.isItalic);
    final fontStyles = firstLine.fontStyle;

    return ReconstructedParagraph(
      text: buffer.toString(),
      startPageIndex: firstLine.pageIndex,
      endPageIndex: lines.last.pageIndex,
      boundingBox: Rect.fromLTRB(minLeft, minTop, maxRight, maxBottom),
      fontSize: firstLine.fontSize,
      fontStyles: fontStyles,
      isBold: isBold,
      isItalic: isItalic,
      lineCount: lines.length,
      sourceLines: List.unmodifiable(lines),
      isDialogue: RegExp(r'^(["“‘«—\-]|--\s)').hasMatch(buffer.toString()),
      isIsolated: lines.length == 1,
    );
  }
}

