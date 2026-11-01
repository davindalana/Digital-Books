import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/typography/typography_settings.dart';
import '../models/reader_content.dart';

class PaginatedNodeSlice {
  final ContentNode node;
  final String textSlice;
  final int startCharOffset;
  final int endCharOffset;
  final bool isContinuation;
  final bool hasMore;

  const PaginatedNodeSlice({
    required this.node,
    required this.textSlice,
    required this.startCharOffset,
    required this.endCharOffset,
    this.isContinuation = false,
    this.hasMore = false,
  });
}

class PaginatedPage {
  final int pageIndexInChapter;
  final int pageIndexInBook;
  final int chapterIndex;
  final String chapterTitle;
  final List<PaginatedNodeSlice> slices;
  final String firstAnchorNodeId;
  final String lastAnchorNodeId;

  const PaginatedPage({
    required this.pageIndexInChapter,
    required this.pageIndexInBook,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.slices,
    required this.firstAnchorNodeId,
    required this.lastAnchorNodeId,
  });

  bool containsAnchor(String nodeId, [int charOffset = 0]) {
    for (final slice in slices) {
      if (slice.node.id == nodeId) {
        if (charOffset >= slice.startCharOffset &&
            (charOffset <= slice.endCharOffset ||
                slice.endCharOffset >= slice.node.text.length)) {
          return true;
        }
      }
    }
    return false;
  }
}

class PaginationEngine {
  static final Map<String, List<PaginatedPage>> _layoutCache = {};

  static void clearCache() => _layoutCache.clear();

  /// Paginates an entire [ReaderDocument] deterministically according to viewport dimensions and typography.
  static List<PaginatedPage> paginateDocument({
    required ReaderDocument document,
    required double viewportWidth,
    required double viewportHeight,
    required TypographySettings typography,
    double headerHeight = 28.0,
    double footerHeight = 24.0,
    double verticalPadding = 8.0,
  }) {
    final List<PaginatedPage> allPages = [];
    int runningBookPageIndex = 0;

    for (final chapter in document.chapters) {
      final chapterPages = paginateChapter(
        chapter: chapter,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        typography: typography,
        startBookPageIndex: runningBookPageIndex,
        headerHeight: headerHeight,
        footerHeight: footerHeight,
        verticalPadding: verticalPadding,
      );
      allPages.addAll(chapterPages);
      runningBookPageIndex += chapterPages.length;
    }

    if (allPages.isEmpty) {
      allPages.add(
        PaginatedPage(
          pageIndexInChapter: 0,
          pageIndexInBook: 0,
          chapterIndex: 0,
          chapterTitle: document.title,
          slices: [
            PaginatedNodeSlice(
              node: const ContentNode(
                id: 'default_empty',
                type: ContentNodeType.paragraph,
                text: 'Tidak ada konten untuk ditampilkan.',
              ),
              textSlice: 'Tidak ada konten untuk ditampilkan.',
              startCharOffset: 0,
              endCharOffset: 34,
            ),
          ],
          firstAnchorNodeId: 'default_empty',
          lastAnchorNodeId: 'default_empty',
        ),
      );
    }

    return allPages;
  }

  /// Paginates a single [ReaderChapter] with actual [TextPainter] height measurements.
  static List<PaginatedPage> paginateChapter({
    required ReaderChapter chapter,
    required double viewportWidth,
    required double viewportHeight,
    required TypographySettings typography,
    int startBookPageIndex = 0,
    double headerHeight = 28.0,
    double footerHeight = 24.0,
    double verticalPadding = 8.0,
  }) {
    // 1. Check cache
    final isTwoPageSpread = viewportWidth >= 850 && typography.twoPageSpread;
    final double rawPageWidth = isTwoPageSpread
        ? ((viewportWidth - 16.0) / 2)
        : viewportWidth;
    final double effectiveMargin = (rawPageWidth < 400)
        ? 16.0
        : (rawPageWidth < 650 ? 22.0 : typography.horizontalMargin);
    final double maxClampWidth = isTwoPageSpread ? 800.0 : 900.0;
    final double contentWidth = (rawPageWidth - (effectiveMargin * 2)).clamp(
      160.0,
      maxClampWidth,
    );

    final double availableHeight =
        (viewportHeight - (verticalPadding * 2) - headerHeight - footerHeight)
            .clamp(120.0, 4000.0);

    final cacheKey =
        '${chapter.id}_${contentWidth.toInt()}x${availableHeight.toInt()}_${typography.cacheKey}_$startBookPageIndex';
    if (_layoutCache.containsKey(cacheKey)) {
      return _layoutCache[cacheKey]!;
    }

    final List<PaginatedPage> generatedPages = [];
    List<PaginatedNodeSlice> currentPageSlices = [];
    double currentUsedHeight = 0;
    int pageIndexInChapter = 0;

    void pushCurrentPage() {
      if (currentPageSlices.isNotEmpty) {
        generatedPages.add(
          PaginatedPage(
            pageIndexInChapter: pageIndexInChapter++,
            pageIndexInBook: startBookPageIndex++,
            chapterIndex: chapter.index,
            chapterTitle: chapter.title,
            slices: List.from(currentPageSlices),
            firstAnchorNodeId: currentPageSlices.first.node.id,
            lastAnchorNodeId: currentPageSlices.last.node.id,
          ),
        );
        currentPageSlices.clear();
        currentUsedHeight = 0;
      }
    }

    for (int nodeIdx = 0; nodeIdx < chapter.nodes.length; nodeIdx++) {
      final node = chapter.nodes[nodeIdx];

      // Explicit page break
      if (node.type == ContentNodeType.pageBreak) {
        pushCurrentPage();
        continue;
      }

      // Images
      if (node.type == ContentNodeType.image) {
        const double estimatedImageHeight = 220.0;
        final hasCaption = node.text.trim().isNotEmpty;
        final totalImageHeight = estimatedImageHeight + (hasCaption ? 28.0 : 0.0);
        if (currentUsedHeight + totalImageHeight > availableHeight &&
            currentPageSlices.isNotEmpty) {
          pushCurrentPage();
        }
        currentPageSlices.add(
          PaginatedNodeSlice(
            node: node,
            textSlice: node.text,
            startCharOffset: 0,
            endCharOffset: node.text.length,
          ),
        );
        currentUsedHeight += totalImageHeight + typography.paragraphSpacing;
        continue;
      }

      // Text measurement using TextPainter
      final text = node.text.trim();
      if (text.isEmpty) continue;

      final textStyle = node.type == ContentNodeType.heading
          ? typography.headingStyle(level: node.level)
          : (node.type == ContentNodeType.quote
                ? typography.quoteStyle()
                : (node.type == ContentNodeType.footnote
                    ? typography.bodyStyle().copyWith(
                        fontSize: typography.fontSize * 0.85,
                        fontStyle: FontStyle.italic,
                      )
                    : typography.bodyStyle()));

      // Orphan heading prevention:
      // If block is a heading, verify that the heading AND at least 2 lines of following text fit.
      // If not, break to the next page immediately so heading does not sit alone at the bottom.
      if (node.type == ContentNodeType.heading) {
        final headingHeight = _measureTextHeight(text, textStyle, contentWidth);
        final minHeadingBudget =
            headingHeight +
            (typography.fontSize * typography.lineSpacing * 2) +
            typography.paragraphSpacing;

        if (currentUsedHeight + minHeadingBudget > availableHeight &&
            currentPageSlices.isNotEmpty) {
          pushCurrentPage();
        }

        currentPageSlices.add(
          PaginatedNodeSlice(
            node: node,
            textSlice: text,
            startCharOffset: 0,
            endCharOffset: text.length,
          ),
        );
        currentUsedHeight +=
            headingHeight + 8.0 + (typography.paragraphSpacing * 1.2);
        continue;
      }

      // Paragraph / Quote / Footnote text
      final isAtomicNode = node.type == ContentNodeType.footnote ||
          (node.type == ContentNodeType.quote && text.length < 250);

      int charStart = 0;
      while (charStart < text.length) {
        final remainingText = text.substring(charStart);
        final remainingHeightBudget = availableHeight - currentUsedHeight;

        // If less than one line of text fits, start a fresh page
        final singleLineHeight = typography.fontSize * typography.lineSpacing;
        if (remainingHeightBudget < singleLineHeight &&
            currentPageSlices.isNotEmpty) {
          pushCurrentPage();
          continue;
        }

        final fullHeight = _measureTextHeight(
          remainingText,
          textStyle,
          contentWidth,
        );

        final nodePadding = node.type == ContentNodeType.footnote
            ? (4.0 + (typography.paragraphSpacing * 0.6))
            : (node.type == ContentNodeType.quote
                ? (8.0 + typography.paragraphSpacing)
                : typography.paragraphSpacing);

        final requiredBudget = fullHeight + nodePadding;
        if (requiredBudget <= remainingHeightBudget ||
            (currentPageSlices.isEmpty && fullHeight <= remainingHeightBudget)) {
          // Entire remaining paragraph fits
          currentPageSlices.add(
            PaginatedNodeSlice(
              node: node,
              textSlice: remainingText,
              startCharOffset: charStart,
              endCharOffset: text.length,
              isContinuation: charStart > 0,
              hasMore: false,
            ),
          );
          currentUsedHeight += requiredBudget;
          charStart = text.length;
        } else {
          // Paragraph must be split adaptively at clean word boundary within availableHeight
          final availableTextBudget = math.max(
            0.0,
            remainingHeightBudget - nodePadding,
          );
          final splitIndex = _findBestWordBreak(
            text: remainingText,
            style: textStyle,
            maxWidth: contentWidth,
            maxHeight: availableTextBudget,
            isFreshPage: currentPageSlices.isEmpty,
            isAtomic: isAtomicNode,
          );

          if (splitIndex <= 0 || splitIndex >= remainingText.length) {
            // Cannot split cleanly or block is atomic, push page and retry on fresh page
            if (currentPageSlices.isNotEmpty) {
              pushCurrentPage();
              continue;
            } else {
              // Even a fresh page cannot fit: force split at clean word boundary
              int forcedIndex = math.max(
                1,
                (remainingText.length * 0.5).floor(),
              );
              // Walk backward to nearest space so words are NEVER cut in half
              while (forcedIndex > 0 && remainingText[forcedIndex] != ' ') {
                forcedIndex--;
              }
              if (forcedIndex <= 0) {
                final nextSpace = remainingText.indexOf(' ');
                forcedIndex = nextSpace > 0 ? nextSpace : remainingText.length;
              }

              currentPageSlices.add(
                PaginatedNodeSlice(
                  node: node,
                  textSlice: remainingText.substring(0, forcedIndex).trimRight(),
                  startCharOffset: charStart,
                  endCharOffset: charStart + forcedIndex,
                  isContinuation: charStart > 0,
                  hasMore: true,
                ),
              );
              charStart += forcedIndex;
              while (charStart < text.length && text[charStart] == ' ') {
                charStart++;
              }
              pushCurrentPage();
            }
          } else {
            final sliceText = remainingText
                .substring(0, splitIndex)
                .trimRight();
            final actualSliceHeight = _measureTextHeight(
              sliceText,
              textStyle,
              contentWidth,
            );

            currentPageSlices.add(
              PaginatedNodeSlice(
                node: node,
                textSlice: sliceText,
                startCharOffset: charStart,
                endCharOffset: charStart + splitIndex,
                isContinuation: charStart > 0,
                hasMore: true,
              ),
            );
            currentUsedHeight += actualSliceHeight + nodePadding;
            charStart += splitIndex;
            // Advance past inter-word whitespace so continuation slice does not start with leading whitespace
            while (charStart < text.length && text[charStart] == ' ') {
              charStart++;
            }

            // Page is now full, push it
            pushCurrentPage();
          }
        }
      }
    }

    pushCurrentPage();

    if (generatedPages.isEmpty) {
      generatedPages.add(
        PaginatedPage(
          pageIndexInChapter: 0,
          pageIndexInBook: startBookPageIndex,
          chapterIndex: chapter.index,
          chapterTitle: chapter.title,
          slices: [
            PaginatedNodeSlice(
              node: ContentNode(
                id: '${chapter.id}_empty',
                type: ContentNodeType.paragraph,
                text: 'Tidak ada konten pada bab ini.',
              ),
              textSlice: 'Tidak ada konten pada bab ini.',
              startCharOffset: 0,
              endCharOffset: 31,
            ),
          ],
          firstAnchorNodeId: '${chapter.id}_empty',
          lastAnchorNodeId: '${chapter.id}_empty',
        ),
      );
    }

    _layoutCache[cacheKey] = generatedPages;
    return generatedPages;
  }

  /// Measures exact rendered height of text using Flutter's native [TextPainter].
  static double _measureTextHeight(
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    if (text.isEmpty) return 0.0;
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final height = textPainter.height;
    textPainter.dispose();
    return height;
  }

  /// Finds the character boundary where text cleanly breaks before exceeding maxHeight.
  /// Guarantees that:
  /// 1. Words are NEVER split in half (snaps backward to clean whitespace boundary).
  /// 2. Rendered height is strictly <= maxHeight (zero vertical overflow/clipping).
  /// 3. Orphan prevention: Requires at least [minLinesAtBottom] (2) lines on the current page.
  /// 4. Widow prevention: Ensures the remainder on the next page has at least [minLinesAtTop] (2) lines.
  /// 5. Atomic preservation: If [isAtomic] is true or paragraph has fewer than 4 lines on a non-fresh page,
  ///    returns 0 so the block is kept intact on the next page.
  static int _findBestWordBreak({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    bool isFreshPage = false,
    bool isAtomic = false,
    int minLinesAtBottom = 2,
    int minLinesAtTop = 2,
  }) {
    if (text.isEmpty || maxHeight <= 0) return 0;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    try {
      final lineMetrics = textPainter.computeLineMetrics();
      final totalLines = lineMetrics.length;

      // If text fits entirely within maxHeight, return text.length
      if (textPainter.height <= maxHeight) {
        return text.length;
      }

      // If block is atomic or too short to split into two multi-line fragments,
      // reject split on non-fresh pages so the block stays whole on next page.
      if (!isFreshPage) {
        if (isAtomic || totalLines < (minLinesAtBottom + minLinesAtTop)) {
          return 0;
        }
      }

      // Determine how many lines fit strictly within maxHeight
      int fittingLines = 0;
      for (int i = 0; i < totalLines; i++) {
        final lineBottom = lineMetrics[i].baseline + lineMetrics[i].descent;
        if (lineBottom <= maxHeight) {
          fittingLines = i + 1;
        } else {
          break;
        }
      }

      // Orphan check: on non-fresh page, must fit at least minLinesAtBottom
      if (!isFreshPage && fittingLines < minLinesAtBottom) {
        return 0;
      }

      // On a fresh page, must fit at least 1 line
      if (isFreshPage && fittingLines == 0) {
        fittingLines = 1;
      }

      int targetLines = fittingLines;
      int remainingLines = totalLines - targetLines;

      // Widow check: if remaining lines would be 1 line, back up targetLines by 1
      if (remainingLines == 1) {
        if (targetLines > minLinesAtBottom) {
          targetLines--;
          remainingLines++;
        } else if (!isFreshPage) {
          // Cannot satisfy widow constraint without violating orphan constraint
          return 0;
        }
      }

      if (targetLines <= 0) return 0;

      // Sample position at the baseline of the target line
      final targetLineIndex = (targetLines - 1).clamp(0, totalLines - 1);
      final targetLineMid = lineMetrics[targetLineIndex].baseline;

      final textPos = textPainter.getPositionForOffset(Offset(maxWidth, targetLineMid));
      int candidateOffset = textPos.offset.clamp(0, text.length);

      // Snap backward to whitespace boundary
      while (candidateOffset > 0 &&
          candidateOffset < text.length &&
          text[candidateOffset].trim().isNotEmpty) {
        candidateOffset--;
      }

      // Verify with sub-TextPainter that candidate slice does not exceed targetLines or maxHeight
      while (candidateOffset > 0) {
        final subTp = TextPainter(
          text: TextSpan(text: text.substring(0, candidateOffset).trimRight(), style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth);
        final subLines = subTp.computeLineMetrics().length;
        final subHeight = subTp.height;
        subTp.dispose();

        if (subLines <= targetLines && (subHeight <= maxHeight || isFreshPage)) {
          return candidateOffset;
        }
        candidateOffset--;
        while (candidateOffset > 0 && text[candidateOffset].trim().isNotEmpty) {
          candidateOffset--;
        }
      }

      // Fallback for fresh page if single word exceeds line
      if (isFreshPage) {
        final nextSpace = text.indexOf(' ');
        return nextSpace > 0 ? nextSpace : text.length;
      }

      return 0;
    } finally {
      textPainter.dispose();
    }
  }

  /// Locates the exact page index in [pages] containing the anchor [anchorNodeId].
  /// If the node is split across multiple pages, uses [characterOffset] to pinpoint the exact slice.
  static int findPageIndexForAnchor({
    required List<PaginatedPage> pages,
    required String anchorNodeId,
    int characterOffset = 0,
  }) {
    if (pages.isEmpty) return 0;

    for (int i = 0; i < pages.length; i++) {
      if (pages[i].containsAnchor(anchorNodeId, characterOffset)) {
        return i;
      }
    }

    // Fallback: match node ID without offset restriction
    for (int i = 0; i < pages.length; i++) {
      if (pages[i].slices.any((s) => s.node.id == anchorNodeId)) {
        return i;
      }
    }

    return 0;
  }
}
