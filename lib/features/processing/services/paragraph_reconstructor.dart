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
  final bool isOrderedList;
  final bool isUnorderedList;
  final bool isCopyright;
  final bool isCaption;

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
    this.isOrderedList = false,
    this.isUnorderedList = false,
    this.isCopyright = false,
    this.isCaption = false,
  });
}

/// D2: Reconstructs coherent paragraphs from ordered text lines using spatial gaps,
/// indentations, punctuation continuity, and de-hyphenation.
class ParagraphReconstructor {
  /// Punctuation marks that signal sentence or paragraph completion.
  static final RegExp _sentenceTerminators = RegExp(r'[.!?…»”"][)\]"\s]*$');

  /// Dialogue openers: quotation marks, em-dash, guillemets.
  static final RegExp _dialogueOpeners = RegExp(r'^(["“‘«—\-]|--\s)');

  /// Ordered list items: "1.", "1)", "(1)", "a.", "i.", etc.
  static final RegExp _orderedListRegex =
      RegExp(r'^(\d+[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]+\))\s+');

  /// Unordered list items: bullet, dash, asterisk, en/em-dash
  static final RegExp _unorderedListRegex =
      RegExp(r'^([•\-\*–—]|[\u2022\u2023\u25E6\u2043\u2219])\s+');

  /// Copyright, imprint, and bibliographic metadata prefixes
  static final RegExp _copyrightMetaRegex = RegExp(
    r'^(hak cipta|all rights reserved|dilarang memfotokopi|katalog dalam terbitan|kdt|isbn|diterbitkan oleh|cetakan ke|desain sampul|penata letak|penerjemah|editor:|pemeriksa aksara|ilustrasi:)\b',
    caseSensitive: false,
  );

  /// Captions (figure, image, diagram, table)
  static final RegExp _captionRegex = RegExp(
    r'^(figure|fig\.|gambar|diagram|tabel|table|photo|foto|denah)\s+([0-9ivxlcdm\.]+)?:?',
    caseSensitive: false,
  );

  /// Chapter header markers
  static final RegExp _chapterHeaderRegex = RegExp(
    r'^(chapter|bab|bagian|part|act|hukum)\s+([0-9ivxlcdm]+|[a-z]+)',
    caseSensitive: false,
  );

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
    final currentTrimmed = currentLine.text.trim();
    final prevTrimmed = prevLine.text.trim();

    // 1. List Item checks (Ordered and Unordered):
    // A line starting with 1., 2., a., •, -, * always begins a distinct list item!
    if (_orderedListRegex.hasMatch(currentTrimmed) ||
        _unorderedListRegex.hasMatch(currentTrimmed)) {
      return true;
    }
    // If previous line was a list item and either finished or has vertical separation
    if (_orderedListRegex.hasMatch(prevTrimmed) ||
        _unorderedListRegex.hasMatch(prevTrimmed)) {
      if (_sentenceTerminators.hasMatch(prevTrimmed) ||
          currentLine.bounds.top - prevLine.bounds.bottom >= modalLineGap * 0.9) {
        return true;
      }
    }

    // 2. Copyright, Publishing & Bibliographic Metadata isolation:
    if (_copyrightMetaRegex.hasMatch(currentTrimmed) ||
        _copyrightMetaRegex.hasMatch(prevTrimmed)) {
      return true;
    }

    // 3. Caption isolation (Figure, Gambar, Tabel, Diagram):
    if (_captionRegex.hasMatch(currentTrimmed) ||
        _captionRegex.hasMatch(prevTrimmed)) {
      return true;
    }

    // 4. Chapter markers and prominent standalone title headings:
    if (_chapterHeaderRegex.hasMatch(currentTrimmed) ||
        _chapterHeaderRegex.hasMatch(prevTrimmed)) {
      return true;
    }

    final isPrevAllCapTitle = prevTrimmed.length <= 60 &&
        prevTrimmed == prevTrimmed.toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(prevTrimmed) &&
        !RegExp(r'^\d+$').hasMatch(prevTrimmed);
    final isCurrAllCapTitle = currentTrimmed.length <= 60 &&
        currentTrimmed == currentTrimmed.toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(currentTrimmed) &&
        !RegExp(r'^\d+$').hasMatch(currentTrimmed);
    if (isPrevAllCapTitle || isCurrAllCapTitle) {
      return true;
    }

    // 5. Significant Left Margin Indentation or Block Quote offset:
    final leftDiff = (currentLine.bounds.left - prevLine.bounds.left).abs();
    if (leftDiff >= 16.0) {
      return true;
    }

    // 6. Font size change: Headings or captions with distinct font sizes never merge into body text
    final fontDiff = (currentLine.fontSize - prevLine.fontSize).abs();
    if (fontDiff >= 1.5) {
      return true;
    }

    // 7. Bold / Italic transition: e.g. bold heading above plain text body
    if (prevLine.isBold != currentLine.isBold && fontDiff >= 0.8) {
      return true;
    }

    // 8. Dialogue check: If current line starts with dialogue quotation, start new paragraph
    if (_dialogueOpeners.hasMatch(currentTrimmed)) {
      if (_sentenceTerminators.hasMatch(prevTrimmed)) {
        return true;
      }
    }

    // 9. Same page vertical gap analysis
    if (prevPage == currentPage) {
      final verticalGap = currentLine.bounds.top - prevLine.bounds.bottom;

      // If gap is noticeably larger than modal line spacing (e.g. > 1.35x), it's a paragraph break
      final threshold = math.max(modalLineGap * 1.35, 5.5);
      if (verticalGap > threshold) {
        return true;
      }

      // First-line Indentation signal:
      final indentDiff = currentLine.bounds.left - prevLine.bounds.left;
      if (indentDiff >= 8.0 && _sentenceTerminators.hasMatch(prevTrimmed)) {
        return true;
      }

      // Right margin termination signal:
      final prevLineEndedPunctuation = _sentenceTerminators.hasMatch(prevTrimmed);
      final widthRatio = prevLine.bounds.width / math.max(currentLine.bounds.width, 1.0);
      if (prevLineEndedPunctuation && widthRatio < 0.80 && verticalGap >= modalLineGap * 0.85) {
        return true;
      }
    } else {
      // 10. Across page boundary:
      if (prevLine.fontSize > 13.0 || prevLine.isBold) {
        return true;
      }

      final isDialogue = _dialogueOpeners.hasMatch(currentTrimmed);
      final indentDiff = currentLine.bounds.left - prevLine.bounds.left;
      final hasFirstLineIndent = indentDiff >= 8.0;

      if (isDialogue || hasFirstLineIndent) {
        return true;
      }

      final prevEndsSentence = _sentenceTerminators.hasMatch(prevTrimmed);
      final startsFarDown = currentLine.bounds.top > 120.0;
      if (prevEndsSentence && startsFarDown) {
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

    final fullText = buffer.toString().trim();

    return ReconstructedParagraph(
      text: fullText,
      startPageIndex: firstLine.pageIndex,
      endPageIndex: lines.last.pageIndex,
      boundingBox: Rect.fromLTRB(minLeft, minTop, maxRight, maxBottom),
      fontSize: firstLine.fontSize,
      fontStyles: fontStyles,
      isBold: isBold,
      isItalic: isItalic,
      lineCount: lines.length,
      sourceLines: List.unmodifiable(lines),
      isDialogue: RegExp(r'^(["“‘«—\-]|--\s)').hasMatch(fullText),
      isIsolated: lines.length == 1,
      isOrderedList: ParagraphReconstructor._orderedListRegex.hasMatch(fullText),
      isUnorderedList: ParagraphReconstructor._unorderedListRegex.hasMatch(fullText),
      isCopyright: ParagraphReconstructor._copyrightMetaRegex.hasMatch(fullText) ||
          RegExp(r'\b(isbn|katalog dalam terbitan|kdt)\b', caseSensitive: false).hasMatch(fullText),
      isCaption: ParagraphReconstructor._captionRegex.hasMatch(fullText),
    );
  }
}

