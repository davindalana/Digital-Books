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

    return Container(
      width: contentWidth,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Running Header
          if (showHeader)
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
              alignment: Alignment.topCenter,
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
          if (showFooter)
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
      final style = typography
          .headingStyle(level: 1, color: theme.textColor)
          .copyWith(
            fontSize: typography.fontSize * 1.45,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
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
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            SelectableText.rich(
              richSpan,
              textAlign: TextAlign.center,
              contextMenuBuilder: (ctx, editableTextState) =>
                  _buildContextMenu(ctx, editableTextState, slice),
            ),
            const SizedBox(height: 10),
            Container(
              width: 50,
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
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
            Container(
              constraints: const BoxConstraints(minWidth: 26),
              margin: const EdgeInsets.only(right: 8, top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFD4AF37,
                ).withAlpha(theme.isDark ? 30 : 20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(
                    0xFFD4AF37,
                  ).withAlpha(theme.isDark ? 80 : 60),
                  width: 0.8,
                ),
              ),
              child: Text(
                marker,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: typography.fontSize * 0.75,
                  fontWeight: FontWeight.bold,
                  color: theme.isDark
                      ? const Color(0xFFE5C058)
                      : const Color(0xFF996515),
                ),
              ),
            ),
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
            Container(
              margin: const EdgeInsets.only(left: 6, right: 12, top: 7),
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFD4AF37),
                shape: BoxShape.circle,
              ),
            ),
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
      final style = typography
          .bodyStyle(color: theme.secondaryTextColor)
          .copyWith(
            fontSize: typography.fontSize * 0.82,
            height: 1.5,
            letterSpacing: 0.2,
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
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: SelectableText.rich(
          richSpan,
          textAlign: TextAlign.left,
          contextMenuBuilder: (ctx, editableTextState) =>
              _buildContextMenu(ctx, editableTextState, slice),
        ),
      );
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

    // Default Paragraph Node
    final style = typography.bodyStyle(color: theme.textColor);
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
    final text = selection.textInside(editableTextState.textEditingValue.text);

    if (text.trim().isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: editableTextState.contextMenuButtonItems,
      );
    }

    final localStart = selection.start;
    final localEnd = selection.end;
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
