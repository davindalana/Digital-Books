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
    double headerHeight = 32.0,
    double footerHeight = 28.0,
    double verticalPadding = 32.0,
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
        ? ((viewportWidth - 32) / 2)
        : viewportWidth;
    final double effectiveMargin = (rawPageWidth < 400)
        ? 16.0
        : (rawPageWidth < 650 ? 22.0 : typography.horizontalMargin);
    final double contentWidth = (rawPageWidth - (effectiveMargin * 2)).clamp(
      160.0,
      1400.0,
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
            headingHeight + (typography.paragraphSpacing * 1.5);
        continue;
      }

      // Paragraph / Quote text
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

        if (fullHeight <= remainingHeightBudget) {
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
          currentUsedHeight += fullHeight + typography.paragraphSpacing;
          charStart = text.length;
        } else {
          // Paragraph must be split at clean word boundary within availableHeight
          final splitIndex = _findBestWordBreak(
            text: remainingText,
            style: textStyle,
            maxWidth: contentWidth,
            maxHeight: remainingHeightBudget,
          );

          if (splitIndex <= 0 || splitIndex >= remainingText.length) {
            // Cannot split or no room, push page and try on fresh page
            if (currentPageSlices.isNotEmpty) {
              pushCurrentPage();
              continue;
            } else {
              // Even a fresh page cannot fit: force split by line count
              final forcedIndex = math.max(
                1,
                (remainingText.length * 0.5).floor(),
              );
              currentPageSlices.add(
                PaginatedNodeSlice(
                  node: node,
                  textSlice: remainingText.substring(0, forcedIndex),
                  startCharOffset: charStart,
                  endCharOffset: charStart + forcedIndex,
                  isContinuation: charStart > 0,
                  hasMore: true,
                ),
              );
              charStart += forcedIndex;
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
            currentUsedHeight +=
                actualSliceHeight + typography.paragraphSpacing;
            charStart += splitIndex;

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
  /// Guarantees that words are NEVER split in half.
  static int _findBestWordBreak({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
  }) {
    if (text.isEmpty) return 0;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    try {
      final textPosition = textPainter.getPositionForOffset(
        Offset(maxWidth, maxHeight),
      );
      int candidateOffset = textPosition.offset.clamp(0, text.length);

      if (candidateOffset >= text.length) {
        return text.length;
      }

      // Walk backward to find the nearest whitespace boundary
      while (candidateOffset > 0 &&
          candidateOffset < text.length &&
          text[candidateOffset].trim().isNotEmpty) {
        candidateOffset--;
      }

      // If no space was found (e.g. single long token), find first whitespace forward or fallback
      if (candidateOffset == 0) {
        final firstSpace = text.indexOf(' ');
        if (firstSpace > 0 && firstSpace < text.length) {
          candidateOffset = firstSpace;
        } else {
          candidateOffset = (text.length / 2).floor().clamp(1, text.length);
        }
      }

      return candidateOffset;
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
