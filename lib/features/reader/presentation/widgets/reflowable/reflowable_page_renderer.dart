import 'dart:io';
import 'package:flutter/material.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';

class ReflowablePageRenderer extends StatelessWidget {
  final PaginatedPage page;
  final int totalPagesInBook;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final double contentWidth;
  final bool showHeader;
  final bool showFooter;
  final bool isLeftPage;
  final Function(String text, String color, int pageNumber)? onHighlightCreated;

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
    this.onHighlightCreated,
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
                alignment: isLeftPage ? Alignment.centerLeft : Alignment.centerRight,
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
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: page.slices.map((slice) => _buildSliceWidget(context, slice)).toList(),
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

    // Heading Node
    if (node.type == ContentNodeType.heading) {
      final style = typography.headingStyle(
        level: node.level,
        color: theme.textColor,
      );
      return Padding(
        padding: EdgeInsets.only(
          top: slice.isContinuation ? 0 : 8,
          bottom: typography.paragraphSpacing * 1.2,
        ),
        child: SelectableText(
          slice.textSlice,
          style: style,
          textAlign: typography.textAlign,
          contextMenuBuilder: (ctx, editableTextState) =>
              _buildContextMenu(ctx, editableTextState),
        ),
      );
    }

    // Quote Node
    if (node.type == ContentNodeType.quote) {
      final style = typography.quoteStyle(
        color: theme.textColor.withAlpha(210),
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
          child: SelectableText(
            slice.textSlice,
            style: style,
            textAlign: typography.textAlign,
            contextMenuBuilder: (ctx, editableTextState) =>
                _buildContextMenu(ctx, editableTextState),
          ),
        ),
      );
    }

    // Default Paragraph Node
    final style = typography.bodyStyle(color: theme.textColor);
    return Padding(
      padding: EdgeInsets.only(bottom: typography.paragraphSpacing),
      child: SelectableText(
        slice.textSlice,
        style: style,
        textAlign: typography.textAlign,
        contextMenuBuilder: (ctx, editableTextState) =>
            _buildContextMenu(ctx, editableTextState),
      ),
    );
  }

  Widget _buildImageWidget(ContentNode node) {
    if (node.imagePath != null && node.imagePath!.isNotEmpty) {
      final file = File(node.imagePath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
            ),
          ),
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
        border: Border.all(
          color: theme.secondaryTextColor.withAlpha(40),
        ),
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
              style: TextStyle(
                fontSize: 12,
                color: theme.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final text = editableTextState.textEditingValue.selection.textInside(
      editableTextState.textEditingValue.text,
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        ...editableTextState.contextMenuButtonItems,
        if (text.trim().isNotEmpty && onHighlightCreated != null)
          ContextMenuButtonItem(
            label: 'Sorot Emas',
            onPressed: () {
              onHighlightCreated!(text.trim(), 'gold', page.pageIndexInBook + 1);
              editableTextState.hideToolbar();
            },
          ),
        if (text.trim().isNotEmpty && onHighlightCreated != null)
          ContextMenuButtonItem(
            label: 'Sorot Kuning',
            onPressed: () {
              onHighlightCreated!(text.trim(), 'yellow', page.pageIndexInBook + 1);
              editableTextState.hideToolbar();
            },
          ),
      ],
    );
  }
}
