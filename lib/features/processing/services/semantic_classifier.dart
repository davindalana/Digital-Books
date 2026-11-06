import 'dart:math' as math;
import 'dart:ui' show Rect;
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
    final effectivePageHeight =
        (defaultPageHeight > 0 &&
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

    // 3. Page-Level Pre-Pass:
    // Identify Table of Contents pages, fuse multi-element Chapter Divider Pages,
    // and fuse Prologue/Preface title lines.
    final paragraphsByPage = <int, List<ReconstructedParagraph>>{};
    for (final p in paragraphs) {
      paragraphsByPage.putIfAbsent(p.startPageIndex, () => []).add(p);
    }

    final tocPageIndices = <int>{};
    for (final pageIdx in paragraphsByPage.keys) {
      final paras = paragraphsByPage[pageIdx]!;
      final hasTocHeader = paras.any(
        (p) => RegExp(
          r'^(daftar isi|table of contents|contents)\b',
          caseSensitive: false,
        ).hasMatch(p.text.trim()),
      );
      final dottedCount = paras
          .where((p) => p.text.contains('..') || p.text.contains('--'))
          .length;
      if (hasTocHeader || dottedCount >= 3) {
        tocPageIndices.add(pageIdx);
      }
    }

    final preparedParagraphs = <ReconstructedParagraph>[];
    for (final pageIdx in paragraphsByPage.keys.toList()..sort()) {
      final pageParas = paragraphsByPage[pageIdx]!;

      // Chapter Divider Page Detection:
      // A page dedicated to introducing a chapter has few paragraphs (<= 6),
      // contains a chapter identifier (e.g. "BAB I" / "BABI"), and an all-caps/title-case title.
      if (pageParas.length <= 6) {
        ReconstructedParagraph? chapPara;
        final titleParas = <ReconstructedParagraph>[];

        for (final p in pageParas) {
          final norm = normalizeChapterHeader(p.text);
          if (norm != null && chapPara == null) {
            chapPara = p;
          } else if (p.text.length >= 2 &&
              (p.text == p.text.toUpperCase() ||
                  p.isBold ||
                  p.fontSize > bodyFontSize * 1.1) &&
              !RegExp(r'^\d+$').hasMatch(p.text.trim()) &&
              p.boundingBox.top < effectivePageHeight * 0.60) {
            titleParas.add(p);
          }
        }

        if (chapPara != null && titleParas.isNotEmpty) {
          final normHeader = normalizeChapterHeader(chapPara.text)!;
          titleParas.sort(
            (a, b) => a.boundingBox.top.compareTo(b.boundingBox.top),
          );
          final fullTitle = titleParas.map((t) => t.text.trim()).join(' ');
          final fusedText = normHeader.contains(':')
              ? normHeader
              : '$normHeader: $fullTitle';
          final fusedTop = math.min(
            chapPara.boundingBox.top,
            titleParas.first.boundingBox.top,
          );
          final fusedBottom = math.max(
            chapPara.boundingBox.bottom,
            titleParas.last.boundingBox.bottom,
          );
          final fusedLeft = titleParas
              .map((t) => t.boundingBox.left)
              .reduce(math.min);
          final fusedRight = titleParas
              .map((t) => t.boundingBox.right)
              .reduce(math.max);

          final fusedPara = ReconstructedParagraph(
            text: fusedText,
            startPageIndex: pageIdx,
            endPageIndex: pageIdx,
            boundingBox: Rect.fromLTRB(
              fusedLeft,
              fusedTop,
              fusedRight,
              fusedBottom,
            ),
            fontSize: math.max(chapPara.fontSize, titleParas.first.fontSize),
            fontStyles: [
              ...chapPara.fontStyles,
              ...titleParas.expand((t) => t.fontStyles),
            ],
            isBold: true,
            isItalic: false,
            lineCount:
                chapPara.lineCount +
                titleParas.fold(0, (sum, t) => sum + t.lineCount),
            sourceLines: [
              ...chapPara.sourceLines,
              ...titleParas.expand((t) => t.sourceLines),
            ],
          );

          for (final p in pageParas) {
            if (p == chapPara) {
              preparedParagraphs.add(fusedPara);
            } else if (titleParas.contains(p)) {
              continue;
            } else {
              preparedParagraphs.add(p);
            }
          }
          continue;
        }
      }

      // Prologue / Preface subtitle fusion on the same page
      if (pageParas.length >= 2) {
        final firstText = pageParas.first.text.trim().toLowerCase();
        if ((firstText == 'prolog' ||
                firstText == 'prologue' ||
                firstText == 'prakata') &&
            !pageParas[1].text.trim().endsWith('.') &&
            pageParas[1].text.length >= 8 &&
            pageParas[1].text.length <= 100 &&
            pageParas[1].boundingBox.top < effectivePageHeight * 0.40) {
          final subtitlePara = pageParas[1];
          final fusedText =
              '${pageParas.first.text.trim()}: ${subtitlePara.text.trim()}';
          final fusedPara = ReconstructedParagraph(
            text: fusedText,
            startPageIndex: pageIdx,
            endPageIndex: pageIdx,
            boundingBox: Rect.fromLTRB(
              pageParas.first.boundingBox.left,
              pageParas.first.boundingBox.top,
              subtitlePara.boundingBox.right,
              subtitlePara.boundingBox.bottom,
            ),
            fontSize: math.max(pageParas.first.fontSize, subtitlePara.fontSize),
            fontStyles: pageParas.first.fontStyles,
            isBold: true,
            isItalic: false,
            lineCount: pageParas.first.lineCount + subtitlePara.lineCount,
            sourceLines: [
              ...pageParas.first.sourceLines,
              ...subtitlePara.sourceLines,
            ],
          );
          preparedParagraphs.add(fusedPara);
          for (int i = 2; i < pageParas.length; i++) {
            preparedParagraphs.add(pageParas[i]);
          }
          continue;
        }
      }

      preparedParagraphs.addAll(pageParas);
    }

    final classifiedBlocks = <SemanticReconstructedBlock>[];

    for (final para in preparedParagraphs) {
      final block = _classifyParagraph(
        para: para,
        bodyFontSize: bodyFontSize,
        bodyLeftMargin: bodyLeftMargin,
        pageHeight: effectivePageHeight,
        repeatingHeaders: repeatingHeaders,
        repeatingFooters: repeatingFooters,
        isTocPage: tocPageIndices.contains(para.startPageIndex),
        totalPages: totalPages,
      );
      classifiedBlocks.add(block);
    }

    return classifiedBlocks;
  }

  /// Normalizes chapter header variants (e.g. "BABI", "Bab11", "BAB 1", "Chapter 2")
  /// into standardized Indonesian / English chapter markers, mapping OCR confusions.
  static String? normalizeChapterHeader(String text) {
    // Clean OCR pipe substitutions (| -> I) and normalize whitespace
    final t = text.trim().replaceAll('|', 'I');
    final match = RegExp(
      r'^(bab|chapter|bagian)\s*([0-9]+|[ivxlcdm]+|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|l)\b',
      caseSensitive: false,
    ).firstMatch(t);
    if (match == null) return null;

    final rawPrefix = match.group(1)!;
    final prefix = rawPrefix == rawPrefix.toUpperCase()
        ? rawPrefix
        : rawPrefix[0].toUpperCase() + rawPrefix.substring(1).toLowerCase();
    var numPart = match.group(2)!;
    if (numPart == numPart.toUpperCase() ||
        RegExp(r'^\d+$').hasMatch(numPart)) {
      // keep
    } else {
      numPart = numPart.toUpperCase();
    }

    // Map common OCR substitutions
    if (numPart == '11') {
      numPart = 'II';
    } else if (numPart == '111' ||
        numPart == 'I1I' ||
        numPart == '1I1' ||
        numPart == 'II1' ||
        numPart == '1II') {
      numPart = 'III';
    } else if (numPart == 'L') {
      numPart = 'I';
    } else if (numPart == 'SATU') {
      numPart = '1';
    } else if (numPart == 'DUA') {
      numPart = '2';
    } else if (numPart == 'TIGA') {
      numPart = '3';
    } else if (numPart == 'EMPAT') {
      numPart = '4';
    } else if (numPart == 'LIMA') {
      numPart = '5';
    } else if (numPart == 'ENAM') {
      numPart = '6';
    } else if (numPart == 'TUJUH') {
      numPart = '7';
    } else if (numPart == 'DELAPAN') {
      numPart = '8';
    } else if (numPart == 'SEMBILAN') {
      numPart = '9';
    } else if (numPart == 'SEPULUH') {
      numPart = '10';
    }

    final remainder = t.substring(match.end).trim();
    final cleanRemainder = remainder.replaceFirst(RegExp(r'^[:\-–—\.]\s*'), '');
    if (cleanRemainder.isNotEmpty) {
      return '$prefix $numPart: $cleanRemainder';
    }
    return '$prefix $numPart';
  }

  /// Classifies an individual paragraph.
  static SemanticReconstructedBlock _classifyParagraph({
    required ReconstructedParagraph para,
    required double bodyFontSize,
    required double bodyLeftMargin,
    required double pageHeight,
    required Set<String> repeatingHeaders,
    required Set<String> repeatingFooters,
    bool isTocPage = false,
    int totalPages = 1,
  }) {
    final text = para.text.trim();
    final top = para.boundingBox.top;
    final bottom = para.boundingBox.bottom;
    final left = para.boundingBox.left;
    final fontSize = para.fontSize;
    final isBold = para.isBold;
    final isItalic = para.isItalic;
    final lineCount = para.lineCount;

    // Handle Table of Contents pages:
    // Only the title "Daftar Isi" is a heading1; all entries on that page are body/toc content.
    if (isTocPage) {
      if (RegExp(
        r'^(daftar isi|table of contents|contents)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading1,
          headingLevel: 1,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.98,
        );
      }
      return SemanticReconstructedBlock(
        type: SemanticBlockType.bodyParagraph,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        metadata: const {'isTocEntry': true},
        confidence: 0.95,
      );
    }

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

      final isAllUpperShort =
          text.length <= 50 &&
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

    if (isItalic &&
        fontSize <= bodyFontSize &&
        lineCount <= 2 &&
        isCaptionKeyword) {
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
    final isLikelyHeading =
        (isBold && fontRatio >= 1.10) ||
        fontRatio >= 1.25 ||
        (isBold && lineCount == 1 && text.length < 100);

    final orderedMatch = RegExp(
      r'^(\d+[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]+\))\s+',
    ).firstMatch(text);
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

    final unorderedMatch = RegExp(
      r'^([•\-\*–—]|[\u2022\u2023\u25E6\u2043\u2219])\s+',
    ).firstMatch(text);
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
    final isShortAllCapTitle =
        text.length <= 60 &&
        text.replaceAll('"', '').trim() ==
            text.replaceAll('"', '').trim().toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(text);
    if (hasIndent &&
        !isShortAllCapTitle &&
        (isItalic ||
            para.isDialogue ||
            (text.startsWith('"') && text.length > 50))) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.quote,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.88,
      );
    }

    // Direct Chapter Header Check (e.g. "BAB 1: ...", "BAB I: ...", "Chapter 1: ...")
    final normChapter = normalizeChapterHeader(text);
    final isTocEntry =
        RegExp(r'(\.{3,}|[-–—]{3,}|\.{2,}\s*[0-9ivxlcdm]+$)').hasMatch(text) &&
        (text.contains('..') || text.contains('--'));

    if (!isTocPage && !isTocEntry && normChapter != null) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.heading1,
        headingLevel: 1,
        text: normChapter,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.98,
      );
    }

    final isRomanChapter =
        lineCount == 1 &&
        top < pageHeight * 0.70 &&
        RegExp(
          r'^(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII|XIII|XIV|XV|XVI|XVII|XVIII|XIX|XX)$',
        ).hasMatch(text);

    if (!isTocPage &&
        !isTocEntry &&
        isRomanChapter &&
        (fontSize > bodyFontSize * 1.15 || isBold)) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.heading1,
        headingLevel: 1,
        text: text,
        sourcePageIndex: para.startPageIndex,
        sourceBounds: para.boundingBox,
        confidence: 0.95,
      );
    }

    // Cover Page (Page 0) components for multi-page documents (unless explicitly a named chapter)
    final isExplicitChapterOnPage0 =
        normalizeChapterHeader(text) != null ||
        RegExp(
          r'^(prolog|prologue|epilog|epilogue|introduction|pengantar|prakata|kata pengantar|pendahuluan|kesimpulan|conclusion|daftar isi|testimoni)\b',
          caseSensitive: false,
        ).hasMatch(text);

    if (para.startPageIndex == 0 &&
        totalPages > 1 &&
        !isExplicitChapterOnPage0) {
      return SemanticReconstructedBlock(
        type: SemanticBlockType.documentTitle,
        headingLevel: 1,
        text: text,
        sourcePageIndex: 0,
        sourceBounds: para.boundingBox,
        metadata: const {'isFrontMatter': true, 'isCover': true},
        confidence: 0.98,
      );
    }

    // H. Headings (H1, H2, H3, Document Title)
    // Supports both font-metric scaling in digital PDFs and casing/spatial patterns in scanned OCR
    if (lineCount <= 4 && text.length < 180) {
      final fontRatio = fontSize / bodyFontSize;

      final isFusedPrologue = RegExp(
        r'^(prolog|prologue|prakata|epilog|epilogue)\s*:',
        caseSensitive: false,
      ).hasMatch(text);

      final isNamedChapter =
          isFusedPrologue ||
          (text.length <= 45 &&
              !text.endsWith('.') &&
              RegExp(
                r'^(prolog|prologue|epilog|epilogue|introduction|pengantar|prakata|kata pengantar|pendahuluan|kesimpulan|conclusion|daftar isi|testimoni|ucapan terima kasih|tentang penulis)\b',
                caseSensitive: false,
              ).hasMatch(text));

      final isRomanChapter =
          lineCount == 1 &&
          top < pageHeight * 0.70 &&
          RegExp(
            r'^(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII|XIII|XIV|XV|XVI|XVII|XVIII|XIX|XX)$',
          ).hasMatch(text);

      final isAllCapTitle =
          lineCount <= 3 &&
          text.length >= 3 &&
          text.length <= 80 &&
          text.replaceAll('"', '').trim() ==
              text.replaceAll('"', '').trim().toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(text) &&
          !RegExp(r'^\d+$').hasMatch(text);

      final isProminentTitle =
          fontRatio >= 1.45 ||
          (fontRatio >= 1.25 &&
              isAllCapTitle &&
              text.length < 60 &&
              !RegExp(r'^\d+$').hasMatch(text));

      // Prioritize explicit Chapter headings over Document Title (unless it is a TOC entry line)
      if (!isTocEntry && (isNamedChapter || isRomanChapter)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading1,
          headingLevel: 1,
          text: normChapter ?? text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }

      // Book / Document Title on leading pages
      if (para.startPageIndex <= 2 &&
          isAllCapTitle &&
          top < pageHeight * 0.40) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.documentTitle,
          headingLevel: 1,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          metadata: const {'isFrontMatter': true},
          confidence: 0.95,
        );
      }

      // True Chapter Markers (explicit BAB, named front/back matter, Roman numerals)
      if (normChapter != null ||
          isNamedChapter ||
          isRomanChapter ||
          (fontRatio >= 1.60 && para.startPageIndex <= 3)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading1,
          headingLevel: 1,
          text: normChapter ?? text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.95,
        );
      }

      // H2: Section heading / Subchapter (all-caps section title, 1.18x+ body size, or numbered section)
      final isSectionPattern = RegExp(
        r'^([0-9ivxlcdm]+\.|\bsection\b|\bhukum\b|[a-z]\.)',
        caseSensitive: false,
      ).hasMatch(text);

      if ((fontRatio >= 1.18 && isBold) ||
          (isBold && isSectionPattern) ||
          isSectionPattern ||
          isProminentTitle ||
          (isAllCapTitle && top < pageHeight * 0.70)) {
        return SemanticReconstructedBlock(
          type: SemanticBlockType.heading2,
          headingLevel: 2,
          text: text,
          sourcePageIndex: para.startPageIndex,
          sourceBounds: para.boundingBox,
          confidence: 0.90,
        );
      }

      // H3: Sub-section heading / Section lead (bold/italic/larger font without terminal punctuation)
      final endsWithPunct = RegExp(r'[\.\?!…]\s*$').hasMatch(text);
      if (lineCount <= 2 &&
          text.length <= 80 &&
          !endsWithPunct &&
          (fontRatio >= 1.08 || isBold || isItalic)) {
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
  static double _detectModalBodyFontSize(
    List<ReconstructedParagraph> paragraphs,
  ) {
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
  static double _detectModalLeftMargin(
    List<ReconstructedParagraph> paragraphs,
  ) {
    if (paragraphs.isEmpty) return 50.0;

    final leftMargins = paragraphs.map((p) => p.boundingBox.left).toList()
      ..sort();
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
