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
  static const double pageVerticalInset = 24.0;

  /// Comfortable text inset for the open-book composition. Each visible page
  /// gets a generous inner margin so body copy does not run close to the
  /// window edge or the center spine.
  static double horizontalPageMargin({
    required double pageWidth,
    required TypographySettings typography,
  }) {
    if (pageWidth < 400.0) return 18.0;
    if (pageWidth < 650.0) {
      return math.max(48.0, typography.horizontalMargin);
    }
    return math.max(56.0, typography.horizontalMargin);
  }

  static void clearCache() => _layoutCache.clear();

  /// Paginates an entire [ReaderDocument] deterministically according to viewport dimensions and typography.
  static List<PaginatedPage> paginateDocument({
    required ReaderDocument document,
    required double viewportWidth,
    required double viewportHeight,
    required TypographySettings typography,
    double headerHeight = 28.0,
    double footerHeight = 24.0,
    double verticalPadding = pageVerticalInset,
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

  /// Spread gutter width between left and right pages in two-page spread mode.
  /// Previously 24.0 dp; increased to 48.0 dp to make the spread feel less crowded
  /// around the center while maintaining balanced proportions and natural book spine depth.
  static const double spreadGutterWidth = 48.0;

  /// Content width used for pagination in the given viewport. Exposed so
  /// verification tests measure the same geometry as the pagination engine.
  static double contentWidthFor({
    required double viewportWidth,
    required TypographySettings typography,
  }) {
    final isTwoPageSpread = viewportWidth >= 850.0 && typography.twoPageSpread;
    final double rawPageWidth = isTwoPageSpread
        ? ((viewportWidth - spreadGutterWidth) / 2.0)
        : viewportWidth;
    final effectiveMargin = horizontalPageMargin(
      pageWidth: rawPageWidth,
      typography: typography,
    );
    final double maxClampWidth = isTwoPageSpread ? 620.0 : 680.0;
    return (rawPageWidth - (effectiveMargin * 2.0)).clamp(160.0, maxClampWidth);
  }

  /// Usable body height after reader chrome and vertical padding. Exposed for
  /// verification tests that must not guess the available geometry.
  static double availableHeightFor({
    required double viewportHeight,
    double headerHeight = 28.0,
    double footerHeight = 24.0,
    double verticalPadding = pageVerticalInset,
  }) {
    return (viewportHeight -
            (verticalPadding * 2) -
            headerHeight -
            footerHeight)
        .clamp(120.0, 4000.0);
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
    double verticalPadding = pageVerticalInset,
  }) {
    // 1. Check cache
    final contentWidth = contentWidthFor(
      viewportWidth: viewportWidth,
      typography: typography,
    );
    final availableHeight = availableHeightFor(
      viewportHeight: viewportHeight,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      verticalPadding: verticalPadding,
    );

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
        final totalImageHeight =
            estimatedImageHeight + (hasCaption ? 28.0 : 0.0);
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

      final TextStyle textStyle = textStyleFor(node, typography);

      // Orphan heading prevention:
      // A heading must stay with the content that follows it. Rather than
      // reserving a fixed three lines, measure the actual next block: a run of
      // consecutive headings is kept together, a short paragraph must fit
      // whole, an atomic legal clause must fit whole, and a long paragraph only
      // needs its first slice. If that keep-with-next budget does not fit, the
      // heading moves to the next page instead of being left alone.
      final isHeadingNode = _isHeadingNode(node.type);

      if (isHeadingNode) {
        final headingHeight = _measureTextHeight(text, textStyle, contentWidth);
        final headingAdvance =
            headingHeight + 8.0 + (typography.paragraphSpacing * 1.2);
        final keepWithNextHeight = _keepWithNextHeight(
          nodes: chapter.nodes,
          nodeIdx: nodeIdx,
          typography: typography,
          contentWidth: contentWidth,
        );

        if (currentUsedHeight + headingAdvance + keepWithNextHeight >
                availableHeight &&
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
        currentUsedHeight += headingAdvance;
        continue;
      }

      // Paragraph / Quote / Footnote text
      final isAtomicNode = _isAtomicNode(node, text);
      final isNormalPara = _isNormalParagraph(node);

      int charStart = 0;
      while (charStart < text.length) {
        final remainingText = text.substring(charStart);
        final remainingHeightBudget = availableHeight - currentUsedHeight;
        final double currentFirstLineIndent = (charStart == 0 && isNormalPara)
            ? typography.firstLineIndent
            : 0.0;

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
          firstLineIndent: currentFirstLineIndent,
        );

        final double nodePadding = paddingFor(node, typography);

        final requiredBudget = fullHeight + nodePadding;

        // Explicit keepWithNext hint (for example the final legal clause before
        // the copyright footer). If the block and the following block cannot
        // share this page, move the block to the next page instead of leaving a
        // footer by itself on a page of its own.
        if (charStart == 0 &&
            node.attributes['keepWithNext'] == true &&
            currentPageSlices.isNotEmpty) {
          final keepWithNextHeight = _keepWithNextBlockHeight(
            nodes: chapter.nodes,
            nodeIdx: nodeIdx,
            typography: typography,
            contentWidth: contentWidth,
          );
          if (currentUsedHeight + requiredBudget + keepWithNextHeight >
              availableHeight) {
            pushCurrentPage();
            continue;
          }
        }

        if (requiredBudget <= remainingHeightBudget) {
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
            firstLineIndent: currentFirstLineIndent,
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
                  textSlice: remainingText
                      .substring(0, forcedIndex)
                      .trimRight(),
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
              firstLineIndent: currentFirstLineIndent,
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

  static bool _isHeadingNode(ContentNodeType type) =>
      type == ContentNodeType.heading ||
      type == ContentNodeType.sectionHeading ||
      type == ContentNodeType.documentTitle;

  static bool _isAtomicNode(ContentNode node, String text) =>
      node.type == ContentNodeType.footnote ||
      (node.type == ContentNodeType.quote && text.length < 250) ||
      (node.type == ContentNodeType.orderedList &&
          node.attributes['legalClause'] == true);

  static bool _isNormalParagraph(ContentNode node) {
    if (node.type != ContentNodeType.paragraph) return false;
    if (node.attributes['isTocEntry'] == true) return false;
    if (node.attributes['kind'] == 'publisherSlogan') return false;
    if (node.attributes['frontMatter'] == 'cover' ||
        node.attributes['frontMatter'] == 'titlePage' ||
        node.attributes['frontMatter'] == 'copyright') {
      return false;
    }
    return true;
  }

  static TextStyle textStyleFor(
    ContentNode node,
    TypographySettings typography,
  ) {
    switch (node.type) {
      case ContentNodeType.documentTitle:
        return typography
            .headingStyle(level: 1)
            .copyWith(
              fontSize: typography.fontSize * 1.5,
              fontWeight: FontWeight.bold,
            );
      case ContentNodeType.heading:
        if (node.attributes['kind'] == 'legalHeading') {
          return typography.bodyStyle().copyWith(
            fontSize: typography.fontSize * 0.95,
            fontWeight: FontWeight.bold,
            height: 1.55,
          );
        }
        return typography.headingStyle(level: node.level);
      case ContentNodeType.sectionHeading:
        return typography
            .headingStyle(level: 2)
            .copyWith(
              fontSize: typography.fontSize * 1.15,
              fontWeight: FontWeight.bold,
            );
      case ContentNodeType.quote:
        return typography.quoteStyle();
      case ContentNodeType.footnote:
      case ContentNodeType.caption:
        return typography.bodyStyle().copyWith(
          fontSize: typography.fontSize * 0.85,
          fontStyle: FontStyle.italic,
        );
      case ContentNodeType.orderedList:
        if (node.attributes['legalClause'] == true) {
          return typography.bodyStyle().copyWith(
            fontSize: typography.fontSize * 0.80,
            height: 1.55,
          );
        }
        return typography.bodyStyle();
      case ContentNodeType.copyrightBlock:
        return typography.bodyStyle().copyWith(
          fontSize: typography.fontSize * 0.78,
          height: 1.55,
        );
      case ContentNodeType.metadataBlock:
        final kind = node.attributes['kind'] as String? ?? '';
        final factor = switch (kind) {
          'publisherLogo' || 'publisher' => 0.72,
          'subtitle' => 0.95,
          'author' => 1.08,
          'credential' => 0.76,
          'badge' => 0.68,
          'label' => 0.82,
          'publisherSlogan' => 0.92,
          'tocChapterLabel' => 0.70,
          'tocChapterTitle' => 1.02,
          'tocPerson' => 0.82,
          'tocEntry' => 0.88,
          'frontMatterFooter' => 0.70,
          'legalHeading' => 0.95,
          _ => 0.80,
        };
        return typography.bodyStyle().copyWith(
          fontSize: typography.fontSize * factor,
          height: 1.55,
        );
      default:
        return typography.bodyStyle();
    }
  }

  static double paddingFor(ContentNode node, TypographySettings typography) {
    switch (node.type) {
      case ContentNodeType.footnote:
      case ContentNodeType.caption:
        return 4.0 + (typography.paragraphSpacing * 0.5);
      case ContentNodeType.orderedList:
        if (node.attributes['legalClause'] == true) {
          return 5.0;
        }
        return typography.paragraphSpacing * 0.6;
      case ContentNodeType.unorderedList:
      case ContentNodeType.listItem:
        return typography.paragraphSpacing * 0.6;
      case ContentNodeType.quote:
        return 8.0 + typography.paragraphSpacing;
      case ContentNodeType.copyrightBlock:
      case ContentNodeType.metadataBlock:
        final hasSectionLabel =
            (node.attributes['sectionLabel'] as String?)?.isNotEmpty == true;
        return (hasSectionLabel ? 22.0 : 6.0) +
            (typography.paragraphSpacing * 0.5);
      default:
        return typography.paragraphSpacing;
    }
  }

  static double _headingAdvanceHeight(
    ContentNode node,
    TypographySettings typography,
    double contentWidth,
  ) {
    final text = node.text.trim();
    if (text.isEmpty) return 0.0;
    return _measureTextHeight(
          text,
          textStyleFor(node, typography),
          contentWidth,
        ) +
        8.0 +
        (typography.paragraphSpacing * 1.2);
  }

  /// Full height of a block as it would appear on an empty page. Used by the
  /// explicit `keepWithNext` composition hint.
  static double _fullBlockHeightFor(
    ContentNode node,
    TypographySettings typography,
    double contentWidth,
  ) {
    if (node.type == ContentNodeType.image) {
      return _minimumSliceHeightFor(node, typography, contentWidth);
    }
    final text = node.text.trim();
    if (text.isEmpty) return 0.0;
    if (_isHeadingNode(node.type)) {
      return _headingAdvanceHeight(node, typography, contentWidth);
    }
    return _measureTextHeight(
          text,
          textStyleFor(node, typography),
          contentWidth,
        ) +
        paddingFor(node, typography);
  }

  /// Height of the next non-empty block for a `keepWithNext` composition hint.
  static double _keepWithNextBlockHeight({
    required List<ContentNode> nodes,
    required int nodeIdx,
    required TypographySettings typography,
    required double contentWidth,
  }) {
    var i = nodeIdx + 1;
    while (i < nodes.length) {
      final next = nodes[i];
      if (next.type == ContentNodeType.pageBreak) return 0.0;
      if (next.type == ContentNodeType.image) {
        return _fullBlockHeightFor(next, typography, contentWidth);
      }
      if (next.text.trim().isEmpty) {
        i++;
        continue;
      }
      return _fullBlockHeightFor(next, typography, contentWidth);
    }
    return 0.0;
  }

  /// Minimum height the next block needs on the same page as a heading.
  static double _minimumSliceHeightFor(
    ContentNode node,
    TypographySettings typography,
    double contentWidth,
  ) {
    if (node.type == ContentNodeType.image) {
      final hasCaption = node.text.trim().isNotEmpty;
      return 220.0 + (hasCaption ? 28.0 : 0.0) + typography.paragraphSpacing;
    }
    final text = node.text.trim();
    if (text.isEmpty) return 0.0;
    if (_isHeadingNode(node.type)) {
      return _headingAdvanceHeight(node, typography, contentWidth);
    }

    final isNormalPara = _isNormalParagraph(node);
    final fullHeight = _measureTextHeight(
      text,
      textStyleFor(node, typography),
      contentWidth,
      firstLineIndent: isNormalPara ? typography.firstLineIndent : 0.0,
    );
    final padding = paddingFor(node, typography);
    if (_isAtomicNode(node, text)) return fullHeight + padding;

    final lineHeight = typography.fontSize * typography.lineSpacing;
    return math.min(fullHeight, lineHeight * 3.0) + padding;
  }

  /// Height that must remain after a heading so it is never the last slice on a
  /// page. Consecutive headings are chained; an explicit page break ends the
  /// chain because there is no following text to keep with.
  static double _keepWithNextHeight({
    required List<ContentNode> nodes,
    required int nodeIdx,
    required TypographySettings typography,
    required double contentWidth,
  }) {
    var budget = 0.0;
    var i = nodeIdx + 1;
    while (i < nodes.length) {
      final next = nodes[i];
      if (next.type == ContentNodeType.pageBreak) return budget;
      if (next.type == ContentNodeType.image) {
        budget += _minimumSliceHeightFor(next, typography, contentWidth);
        return budget;
      }
      if (next.text.trim().isEmpty) {
        i++;
        continue;
      }
      if (_isHeadingNode(next.type)) {
        budget += _headingAdvanceHeight(next, typography, contentWidth);
        i++;
        continue;
      }
      budget += _minimumSliceHeightFor(next, typography, contentWidth);
      return budget;
    }
    return budget;
  }

  /// Measures exact rendered height of text using Flutter's native [TextPainter].
  static double _measureTextHeight(
    String text,
    TextStyle style,
    double maxWidth, {
    double firstLineIndent = 0.0,
  }) {
    if (text.isEmpty) return 0.0;
    final TextPainter textPainter;
    if (firstLineIndent > 0.0) {
      final fontSize = style.fontSize ?? 18.0;
      textPainter = TextPainter(
        text: TextSpan(
          children: [
            WidgetSpan(
              child: SizedBox(width: firstLineIndent, height: fontSize),
            ),
            TextSpan(text: text, style: style),
          ],
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(firstLineIndent, fontSize),
          alignment: PlaceholderAlignment.bottom,
        ),
      ]);
    } else {
      textPainter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      );
    }
    textPainter.layout(maxWidth: maxWidth);
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
    double firstLineIndent = 0.0,
  }) {
    if (text.isEmpty || maxHeight <= 0) return 0;

    final TextPainter textPainter;
    if (firstLineIndent > 0.0) {
      final fontSize = style.fontSize ?? 18.0;
      textPainter = TextPainter(
        text: TextSpan(
          children: [
            WidgetSpan(
              child: SizedBox(width: firstLineIndent, height: fontSize),
            ),
            TextSpan(text: text, style: style),
          ],
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(firstLineIndent, fontSize),
          alignment: PlaceholderAlignment.bottom,
        ),
      ]);
    } else {
      textPainter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      );
    }
    textPainter.layout(maxWidth: maxWidth);

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

      final textPos = textPainter.getPositionForOffset(
        Offset(maxWidth, targetLineMid),
      );
      int candidateOffset = (firstLineIndent > 0.0)
          ? math.max(0, textPos.offset - 1).clamp(0, text.length)
          : textPos.offset.clamp(0, text.length);

      // Snap backward to whitespace boundary
      while (candidateOffset > 0 &&
          candidateOffset < text.length &&
          text[candidateOffset].trim().isNotEmpty) {
        candidateOffset--;
      }

      // Verify with sub-TextPainter that candidate slice does not exceed targetLines or maxHeight
      while (candidateOffset > 0) {
        final TextPainter subTp;
        if (firstLineIndent > 0.0) {
          final fontSize = style.fontSize ?? 18.0;
          subTp = TextPainter(
            text: TextSpan(
              children: [
                WidgetSpan(
                  child: SizedBox(width: firstLineIndent, height: fontSize),
                ),
                TextSpan(
                  text: text.substring(0, candidateOffset).trimRight(),
                  style: style,
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          );
          subTp.setPlaceholderDimensions([
            PlaceholderDimensions(
              size: Size(firstLineIndent, fontSize),
              alignment: PlaceholderAlignment.bottom,
            ),
          ]);
        } else {
          subTp = TextPainter(
            text: TextSpan(
              text: text.substring(0, candidateOffset).trimRight(),
              style: style,
            ),
            textDirection: TextDirection.ltr,
          );
        }
        subTp.layout(maxWidth: maxWidth);
        final subLines = subTp.computeLineMetrics().length;
        final subHeight = subTp.height;
        subTp.dispose();

        if (subLines <= targetLines &&
            (subHeight <= maxHeight || isFreshPage)) {
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
