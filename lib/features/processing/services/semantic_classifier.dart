import 'dart:math' as math;
import '../models/semantic_reconstruction_models.dart';
import 'paragraph_reconstructor.dart';

/// D3: Classifies reconstructed paragraphs into semantic roles based on font metrics,
/// spatial positioning, styling, and inter-page repeating patterns.
class SemanticClassifier {
  /// Classifies a list of reconstructed paragraphs from a document.
  static List<SemanticReconstructedBlock> classifyDocument({
    required List<ReconstructedParagraph> paragraphs,
    required int totalPages,
    double defaultPageHeight = 792.0, // standard letter/A4
  }) {
    if (paragraphs.isEmpty) return [];

    // 1. Calculate document-wide typography baselines
    final bodyFontSize = _detectModalBodyFontSize(paragraphs);
    final bodyLeftMargin = _detectModalLeftMargin(paragraphs);

    // 2. Detect repeating header/footer patterns across pages
    final repeatingHeaders = _detectRepeatingTexts(
      paragraphs.where((p) => p.boundingBox.top < 85.0),
      minOccurrences: math.min(2, totalPages),
    );

    final repeatingFooters = _detectRepeatingTexts(
      paragraphs.where((p) => p.boundingBox.top > defaultPageHeight - 75.0),
      minOccurrences: math.min(2, totalPages),
    );

    final classifiedBlocks = <SemanticReconstructedBlock>[];

    for (final para in paragraphs) {
      final block = _classifyParagraph(
        para: para,
        bodyFontSize: bodyFontSize,
        bodyLeftMargin: bodyLeftMargin,
        pageHeight: defaultPageHeight,
        repeatingHeaders: repeatingHeaders,
        repeatingFooters: repeatingFooters,
      );
      classifiedBlocks.add(block);
    }

    return classifiedBlocks;
  }

  /// Classifies an individual paragraph.
  static SemanticReconstructedBlock _classifyParagraph({
    required ReconstructedParagraph para,
    required double bodyFontSize,
    required double bodyLeftMargin,
    required double pageHeight,
    required Set<String> repeatingHeaders,
    required Set<String> repeatingFooters,
  }) {
    final text = para.text.trim();
    final top = para.boundingBox.top;
    final bottom = para.boundingBox.bottom;
    final left = para.boundingBox.left;
    final fontSize = para.fontSize;
    final isBold = para.isBold;
    final isItalic = para.isItalic;
    final lineCount = para.lineCount;

    // A. Running Headers (top zone)
    if (top < 80.0) {
      if (repeatingHeaders.contains(text) ||
          (fontSize <= bodyFontSize && lineCount == 1 && text.length < 80)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.runningHeader,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }
    }

    // B. Footnotes (bottom region of page with smaller font size and index marker)
    if (top > pageHeight - 160.0 && fontSize < bodyFontSize * 0.95) {
      if (RegExp(r'^(\*|\d+[\.\)]|\[\d+\]|\(\d+\))\s+').hasMatch(text)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.footnote,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }
    }

    // C. Page Numbers and Footers (bottom zone)
    if (bottom > pageHeight - 65.0 || top > pageHeight - 70.0) {
      if (RegExp(r'^(page\s+\d+(\s+of\s+\d+)?|\d+|-\s*\d+\s*-)$', caseSensitive: false).hasMatch(text)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.pageNumber,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.98,
        );
      }
      if (repeatingFooters.contains(text) || (fontSize <= bodyFontSize && lineCount <= 2)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.runningFooter,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.90,
        );
      }
    }

    // D. Captions (proximity text starting with figure/diagram keywords or small italic)
    final isCaptionKeyword = RegExp(
      r'^(figure|fig\.|gambar|diagram|tabel|table|photo|denah)\s+([0-9ivxlcdm\.]+)?:?',
      caseSensitive: false,
    ).hasMatch(text);

    if (isCaptionKeyword && lineCount <= 3) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.caption,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        captionText: text,
        confidence: 0.95,
      );
    }

    if (isItalic && fontSize <= bodyFontSize && lineCount <= 2 && isCaptionKeyword) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.caption,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.85,
      );
    }

    // E. Block Quotes (significant left indent or italicized long quotation)
    final hasIndent = left >= bodyLeftMargin + 16.0;
    if (hasIndent && (isItalic || para.isDialogue || text.startsWith('"'))) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.quote,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.88,
      );
    }

    // F. Headings (H1, H2, H3)
    // Only short, prominent paragraphs qualify as headings (not long text blocks)
    if (lineCount <= 3 && text.length < 160) {
      final fontRatio = fontSize / bodyFontSize;

      // H1: Prominent font (>= 1.45x body size), or Chapter pattern + bold
      final isChapterPattern = RegExp(
        r'^(chapter|bab|bagian|part|book|act)\s+([0-9ivxlcdm]+|[a-z]+)',
        caseSensitive: false,
      ).hasMatch(text);

      if (fontRatio >= 1.45 || (fontRatio >= 1.25 && isBold && isChapterPattern)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading1,
          headingLevel: 1,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }

      // H2: Section heading (1.2x - 1.45x body size, or bold with Roman/Section numbering)
      final isSectionPattern = RegExp(
        r'^([0-9ivxlcdm]+\.|\bsection\b|\bhukum\b)',
        caseSensitive: false,
      ).hasMatch(text);

      if ((fontRatio >= 1.22 && isBold) || (isBold && isSectionPattern)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading2,
          headingLevel: 2,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.90,
        );
      }

      // H3: Sub-section heading (bold and slightly above or equal to body size with punctuation or title case)
      if (fontRatio >= 1.05 && isBold) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading3,
          headingLevel: 3,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.85,
        );
      }
    }

    // G. Body Paragraph: Typical body font size within normal variation
    final fontDelta = (fontSize - bodyFontSize).abs();
    if (fontDelta <= 1.5) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.bodyParagraph,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.95,
      );
    }

    // H. Fallback: If ambiguous or unusual typography, mark as unknown
    return SemanticReconstructedBlock(
      type: SemanticBlockType.unknown,
      text: text,
      sourcePageIndex: para.startPageIndex,
      sourceBounds: para.boundingBox,
      confidence: 0.50,
    );
  }

  /// Calculates the modal (most frequent) body font size across paragraphs.
  static double _detectModalBodyFontSize(List<ReconstructedParagraph> paragraphs) {
    if (paragraphs.isEmpty) return 11.0;

    final fontCounts = <double, int>{};
    for (final p in paragraphs) {
      // Weight font size by character length
      final rounded = (p.fontSize * 2).round() / 2.0; // round to nearest 0.5
      fontCounts[rounded] = (fontCounts[rounded] ?? 0) + p.text.length;
    }

    double bestSize = 11.0;
    int maxWeight = 0;
    fontCounts.forEach((size, weight) {
      if (weight > maxWeight) {
        maxWeight = weight;
        bestSize = size;
      }
    });

    return bestSize;
  }

  /// Calculates the modal left margin for body text.
  static double _detectModalLeftMargin(List<ReconstructedParagraph> paragraphs) {
    if (paragraphs.isEmpty) return 50.0;

    final leftMargins = paragraphs.map((p) => p.boundingBox.left).toList()..sort();
    final mid = leftMargins.length ~/ 2;
    return leftMargins[mid];
  }

  /// Identifies strings that repeat verbatim across multiple pages.
  static Set<String> _detectRepeatingTexts(
    Iterable<ReconstructedParagraph> candidates, {
    required int minOccurrences,
  }) {
    final pageOccurrences = <String, Set<int>>{};
    for (final c in candidates) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      pageOccurrences.putIfAbsent(t, () => {}).add(c.startPageIndex);
    }

    final repeating = <String>{};
    pageOccurrences.forEach((text, pages) {
      if (pages.length >= minOccurrences) {
        repeating.add(text);
      }
    });

    return repeating;
  }
}
