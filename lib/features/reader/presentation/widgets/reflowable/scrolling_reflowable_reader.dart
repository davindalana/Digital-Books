import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'highlight_interaction_sheet.dart';
import 'reflowable_page_renderer.dart';

enum _ScrollItemType { chapterHeader, node, chapterDivider }

class _ScrollItem {
  final _ScrollItemType type;
  final int chapterIndex;
  final String chapterTitle;
  final ContentNode? node;
  final String anchorId;
  final double estimatedHeight;

  const _ScrollItem({
    required this.type,
    required this.chapterIndex,
    required this.chapterTitle,
    this.node,
    required this.anchorId,
    required this.estimatedHeight,
  });
}

class ScrollingReflowableReader extends StatefulWidget {
  final ReaderDocument document;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final String? initialAnchorNodeId;
  final int initialChapterIndex;
  final VoidCallback onTapContent;
  final Function(
    int chapterIndex,
    int position,
    double percentage,
    String? anchorNodeId,
    int charOffset,
  )
  onProgressChanged;
  final List<Highlight> highlights;
  final List<ActiveSearchMatch> searchMatches;
  final HighlightCreationCallback? onHighlightCreated;
  final void Function(Highlight highlight)? onHighlightTap;

  const ScrollingReflowableReader({
    super.key,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialAnchorNodeId,
    this.initialChapterIndex = 0,
    required this.onTapContent,
    required this.onProgressChanged,
    this.highlights = const [],
    this.searchMatches = const [],
    this.onHighlightCreated,
    this.onHighlightTap,
  });

  @override
  State<ScrollingReflowableReader> createState() =>
      ScrollingReflowableReaderState();
}

class ScrollingReflowableReaderState extends State<ScrollingReflowableReader> {
  final ScrollController _scrollController = ScrollController();
  List<_ScrollItem> _flatItems = [];
  List<double> _cumulativeOffsets = [];
  Timer? _debounceTimer;

  String? _activeAnchorNodeId;
  int _activeChapterIndex = 0;

  String? get currentAnchorNodeId => _activeAnchorNodeId;
  int get currentChapterIndex => _activeChapterIndex;

  @override
  void initState() {
    super.initState();
    _activeAnchorNodeId = widget.initialAnchorNodeId;
    _activeChapterIndex = widget.initialChapterIndex;
    _buildFlatItemList();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToInitialPosition();
    });
  }

  @override
  void didUpdateWidget(covariant ScrollingReflowableReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.typography != widget.typography) {
      _buildFlatItemList();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _buildFlatItemList() {
    final items = <_ScrollItem>[];
    final offsets = <double>[];
    double runningOffset = 0.0;

    for (int chIdx = 0; chIdx < widget.document.chapters.length; chIdx++) {
      final chapter = widget.document.chapters[chIdx];

      // Chapter Header
      offsets.add(runningOffset);
      items.add(
        _ScrollItem(
          type: _ScrollItemType.chapterHeader,
          chapterIndex: chIdx,
          chapterTitle: chapter.title,
          anchorId: 'header_$chIdx',
          estimatedHeight: 120.0,
        ),
      );
      runningOffset += 120.0;

      // Chapter Nodes
      for (final node in chapter.nodes) {
        final estHeight = _estimateNodeHeight(node);
        offsets.add(runningOffset);
        items.add(
          _ScrollItem(
            type: _ScrollItemType.node,
            chapterIndex: chIdx,
            chapterTitle: chapter.title,
            node: node,
            anchorId: node.id,
            estimatedHeight: estHeight,
          ),
        );
        runningOffset += estHeight;
      }

      // Chapter Divider
      if (chIdx < widget.document.chapters.length - 1) {
        offsets.add(runningOffset);
        items.add(
          _ScrollItem(
            type: _ScrollItemType.chapterDivider,
            chapterIndex: chIdx,
            chapterTitle: chapter.title,
            anchorId: 'divider_$chIdx',
            estimatedHeight: 70.0,
          ),
        );
        runningOffset += 70.0;
      }
    }

    _flatItems = items;
    _cumulativeOffsets = offsets;
  }

  double _estimateNodeHeight(ContentNode node) {
    if (node.type == ContentNodeType.image) return 220.0;
    if (node.type == ContentNodeType.heading) return 70.0;
    if (node.type == ContentNodeType.quote) {
      final lineCount = (node.text.length / 45.0).ceil();
      return (lineCount * 24.0) + 24.0;
    }
    final lineCount = (node.text.length / 50.0).ceil();
    return (lineCount * 22.0) + widget.typography.paragraphSpacing;
  }

  void _jumpToInitialPosition() {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;

    if (_activeAnchorNodeId != null) {
      for (int i = 0; i < _flatItems.length; i++) {
        if (_flatItems[i].anchorId == _activeAnchorNodeId) {
          final targetOffset = _cumulativeOffsets[i];
          _scrollController.jumpTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
          return;
        }
      }
    }

    if (_activeChapterIndex > 0) {
      for (int i = 0; i < _flatItems.length; i++) {
        if (_flatItems[i].chapterIndex == _activeChapterIndex &&
            _flatItems[i].type == _ScrollItemType.chapterHeader) {
          final targetOffset = _cumulativeOffsets[i];
          _scrollController.jumpTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
          return;
        }
      }
    }
  }

  void scrollToAnchor(String anchorNodeId) {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;

    for (int i = 0; i < _flatItems.length; i++) {
      if (_flatItems[i].anchorId == anchorNodeId) {
        final targetOffset = _cumulativeOffsets[i];
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
  }

  void jumpToChapter(int chapterIndex) {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;
    for (int i = 0; i < _flatItems.length; i++) {
      if (_flatItems[i].chapterIndex == chapterIndex &&
          _flatItems[i].type == _ScrollItemType.chapterHeader) {
        final targetOffset = _cumulativeOffsets[i];
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _updateActiveLocationFromScroll();
    });
  }

  void _updateActiveLocationFromScroll() {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;

    final currentOffset = _scrollController.offset;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final pct = (maxOffset > 0)
        ? (currentOffset / maxOffset).clamp(0.0, 1.0)
        : 0.0;

    int low = 0;
    int high = _cumulativeOffsets.length - 1;
    int visibleIndex = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_cumulativeOffsets[mid] <= currentOffset) {
        visibleIndex = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    final item = _flatItems[visibleIndex.clamp(0, _flatItems.length - 1)];
    _activeAnchorNodeId = item.anchorId;
    _activeChapterIndex = item.chapterIndex;

    widget.onProgressChanged(
      item.chapterIndex,
      visibleIndex + 1,
      pct,
      _activeAnchorNodeId,
      0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final effectiveMargin = (screenWidth < 400)
        ? 16.0
        : (screenWidth < 650 ? 24.0 : widget.typography.horizontalMargin);
    final maxContentWidth = math.min(
      760.0,
      screenWidth - (effectiveMargin * 2),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTapContent,
      child: Center(
        child: SizedBox(
          width: maxContentWidth,
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              vertical: 48,
              horizontal: effectiveMargin,
            ),
            itemCount: _flatItems.length,
            itemBuilder: (context, index) {
              final item = _flatItems[index];
              return _buildItemWidget(context, item);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildItemWidget(BuildContext context, _ScrollItem item) {
    switch (item.type) {
      case _ScrollItemType.chapterHeader:
        final chapter = widget.document.chapters[item.chapterIndex];
        final readMins = ReflowableEngine.estimateChapterReadingMinutes(
          chapter,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BAB ${item.chapterIndex + 1}',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                  color: widget.theme.isDark
                      ? const Color(0xFFD4AF37)
                      : const Color(0xFFB8860B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.chapterTitle,
                style: widget.typography.headingStyle(
                  level: 1,
                  color: widget.theme.textColor,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: widget.theme.secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$readMins menit baca',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.theme.secondaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(
                color: widget.theme.secondaryTextColor.withAlpha(40),
                thickness: 0.8,
              ),
            ],
          ),
        );

      case _ScrollItemType.chapterDivider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDot(),
                const SizedBox(width: 8),
                _buildDot(),
                const SizedBox(width: 8),
                _buildDot(),
              ],
            ),
          ),
        );

      case _ScrollItemType.node:
        final node = item.node!;
        return _buildNodeWidget(context, node);
    }
  }

  Widget _buildDot() {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: widget.theme.secondaryTextColor.withAlpha(120),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildNodeWidget(BuildContext context, ContentNode node) {
    if (node.type == ContentNodeType.image) {
      return Padding(
        padding: EdgeInsets.only(bottom: widget.typography.paragraphSpacing),
        child: _buildImageWidget(node),
      );
    }

    final highlightsForNode = widget.highlights
        .where(
          (h) =>
              h.anchorNodeId == node.id ||
              (h.anchorNodeId == null && h.chapterId == node.id),
        )
        .toList();
    final searchMatchesForNode = widget.searchMatches
        .where((sm) => sm.nodeId == node.id)
        .toList();

    if (node.type == ContentNodeType.heading) {
      final style = widget.typography.headingStyle(
        level: node.level,
        color: widget.theme.textColor,
      );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: node.text,
        sliceStartOffset: 0,
        sliceEndOffset: node.text.length,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: widget.theme,
        onHighlightTap: widget.onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(
          top: 14,
          bottom: widget.typography.paragraphSpacing * 1.2,
        ),
        child: SelectableText.rich(
          richSpan,
          textAlign: widget.typography.textAlign,
          contextMenuBuilder: (ctx, state) =>
              _buildContextMenu(ctx, state, node),
        ),
      );
    }

    if (node.type == ContentNodeType.quote) {
      final style = widget.typography.quoteStyle(
        color: widget.theme.textColor.withAlpha(210),
      );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: node.text,
        sliceStartOffset: 0,
        sliceEndOffset: node.text.length,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: widget.theme,
        onHighlightTap: widget.onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(bottom: widget.typography.paragraphSpacing),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: widget.theme.isDark
                    ? const Color(0xFFD4AF37).withAlpha(180)
                    : const Color(0xFFB8860B).withAlpha(200),
                width: 3.0,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
          child: SelectableText.rich(
            richSpan,
            textAlign: widget.typography.textAlign,
            contextMenuBuilder: (ctx, state) =>
                _buildContextMenu(ctx, state, node),
          ),
        ),
      );
    }

    // Footnote Node
    if (node.type == ContentNodeType.footnote) {
      final style = widget.typography.bodyStyle(
        color: widget.theme.secondaryTextColor,
      ).copyWith(
        fontSize: widget.typography.fontSize * 0.85,
        fontStyle: FontStyle.italic,
      );
      final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: node.text,
        sliceStartOffset: 0,
        sliceEndOffset: node.text.length,
        highlightsForNode: highlightsForNode,
        searchMatchesForNode: searchMatchesForNode,
        baseStyle: style,
        theme: widget.theme,
        onHighlightTap: widget.onHighlightTap,
      );

      return Padding(
        padding: EdgeInsets.only(
          top: 4,
          bottom: widget.typography.paragraphSpacing * 0.6,
        ),
        child: SelectableText.rich(
          richSpan,
          textAlign: widget.typography.textAlign,
          contextMenuBuilder: (ctx, state) =>
              _buildContextMenu(ctx, state, node),
        ),
      );
    }

    // Default Paragraph
    final style = widget.typography.bodyStyle(color: widget.theme.textColor);
    final richSpan = ReflowableHighlightSpanBuilder.buildRichSpan(
      text: node.text,
      sliceStartOffset: 0,
      sliceEndOffset: node.text.length,
      highlightsForNode: highlightsForNode,
      searchMatchesForNode: searchMatchesForNode,
      baseStyle: style,
      theme: widget.theme,
      onHighlightTap: widget.onHighlightTap,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: widget.typography.paragraphSpacing),
      child: SelectableText.rich(
        richSpan,
        textAlign: widget.typography.textAlign,
        contextMenuBuilder: (ctx, state) => _buildContextMenu(ctx, state, node),
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
                constraints: const BoxConstraints(maxHeight: 280),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildPlaceholderImage(),
                ),
              ),
            ),
            if (hasCaption) ...[
              const SizedBox(height: 8),
              Text(
                node.text.trim(),
                style: TextStyle(
                  fontSize: widget.typography.fontSize * 0.85,
                  color: widget.theme.secondaryTextColor,
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
      height: 160,
      decoration: BoxDecoration(
        color: widget.theme.isDark
            ? Colors.white.withAlpha(15)
            : Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.theme.secondaryTextColor.withAlpha(40),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 36,
              color: widget.theme.secondaryTextColor.withAlpha(150),
            ),
            const SizedBox(height: 8),
            Text(
              'Ilustrasi Buku',
              style: TextStyle(
                fontSize: 12,
                color: widget.theme.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState state,
    ContentNode node,
  ) {
    final selection = state.textEditingValue.selection;
    final text = selection.textInside(state.textEditingValue.text);

    if (text.trim().isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: state.contextMenuButtonItems,
      );
    }

    final absStart = selection.start.clamp(0, node.text.length);
    final absEnd = selection.end.clamp(absStart, node.text.length);

    final pStart = math.max(0, absStart - 32);
    final prefixContext = node.text.substring(pStart, absStart);

    final sEnd = math.min(node.text.length, absEnd + 32);
    final suffixContext = node.text.substring(absEnd, sEnd);

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ...state.contextMenuButtonItems,
        ContextMenuButtonItem(
          label: '🟡 Kuning',
          onPressed: () {
            widget.onHighlightCreated?.call(
              text: text.trim(),
              color: 'yellow',
              anchorNodeId: node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: node.sourcePdfPage,
            );
            state.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🟢 Hijau',
          onPressed: () {
            widget.onHighlightCreated?.call(
              text: text.trim(),
              color: 'green',
              anchorNodeId: node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: node.sourcePdfPage,
            );
            state.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🔵 Biru',
          onPressed: () {
            widget.onHighlightCreated?.call(
              text: text.trim(),
              color: 'blue',
              anchorNodeId: node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: node.sourcePdfPage,
            );
            state.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🔴 Merah Muda',
          onPressed: () {
            widget.onHighlightCreated?.call(
              text: text.trim(),
              color: 'pink',
              anchorNodeId: node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: node.sourcePdfPage,
            );
            state.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '🟣 Ungu',
          onPressed: () {
            widget.onHighlightCreated?.call(
              text: text.trim(),
              color: 'purple',
              anchorNodeId: node.id,
              startOffset: absStart,
              endOffset: absEnd,
              prefixContext: prefixContext,
              suffixContext: suffixContext,
              pageNumber: node.sourcePdfPage,
            );
            state.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: '📝 Catatan',
          onPressed: () {
            state.hideToolbar();
            HighlightInteractionSheet.show(
              context: context,
              selectedText: text.trim(),
              theme: widget.theme,
              onSave: (color, note) {
                widget.onHighlightCreated?.call(
                  text: text.trim(),
                  color: color,
                  note: note,
                  anchorNodeId: node.id,
                  startOffset: absStart,
                  endOffset: absEnd,
                  prefixContext: prefixContext,
                  suffixContext: suffixContext,
                  pageNumber: node.sourcePdfPage,
                );
              },
            );
          },
        ),
      ],
    );
  }
}
