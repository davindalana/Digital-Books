import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../models/extracted_page_geometry.dart';
import '../models/semantic_reconstruction_models.dart';
import 'reading_order_resolver.dart';

/// Result of the dedicated table-of-contents reconstruction pass.
class TocResult {
  final List<SemanticReconstructedBlock> blocks;
  final Set<int> handledPages;

  const TocResult({required this.blocks, required this.handledPages});
}

/// Converts OCR TOC fragments (title lines, dot leaders and page labels that
/// are often emitted on separate lines) into one logical row per entry.
class TocReconstructor {
  static TocResult reconstruct({required List<PageReadingOrderResult> pages}) {
    final first = pages.indexWhere(
      (p) => p.orderedLines.any(
        (l) => RegExp(
          r'^(daftar isi|table of contents|contents)\b',
          caseSensitive: false,
        ).hasMatch(l.text.trim()),
      ),
    );
    if (first < 0) {
      return const TocResult(blocks: [], handledPages: {});
    }

    final handled = <int>{};
    final blocks = <SemanticReconstructedBlock>[
      SemanticReconstructedBlock(
        type: SemanticBlockType.heading1,
        text: 'Daftar Isi',
        sourcePageIndex: first,
        confidence: 0.98,
        metadata: const {'isToc': true, 'kind': 'tocTitle'},
      ),
    ];

    for (
      var pageIndex = first;
      pageIndex < pages.length && pageIndex < first + 8;
      pageIndex++
    ) {
      final page = pages[pageIndex];
      final lines = List<ExtractedTextLine>.from(page.orderedLines)
        ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      if (lines.isEmpty) continue;

      final pageWidth =
          lines.map((l) => l.bounds.right).reduce(math.max) + 20.0;
      final pageLabels = lines
          .where(
            (l) => l.bounds.left > pageWidth * 0.62 && _isPageLabel(l.text),
          )
          .toList();
      final titleLines = lines
          .where(
            (l) =>
                l.bounds.left <= pageWidth * 0.62 &&
                !_isPageLabel(l.text) &&
                !_isHeaderOrFooter(l.text),
          )
          .toList();

      // Continuation TOC pages have several title/page-label pairs. Stop when
      // the layout no longer looks like a TOC.
      if (pageIndex > first && pageLabels.length < 2) break;
      handled.add(pageIndex);

      final usedLabels = <int>{};
      // TOC sub-entries (actor/person names) are indented under the preceding
      // work title and carry no page label of their own. Use the page's body
      // left edge as the baseline so a harmless scan shift is not mistaken for
      // an indentation.
      final bodyLeft = titleLines.isEmpty
          ? 0.0
          : titleLines.map((l) => l.bounds.left).reduce(math.min);
      final indentationThreshold = math.max(12.0, pageWidth * 0.018);
      var i = 0;
      var afterChapterLabel = false;
      String? lastEntryTitle;
      String? lastEntryPage;
      while (i < titleLines.length) {
        final line = titleLines[i];
        var text = line.text.trim();
        if (text.isEmpty ||
            RegExp(
              r'^(daftar isi|table of contents|contents)$',
              caseSensitive: false,
            ).hasMatch(text)) {
          i++;
          continue;
        }

        final chapter = _chapterLabel(text);
        if (chapter != null) {
          blocks.add(
            SemanticReconstructedBlock(
              type: SemanticBlockType.metadataBlock,
              text: chapter,
              sourcePageIndex: pageIndex,
              sourceBounds: line.bounds,
              confidence: 0.97,
              metadata: const {'isToc': true, 'kind': 'tocChapterLabel'},
            ),
          );
          afterChapterLabel = true;
          i++;
          continue;
        }

        // Testimonial-index lines are person names, not TOC entries to merge
        // with the following work title. They appear either as "- Name" on the
        // next TOC page or as an indented line without a page label. In both
        // cases the person is a sub-entry of the preceding work title.
        final isIndented = line.bounds.left - bodyLeft >= indentationThreshold;
        final hasTrailingPage = _trailingPageNumber(text) != null;
        final isPerson =
            text.startsWith('- ') || (isIndented && !hasTrailingPage);
        if (isPerson) {
          final personText = _stripTrailingPageNumber(
            text,
          ).replaceFirst(RegExp(r'^-\s*'), '').trim();
          if (personText.isNotEmpty) {
            blocks.add(
              SemanticReconstructedBlock(
                type: SemanticBlockType.metadataBlock,
                text: personText,
                sourcePageIndex: pageIndex,
                sourceBounds: line.bounds,
                confidence: 0.94,
                metadata: {
                  'isToc': true,
                  'kind': 'tocPerson',
                  'tocTitle': personText,
                  'tocPage': '',
                  'parentTocTitle': ?lastEntryTitle,
                  if (lastEntryPage != null && lastEntryPage.isNotEmpty)
                    'parentTocPage': lastEntryPage,
                },
              ),
            );
          }
          i++;
          continue;
        }

        final merged = <ExtractedTextLine>[line];
        var pageLabel =
            _trailingPageNumber(text) ??
            _pairedPageLabel(line, pageLabels, usedLabels);
        var j = i + 1;
        while (pageLabel == null && j < titleLines.length) {
          final next = titleLines[j];
          if (_chapterLabel(next.text.trim()) != null) break;
          if (next.bounds.top - merged.last.bounds.top > 36) break;
          merged.add(next);
          pageLabel = _pairedPageLabel(next, pageLabels, usedLabels);
          j++;
        }

        text = merged.map((l) => _cleanTitle(l.text)).join(' ').trim();
        final trailing = _trailingPageNumber(text);
        final pageNumber = pageLabel ?? trailing;
        if (pageNumber != null) {
          text = _stripTrailingPageNumber(text);
        }
        if (text.isEmpty) {
          i = j;
          continue;
        }

        if (pageNumber == null && afterChapterLabel) {
          blocks.add(
            SemanticReconstructedBlock(
              type: SemanticBlockType.metadataBlock,
              text: text,
              sourcePageIndex: pageIndex,
              sourceBounds: _bounds(merged),
              confidence: 0.95,
              metadata: const {'isToc': true, 'kind': 'tocChapterTitle'},
            ),
          );
        } else {
          blocks.add(
            SemanticReconstructedBlock(
              type: SemanticBlockType.metadataBlock,
              text: text,
              sourcePageIndex: pageIndex,
              sourceBounds: _bounds(merged),
              confidence: 0.95,
              metadata: {
                'isToc': true,
                'kind': 'tocEntry',
                'tocTitle': text,
                'tocPage': pageNumber ?? '',
              },
            ),
          );
        }
        lastEntryTitle = text;
        lastEntryPage = pageNumber ?? '';
        afterChapterLabel = false;
        i = j;
      }
    }

    return TocResult(blocks: blocks, handledPages: handled);
  }

  static bool _isPageLabel(String raw) {
    final text = raw.replaceAll(RegExp(r'^[\.\s]+|[\.\s]+$'), '').trim();
    return RegExp(r'^([ivxlcdm]+|\d+)$', caseSensitive: false).hasMatch(text);
  }

  static bool _isHeaderOrFooter(String text) {
    final lower = text.toLowerCase();
    return lower.contains('bicara itu ada seninya') ||
        RegExp(r'^[ivxlcdm]+\s+bicara', caseSensitive: false).hasMatch(lower);
  }

  static String? _chapterLabel(String text) {
    final normalized = text.replaceAll('|', 'I').trim();
    final match = RegExp(
      r'^(bab|chapter)\s+([ivxlcdm]+|\d+)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    final prefix = match.group(1)!.toUpperCase();
    var number = match.group(2)!.replaceAll('|', 'I').toUpperCase();
    if (number == '11') number = 'II';
    if (number == '111' || number == 'I1I' || number == '1I1') number = 'III';
    return '$prefix $number';
  }

  static String? _pairedPageLabel(
    ExtractedTextLine line,
    List<ExtractedTextLine> labels,
    Set<int> used,
  ) {
    for (var k = 0; k < labels.length; k++) {
      if (used.contains(k)) continue;
      final label = labels[k];
      if ((label.bounds.top - line.bounds.top).abs() <= 14.0) {
        used.add(k);
        return label.text.replaceAll(RegExp(r'[\.\s]+'), '').trim();
      }
    }
    return null;
  }

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'[\.\s]{2,}$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'(?<![A-Z])\.\s*$'), '')
        .trim();
  }

  static String? _trailingPageNumber(String text) {
    final match = RegExp(
      r'(?:\.{2,}|\s{2,})\s*([ivxlcdm]+|\d+)\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1);
  }

  static String _stripTrailingPageNumber(String text) {
    return text
        .replaceAll(
          RegExp(
            r'(?:\.{2,}|\s{2,})\s*([ivxlcdm]+|\d+)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[\.\s]{2,}$'), '')
        .replaceAll(RegExp(r'(?<![A-Z])\.\s*$'), '')
        .trim();
  }

  static Rect? _bounds(List<ExtractedTextLine> lines) {
    if (lines.isEmpty) return null;
    var left = lines.first.bounds.left;
    var top = lines.first.bounds.top;
    var right = lines.first.bounds.right;
    var bottom = lines.first.bounds.bottom;
    for (final line in lines.skip(1)) {
      left = math.min(left, line.bounds.left);
      top = math.min(top, line.bounds.top);
      right = math.max(right, line.bounds.right);
      bottom = math.max(bottom, line.bounds.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
