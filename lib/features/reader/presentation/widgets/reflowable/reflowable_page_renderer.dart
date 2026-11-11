import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'highlight_interaction_sheet.dart';

typedef HighlightCreationCallback =
    void Function({
      required String text,
      required String color,
      String? note,
      required String anchorNodeId,
      required int startOffset,
      required int endOffset,
      String? prefixContext,
      String? suffixContext,
      required int pageNumber,
    });

class ReflowablePageRenderer extends StatelessWidget {
  final PaginatedPage page;
  final int totalPagesInBook;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final double contentWidth;
  final bool showHeader;
  final bool showFooter;
  final bool isLeftPage;
  final List<Highlight> highlights;
  final List<ActiveSearchMatch> searchMatches;
  final HighlightCreationCallback? onHighlightCreated;
  final void Function(Highlight highlight)? onHighlightTap;

  const ReflowablePageRenderer({
    super.key,
    required this.page,
    required this.totalPagesInBook,
    required this.theme,
    required this.typography,
    required this.contentWidth,
    this.showHeader = true,
    this.showFooter = true,
    this.isLeftPage = false,
    this.highlights = const [],
    this.searchMatches = const [],
    this.onHighlightCreated,
    this.onHighlightTap,
  });

  @override
  Widget build(BuildContext context) {
    // Find if any slice has a source PDF page citation
    final sourcePdfPages = page.slices
        .map((s) => s.node.sourcePdfPage)
        .where((p) => p > 0)
        .toSet();
    final sourcePdfText = sourcePdfPages.isNotEmpty
        ? ' (PDF hal. ${sourcePdfPages.join(', ')})'
        : '';

    final hasFrontMatter = page.slices.any(
      (s) => s.node.attributes['frontMatter'] != null,
    );
    final isCoverPage = page.slices.any(
      (s) => s.node.attributes['frontMatter'] == 'cover',
    );
    final isTitlePage = page.slices.any(
      (s) => s.node.attributes['frontMatter'] == 'titlePage',
    );
    final effectiveShowHeader = showHeader && !hasFrontMatter;
    final effectiveShowFooter = showFooter && !isCoverPage && !isTitlePage;
    final isSloganPage =
        page.slices.isNotEmpty &&
        page.slices.every(
          (s) => s.node.attributes['kind'] == 'publisherSlogan',
        );
    final centerFrontMatter = hasFrontMatter || isSloganPage;

    return Container(
      width: contentWidth,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Running Header
          if (effectiveShowHeader)
            SizedBox(
              height: 28,
              child: Align(
                alignment: isLeftPage
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Text(
                  page.chapterTitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: theme.secondaryTextColor.withAlpha(160),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 28),

          // 2. Main Page Content (Slices)
          //
          // Pagination measures text with TextPainter, but SelectableText can
          // render a few pixels taller on dense pages. Scale the completed page
          // down by at most a fraction of a percent instead of clipping the last
          // line. This is a safety net, not a scrolling region: vertical
          // scrolling remains disabled in Book Mode.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: centerFrontMatter
                  ? Alignment.center
                  : Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: page.slices
                      .map((slice) => _buildSliceWidget(context, slice))
                      .toList(),
                ),
              ),
            ),
          ),

          // 3. Running Footer
          if (effectiveShowFooter)
            SizedBox(
              height: 24,
              child: Center(
                child: Text(
                  '${page.pageIndexInBook + 1} / $totalPagesInBook$sourcePdfText',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                    color: theme.secondaryTextColor.withAlpha(160),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSliceWidget(BuildContext context, PaginatedNodeSlice slice) {
    final node = slice.node;

    // Image Node
    if (node.type == ContentNodeType.image) {
      return Padding(
        padding: EdgeInsets.only(bottom: typography.paragraphSpacing),
        child: _buildImageWidget(node),
      );
    }

    final highlightsForNode = highlights
        .where(
          (h) =>
              h.anchorNodeId == node.id ||
              (h.anchorNodeId == null && h.chapterId == node.id),
        )
        .toList();
    final searchMatchesForNode = searchMatches
        .where((sm) => sm.nodeId == node.id)
        .toList();

    // Document Title Node
    if (node.type == ContentNodeType.documentTitle) {
      final kind = node.attributes['kind'] as String? ?? '';
      final isMainTitle = kind == 'mainTitle';
      final isEnglishTitle = kind == 'englishTitle';
      final style = typography
          .headingStyle(level: 1, color: theme.textColor)
          .copyWith(
            fontSize:
                typography.fontSize *
                (isMainTitle ? 1.35 : (isEnglishTitle ? 0.74 : 1.35)),
            fontWeight: FontWeight.bold,
            height: isMainTitle ? 1.18 : 1.35,
            letterSpacing: isEnglishTitle ? 1.8 : 0.5,
            color: isEnglishTitle ? theme.secondaryTextColor : theme.textColor,
          );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      final topPadding = isMainTitle
          ? (node.attributes['frontMatter'] == 'cover' ? 36.0 : 20.0)
          : 8.0;
      return Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: isMainTitle ? 14 : 6),
        child: Column(
          children: [
            SelectableText.rich(
              richSpan,
              textAlign: TextAlign.center,
              contextMenuBuilder: (ctx, editableTextState) =>
                  _buildContextMenu(ctx, editableTextState, slice),
            ),
            if (!isEnglishTitle) ...[
              const SizedBox(height: 12),
              Container(
                width: isMainTitle ? 64 : 50,
                height: 2,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Section Heading Node (H2 / Subheadings)
    if (node.type == ContentNodeType.sectionHeading) {
      final style = typography
          .headingStyle(level: 2, color: theme.textColor)
          .copyWith(
            fontSize: typography.fontSize * 1.15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: const EdgeInsets.only(top: 14.0, bottom: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3.5,
              height: typography.fontSize * 1.15,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SelectableText.rich(
                richSpan,
                textAlign: TextAlign.left,
                contextMenuBuilder: (ctx, editableTextState) =>
                    _buildContextMenu(ctx, editableTextState, slice),
              ),
            ),
          ],
        ),
      );
    }

    // Legal numbered clause (front matter). Legal text uses a plain hanging
    // number rather than the decorative list badge used for body content.
    if (node.type == ContentNodeType.orderedList &&
        node.attributes['legalClause'] == true) {
      final itemText = slice.textSlice.trim();
      final markerText = node.attributes['listMarker'] as String? ?? '';
      final markerPattern = markerText.isNotEmpty
          ? RegExp('^${RegExp.escape(markerText)}\\s*')
          : RegExp(r'^(\d+[\.\)])\s*');
      final match = markerPattern.firstMatch(itemText);
      final marker =
          match?.group(0)?.trim() ?? (markerText.isNotEmpty ? markerText : '•');
      final content = match != null ? itemText.substring(match.end) : itemText;
      final style = typography
          .bodyStyle(color: theme.secondaryTextColor)
          .copyWith(fontSize: typography.fontSize * 0.80, height: 1.55);
      final consumed = itemText.length - content.length;
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: content,
        sliceStartOffset: slice.startCharOffset + consumed,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: const EdgeInsets.only(left: 6, right: 8, bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                marker,
                textAlign: TextAlign.right,
                style: style.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText.rich(
                richSpan,
                textAlign: TextAlign.left,
                contextMenuBuilder: (ctx, editableTextState) =>
                    _buildContextMenu(ctx, editableTextState, slice),
              ),
            ),
          ],
        ),
      );
    }

    // Ordered List Item Node
    if (node.type == ContentNodeType.orderedList ||
        node.type == ContentNodeType.listItem) {
      final itemText = slice.textSlice.trim();
      final match = RegExp(
        r'^(\d+[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]+\))\s*(.*)$',
        dotAll: true,
      ).firstMatch(itemText);
      final marker = match?.group(1) ?? '•';
      final content = match?.group(2) ?? itemText;

      final style = typography.bodyStyle(color: theme.textColor);
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: content,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(
          left: 12.0,
          right: 4.0,
          bottom: typography.paragraphSpacing * 0.5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                marker,
                textAlign: TextAlign.right,
                style: typography
                    .bodyStyle(color: theme.secondaryTextColor)
                    .copyWith(
                      fontSize: typography.fontSize * 0.90,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText.rich(
                richSpan,
                textAlign: typography.textAlign,
                contextMenuBuilder: (ctx, editableTextState) =>
                    _buildContextMenu(ctx, editableTextState, slice),
              ),
            ),
          ],
        ),
      );
    }

    // Unordered List Item Node
    if (node.type == ContentNodeType.unorderedList) {
      final style = typography.bodyStyle(color: theme.textColor);
      final rawText = slice.textSlice.trim();
      final bulletMatch = RegExp(
        r'^([•\-\*–—]|[\u2022\u2023\u25E6\u2043\u2219])\s*(.*)$',
        dotAll: true,
      ).firstMatch(rawText);
      final content = bulletMatch?.group(2) ?? rawText;

      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: content,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(
          left: 12.0,
          right: 4.0,
          bottom: typography.paragraphSpacing * 0.5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Text(
                '•',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: typography.fontSize,
                  color: const Color(0xFFD4AF37),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText.rich(
                richSpan,
                textAlign: typography.textAlign,
                contextMenuBuilder: (ctx, editableTextState) =>
                    _buildContextMenu(ctx, editableTextState, slice),
              ),
            ),
          ],
        ),
      );
    }

    // Caption Node
    if (node.type == ContentNodeType.caption) {
      final style = typography
          .bodyStyle(color: theme.secondaryTextColor)
          .copyWith(
            fontSize: typography.fontSize * 0.85,
            fontStyle: FontStyle.italic,
          );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Center(
          child: SelectableText.rich(
            richSpan,
            textAlign: TextAlign.center,
            contextMenuBuilder: (ctx, editableTextState) =>
                _buildContextMenu(ctx, editableTextState, slice),
          ),
        ),
      );
    }

    // Copyright / Metadata Block Node
    if (node.type == ContentNodeType.copyrightBlock ||
        node.type == ContentNodeType.metadataBlock) {
      final kind = node.attributes['kind'] as String? ?? '';
      if (kind == 'tocPerson') {
        final name = (node.attributes['tocTitle'] as String?) ?? node.text;
        final page = (node.attributes['tocPage'] as String?) ?? '';
        return Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typography
                      .bodyStyle(color: theme.secondaryTextColor)
                      .copyWith(
                        fontSize: typography.fontSize * 0.82,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
              if (page.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  page,
                  style: typography
                      .bodyStyle(color: theme.secondaryTextColor)
                      .copyWith(
                        fontSize: typography.fontSize * 0.80,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        );
      }
      if (kind == 'tocEntry') {
        final tocTitle = (node.attributes['tocTitle'] as String?) ?? node.text;
        final tocPage = (node.attributes['tocPage'] as String?) ?? '';
        final titleStyle = typography
            .bodyStyle(color: theme.textColor)
            .copyWith(fontSize: typography.fontSize * 0.88, height: 1.45);
        final pageStyle = typography
            .bodyStyle(color: theme.secondaryTextColor)
            .copyWith(
              fontSize: typography.fontSize * 0.82,
              fontWeight: FontWeight.w600,
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  tocTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRect(
                  child: Text(
                    '.' * 120,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: typography.fontSize * 0.82,
                      height: 1.45,
                      letterSpacing: 2.0,
                      color: theme.secondaryTextColor.withAlpha(70),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 34,
                child: Text(
                  tocPage,
                  textAlign: TextAlign.right,
                  style: pageStyle,
                ),
              ),
            ],
          ),
        );
      }
      var factor = 0.80;
      var weight = FontWeight.normal;
      var fontStyle = FontStyle.normal;
      var color = theme.secondaryTextColor;
      var align = TextAlign.left;
      var letterSpacing = 0.2;
      var padding = const EdgeInsets.symmetric(vertical: 6.0);

      switch (kind) {
        case 'tocChapterLabel':
          factor = 0.70;
          weight = FontWeight.bold;
          color = const Color(0xFFD4AF37);
          letterSpacing = 1.5;
          padding = const EdgeInsets.only(top: 16, bottom: 2);
          break;
        case 'tocChapterTitle':
          factor = 1.02;
          weight = FontWeight.bold;
          color = theme.textColor;
          padding = const EdgeInsets.only(top: 2, bottom: 7);
          break;
        case 'publisherLogo':
          factor = 0.72;
          weight = FontWeight.w600;
          letterSpacing = 1.6;
          align = TextAlign.center;
          padding = const EdgeInsets.only(top: 4, bottom: 12);
          break;
        case 'subtitle':
          factor = 0.95;
          letterSpacing = 0.6;
          align = TextAlign.center;
          padding = const EdgeInsets.only(top: 4, bottom: 10);
          break;
        case 'author':
          factor = 1.08;
          weight = FontWeight.bold;
          color = theme.textColor;
          align = TextAlign.center;
          padding = const EdgeInsets.only(top: 12, bottom: 2);
          break;
        case 'credential':
          factor = 0.76;
          fontStyle = FontStyle.italic;
          align = TextAlign.center;
          padding = const EdgeInsets.only(bottom: 12);
          break;
        case 'badge':
          factor = 0.68;
          weight = FontWeight.bold;
          color = const Color(0xFFD4AF37);
          letterSpacing = 1.4;
          align = TextAlign.center;
          padding = const EdgeInsets.only(bottom: 12);
          break;
        case 'label':
          factor = 0.82;
          align = TextAlign.center;
          padding = const EdgeInsets.only(top: 12, bottom: 2);
          break;
        case 'publisher':
          factor = 0.72;
          letterSpacing = 1.3;
          align = TextAlign.center;
          padding = const EdgeInsets.only(top: 18, bottom: 12);
          break;
        case 'publisherSlogan':
          factor = 0.92;
          fontStyle = FontStyle.italic;
          align = TextAlign.center;
          padding = const EdgeInsets.symmetric(vertical: 12);
          break;
        case 'legalHeading':
          factor = 0.95;
          weight = FontWeight.bold;
          color = theme.textColor;
          padding = const EdgeInsets.only(top: 18, bottom: 6);
          break;
        case 'frontMatterFooter':
          factor = 0.70;
          letterSpacing = 0.4;
          align = TextAlign.center;
          padding = const EdgeInsets.only(top: 16);
          break;
        default:
          if (node.type == ContentNodeType.copyrightBlock) {
            factor = 0.78;
            padding = const EdgeInsets.symmetric(vertical: 5.0);
          }
          break;
      }

      final style = typography
          .bodyStyle(color: color)
          .copyWith(
            fontSize: typography.fontSize * factor,
            height: 1.55,
            letterSpacing: letterSpacing,
            fontWeight: weight,
            fontStyle: fontStyle,
          );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      final sectionLabel = node.attributes['sectionLabel'] as String?;
      final content = SelectableText.rich(
        richSpan,
        textAlign: align,
        contextMenuBuilder: (ctx, editableTextState) =>
            _buildContextMenu(ctx, editableTextState, slice),
      );
      return Padding(
        padding: padding,
        child: sectionLabel == null || sectionLabel.isEmpty
            ? content
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sectionLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: typography.fontSize * 0.62,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFD4AF37),
                    ),
                  ),
                  const SizedBox(height: 4),
                  content,
                ],
              ),
      );
    }

    // Chapter opening: split the OCR marker ("BAB I:") from the title so the
    // page reads like a book chapter opener instead of a giant all-caps blob.
    if (node.type == ContentNodeType.heading && node.level == 1) {
      final fullText = slice.textSlice.trim();
      final match = RegExp(
        r'^(BAB|CHAPTER)\s+([IVXLCDM0-9]+)\s*:\s*(.+)$',
        dotAll: true,
      ).firstMatch(fullText);
      final titleText = match?.group(3);
      if (match != null && titleText != null) {
        final title = titleText.trim();
        final titleIndex = fullText.indexOf(titleText);
        final titleStyle = typography
            .headingStyle(level: 1, color: theme.textColor)
            .copyWith(
              fontSize: typography.fontSize * 1.22,
              height: 1.28,
              letterSpacing: 0.2,
            );
        final titleSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
          text: title,
          sliceStartOffset: slice.startCharOffset + titleIndex,
          sliceEndOffset: slice.endCharOffset,
          highlightsForNode: highlightsForNode,
          searchMatchesForNode: searchMatchesForNode,
          baseStyle: titleStyle,
          theme: theme,
          onHighlightTap: onHighlightTap,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${match.group(1)!.toUpperCase()} ${match.group(2)}',
                style: TextStyle(
                  fontSize: typography.fontSize * 0.68,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(height: 7),
              SelectableText.rich(
                titleSpan,
                textAlign: TextAlign.left,
                contextMenuBuilder: (ctx, editableTextState) =>
                    _buildContextMenu(ctx, editableTextState, slice),
              ),
            ],
          ),
        );
      }
    }

    // Heading Node
    if (node.type == ContentNodeType.heading) {
      final style = typography.headingStyle(
        level: node.level,
        color: theme.textColor,
      );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(
          top: slice.isContinuation ? 0 : 8,
          bottom: typography.paragraphSpacing * 1.2,
        ),
        child: SelectableText.rich(
          richSpan,
          textAlign: TextAlign.left,
          contextMenuBuilder: (ctx, editableTextState) =>
              _buildContextMenu(ctx, editableTextState, slice),
        ),
      );
    }

    // Quote Node
    if (node.type == ContentNodeType.quote) {
      final style = typography.quoteStyle(
        color: theme.textColor.withAlpha(210),
      );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(bottom: typography.paragraphSpacing),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.isDark
                    ? const Color(0xFFD4AF37).withAlpha(180)
                    : const Color(0xFFB8860B).withAlpha(200),
                width: 3.0,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
          child: SelectableText.rich(
            richSpan,
            textAlign: typography.textAlign,
            contextMenuBuilder: (ctx, editableTextState) =>
                _buildContextMenu(ctx, editableTextState, slice),
          ),
        ),
      );
    }

    // Footnote Node
    if (node.type == ContentNodeType.footnote) {
      final style = typography
          .bodyStyle(color: theme.secondaryTextColor)
          .copyWith(
            fontSize: typography.fontSize * 0.85,
            fontStyle: FontStyle.italic,
          );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(
          top: 4,
          bottom: typography.paragraphSpacing * 0.6,
        ),
        child: SelectableText.rich(
          richSpan,
          textAlign: typography.textAlign,
          contextMenuBuilder: (ctx, editableTextState) =>
              _buildContextMenu(ctx, editableTextState, slice),
        ),
      );
    }

    // Table-of-contents entry. TOC lines are denser and should not inherit the
    // body paragraph rhythm; the semantic stage still uses bodyParagraph to
    // preserve anchors and search offsets.
    if (node.type == ContentNodeType.paragraph &&
        node.attributes['isTocEntry'] == true) {
      final tocStyle = typography
          .bodyStyle(color: theme.textColor)
          .copyWith(fontSize: typography.fontSize * 0.88, height: 1.50);
      final tocSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: slice.textSlice,
        sliceStartOffset: slice.startCharOffset,
        sliceEndOffset: slice.endCharOffset,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: tocStyle,
        theme: theme,
        onHighlightTap: onHighlightTap,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SelectableText.rich(
          tocSpan,
          textAlign: TextAlign.left,
          contextMenuBuilder: (ctx, editableTextState) =>
              _buildContextMenu(ctx, editableTextState, slice),
        ),
      );
    }

    // Default Paragraph Node
    final isNormal =
        node.type == ContentNodeType.paragraph &&
        node.attributes['isTocEntry'] != true &&
        node.attributes['kind'] != 'publisherSlogan' &&
        node.attributes['frontMatter'] == null;
    final applyFirstLineIndent = isNormal && !slice.isContinuation;

    final style = typography.bodyStyle(color: theme.textColor);
    final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
      text: slice.textSlice,
      sliceStartOffset: slice.startCharOffset,
      sliceEndOffset: slice.endCharOffset,
      highlightsForNode: highlightsForNode,
      searchMatchesForNode: searchMatchesForNode,
      baseStyle: style,
      theme: theme,
      firstLineIndent: applyFirstLineIndent ? typography.firstLineIndent : 0.0,
      onHighlightTap: onHighlightTap,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: typography.paragraphSpacing),
      child: SelectableText.rich(
        richSpan,
        textAlign: typography.textAlign,
        contextMenuBuilder: (ctx, editableTextState) =>
            _buildContextMenu(ctx, editableTextState, slice),
      ),
    );
  }

  Widget _buildImageWidget(ContentNode node) {
    if (node.imagePath != null && node.imagePath!.isNotEmpty) {
      final file = File(node.imagePath!);
      if (file.existsSync()) {
        final hasCaption = node.text.trim().isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildPlaceholderImage(),
                ),
              ),
            ),
            if (hasCaption) ...[
              const SizedBox(height: 6),
              Text(
                node.text.trim(),
                style: TextStyle(
                  fontSize: typography.fontSize * 0.85,
                  color: theme.secondaryTextColor,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      }
    }
    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: theme.isDark
            ? Colors.white.withAlpha(15)
            : Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.secondaryTextColor.withAlpha(40)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 32,
              color: theme.secondaryTextColor.withAlpha(150),
            ),
            const SizedBox(height: 6),
            Text(
              'Ilustrasi Buku',
              style: TextStyle(fontSize: 12, color: theme.secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
    PaginatedNodeSlice slice,
  ) {
    final selection = editableTextState.textEditingValue.selection;
    final rawText = selection.textInside(
      editableTextState.textEditingValue.text,
    );
    final text = rawText.replaceAll('\uFFFC', '');

    if (text.trim().isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: editableTextState.contextMenuButtonItems,
      );
    }

    final isNormal =
        slice.node.type == ContentNodeType.paragraph &&
        slice.node.attributes['isTocEntry'] != true &&
        slice.node.attributes['kind'] != 'publisherSlogan' &&
        slice.node.attributes['frontMatter'] == null;
    final hasIndent = isNormal && !slice.isContinuation;
    final indentShift = hasIndent ? 1 : 0;

    final localStart = math.max(0, selection.start - indentShift);
    final localEnd = math.max(0, selection.end - indentShift);
    final absStart = (slice.startCharOffset + localStart).clamp(
      0,
      slice.node.text.length,
    );
    final absEnd = (slice.startCharOffset + localEnd).clamp(
      absStart,
      slice.node.text.length,
    );

    final pStart = math.max(0, absStart - 32);
    final prefixContext = slice.node.text.substring(pStart, absStart);

    final sEnd = math.min(slice.node.text.length, absEnd + 32);
    final suffixContext = slice.node.text.substring(absEnd, sEnd);

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        ...editableTextState.contextMenuButtonItems,
        ContextMenuButtonItem(
          label: '🟡 Kuning',
          onPressed: () {
            onHighlightCreated?.call(
              text: text.trim(),
              color: 'yellow',
              anchorNodeId: slice.node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: page.pageIndexInBook + 1,
            );
            editableTextState.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🟢 Hijau',
          onPressed: () {
            onHighlightCreated?.call(
              text: text.trim(),
              color: 'green',
              anchorNodeId: slice.node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: page.pageIndexInBook + 1,
            );
            editableTextState.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🔵 Biru',
          onPressed: () {
            onHighlightCreated?.call(
              text: text.trim(),
              color: 'blue',
              anchorNodeId: slice.node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: page.pageIndexInBook + 1,
            );
            editableTextState.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🔴 Merah Muda',
          onPressed: () {
            onHighlightCreated?.call(
              text: text.trim(),
              color: 'pink',
              anchorNodeId: slice.node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: page.pageIndexInBook + 1,
            );
            editableTextState.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🟣 Ungu',
          onPressed: () {
            onHighlightCreated?.call(
              text: text.trim(),
              color: 'purple',
              anchorNodeId: slice.node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: page.pageIndexInBook + 1,
            );
            editableTextState.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '📝 Catatan',
          onPressed: () {
            editableTextState.hideToolbar();
            HighlightInteractionSheet.show(
              context: context,
              selectedText: text.trim(),
              theme: theme,
              onSave: (color, note) {
                onHighlightCreated?.call(
                  text: text.trim(),
                  color: color,
                  note: note,
                  anchorNodeId: slice.node.id,
                  startOffset: absStart,
                  endOffset: absEnd,
                  prefixContext: prefixContext,
                  suffixContext: suffixContext,
                  pageNumber: page.pageIndexInBook + 1,
                );
              },
            );
          },
        ),
      ],
    );
  }
}
