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

    final detectedMaxY = paragraphs
        .map((p) => p.boundingBox.bottom)
        .reduce(math.max);
    final effectivePageHeight = (defaultPageHeight > 0 &&
            (defaultPageHeight - detectedMaxY).abs() < 180)
        ? defaultPageHeight
        : math.max(defaultPageHeight, detectedMaxY + 20.0);

    // 1. Calculate document-wide typography baselines
    final bodyFontSize = _detectModalBodyFontSize(paragraphs);
    final bodyLeftMargin = _detectModalLeftMargin(paragraphs);

    final headerZoneThreshold = math.min(65.0, effectivePageHeight * 0.10);
    final footerZoneThreshold = math.max(
      effectivePageHeight - 75.0,
      effectivePageHeight * 0.88,
    );

    // 2. Detect repeating header/footer patterns across pages
    final repeatingHeaders = _detectRepeatingTexts(
      paragraphs.where((p) => p.boundingBox.top <= headerZoneThreshold),
      minOccurrences: math.min(2, totalPages),
    );

    final repeatingFooters = _detectRepeatingTexts(
      paragraphs.where((p) => p.boundingBox.bottom >= footerZoneThreshold),
      minOccurrences: math.min(2, totalPages),
    );

    final classifiedBlocks = <SemanticReconstructedBlock>[];

    for (final para in paragraphs) {
      final block = _classifyParagraph(
        para: para,
        bodyFontSize: bodyFontSize,
        bodyLeftMargin: bodyLeftMargin,
        pageHeight: effectivePageHeight,
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
    final headerThreshold = math.min(65.0, pageHeight * 0.10);
    if (top <= headerThreshold) {
      final isStandalonePageNum = RegExp(
        r'^(page\s+\d+(\s+of\s+\d+)?|\d+|-\s*\d+\s*|hal\.?\s*\d+|[ivxlcdm]+)$',
        caseSensitive: false,
      ).hasMatch(text);
      if (isStandalonePageNum) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.pageNumber,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.98,
        );
      }

      final isAllUpperShort = text.length <= 50 &&
          text == text.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(text) &&
          !text.endsWith(',') &&
          !text.endsWith(';');

      if (repeatingHeaders.contains(text) || isAllUpperShort) {
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
    final footnoteThreshold = pageHeight - 160.0;
    if (top > footnoteThreshold && fontSize < bodyFontSize * 0.95) {
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
    final footerThreshold = math.max(pageHeight - 75.0, pageHeight * 0.88);
    if (bottom >= footerThreshold || top >= footerThreshold) {
      final isStandalonePageNum = RegExp(
        r'^(page\s+\d+(\s+of\s+\d+)?|\d+|-\s*\d+\s*|hal\.?\s*\d+|[ivxlcdm]+)$',
        caseSensitive: false,
      ).hasMatch(text);
      if (isStandalonePageNum) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.pageNumber,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.98,
        );
      }
      if (repeatingFooters.contains(text) ||
          (fontSize <= bodyFontSize && lineCount <= 2 && text.length <= 60)) {
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
      r'^(figure|fig\.|gambar|diagram|tabel|table|photo|foto|denah)\s+([0-9ivxlcdm\.]+)?:?',
      caseSensitive: false,
    ).hasMatch(text);

    if ((para.isCaption || isCaptionKeyword) && lineCount <= 3) {
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

    // E. Ordered and Unordered Lists
    final fontRatio = fontSize / bodyFontSize;
    final isLikelyHeading = (isBold && fontRatio >= 1.10) ||
        fontRatio >= 1.25 ||
        (isBold && lineCount == 1 && text.length < 100);

    final orderedMatch = RegExp(r'^(\d+[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]+\))\s+').firstMatch(text);
    if ((para.isOrderedList || orderedMatch != null) && !isLikelyHeading) {
      final marker = orderedMatch?.group(1) ?? '';
      return SemanticReconstructedBlock(
        type: SemanticBlockType.orderedListItem,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        metadata: {'listMarker': marker},
        confidence: 0.95,
      );
    }

    final unorderedMatch = RegExp(r'^([•\-\*–—]|[\u2022\u2023\u25E6\u2043\u2219])\s+').firstMatch(text);
    if (para.isUnorderedList || unorderedMatch != null) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.unorderedListItem,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        metadata: {'listMarker': '•'},
        confidence: 0.95,
      );
    }

    // F. Copyright, Imprint, and Publishing Information
    if (para.isCopyright ||
        RegExp(
          r'(hak cipta|all rights reserved|dilarang memfotokopi|katalog dalam terbitan|kdt|isbn\b|cetakan ke-|desain sampul|penata letak|penerjemah|editor:|diterbitkan oleh|penerbit\b)',
          caseSensitive: false,
        ).hasMatch(text)) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.copyrightBlock,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.96,
      );
    }

    // G. Block Quotes (significant left indent or italicized long quotation)
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

    // H. Headings (H1, H2, H3, Document Title)
    // Supports both font-metric scaling in digital PDFs and casing/spatial patterns in scanned OCR
    if (lineCount <= 3 && text.length < 160) {
      final fontRatio = fontSize / bodyFontSize;

      final isChapterPattern = RegExp(
        r'^(chapter|bab|bagian|part|book|act|hukum)\s+([0-9ivxlcdm]+|[a-z]+)',
        caseSensitive: false,
      ).hasMatch(text);

      final isNamedChapter = RegExp(
        r'^(prolog|prologue|epilog|epilogue|introduction|pengantar|prakata|kata pengantar|pendahuluan|kesimpulan|conclusion|daftar isi|ucapan terima kasih|tentang penulis)\b',
        caseSensitive: false,
      ).hasMatch(text);

      final isRomanChapter = lineCount == 1 &&
          top < pageHeight * 0.70 &&
          RegExp(
            r'^(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII|XIII|XIV|XV|XVI|XVII|XVIII|XIX|XX)$',
          ).hasMatch(text);

      final isAllCapTitle = lineCount <= 2 &&
          text.length <= 60 &&
          text == text.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(text) &&
          !RegExp(r'^\d+$').hasMatch(text);

      final isProminentTitle = fontRatio >= 1.25 &&
          isBold &&
          text.length < 60 &&
          text == text.toUpperCase() &&
          !RegExp(r'^\d+$').hasMatch(text);

      // Prioritize explicit Chapter headings over Document Title
      if (isChapterPattern || isNamedChapter || isRomanChapter) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading1,
          headingLevel: 1,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }

      // Book / Document Title on leading pages
      if (para.startPageIndex <= 2 && isAllCapTitle && top < pageHeight * 0.40) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.documentTitle,
          headingLevel: 1,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }

      if (fontRatio >= 1.45 ||
          (fontRatio >= 1.18 && isBold && (isChapterPattern || isNamedChapter || isRomanChapter)) ||
          isProminentTitle) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading1,
          headingLevel: 1,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }

      // H2: Section heading (1.2x - 1.45x body size, or bold with Roman/Section numbering or isolated uppercase)
      final isSectionPattern = RegExp(
        r'^([0-9ivxlcdm]+\.|\bsection\b|\bhukum\b)',
        caseSensitive: false,
      ).hasMatch(text);

      if ((fontRatio >= 1.22 && isBold) ||
          (isBold && isSectionPattern) ||
          isSectionPattern ||
          (isAllCapTitle && top < pageHeight * 0.65)) {
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
