import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';

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
  final Function(int chapterIndex, int position, double percentage, String? anchorNodeId, int charOffset) onProgressChanged;
  final Function(String text, String color, int pageNumber)? onHighlightCreated;

  const ScrollingReflowableReader({
    super.key,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialAnchorNodeId,
    this.initialChapterIndex = 0,
    required this.onTapContent,
    required this.onProgressChanged,
    this.onHighlightCreated,
  });

  @override
  State<ScrollingReflowableReader> createState() => ScrollingReflowableReaderState();
}

class ScrollingReflowableReaderState extends State<ScrollingReflowableReader> {
  final ScrollController _scrollController = ScrollController();
  List<_ScrollItem> _flatItems = [];
  List<double> _cumulativeOffsets = [];
  Timer? _debounceTimer;

  String? _activeAnchorNodeId;
  int _activeChapterIndex = 0;
  bool _hasScrolledToInitial = false;

  String? get activeAnchorNodeId => _activeAnchorNodeId;
  int get activeChapterIndex => _activeChapterIndex;

  @override
  void initState() {
    super.initState();
    _activeAnchorNodeId = widget.initialAnchorNodeId;
    _activeChapterIndex = widget.initialChapterIndex;
    _buildFlatItems();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialAnchor();
    });
  }

  @override
  void didUpdateWidget(covariant ScrollingReflowableReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.typography.cacheKey != widget.typography.cacheKey) {
      _buildFlatItems();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _buildFlatItems() {
    final List<_ScrollItem> items = [];
    final List<double> offsets = [];
    double runningOffset = 0.0;

    final baseLineHeight = widget.typography.fontSize * widget.typography.lineSpacing;

    for (int chIdx = 0; chIdx < widget.document.chapters.length; chIdx++) {
      final ch = widget.document.chapters[chIdx];

      // Chapter Header
      offsets.add(runningOffset);
      const headerHeight = 110.0;
      items.add(_ScrollItem(
        type: _ScrollItemType.chapterHeader,
        chapterIndex: chIdx,
        chapterTitle: ch.title,
        anchorId: 'ch_${chIdx}_header',
        estimatedHeight: headerHeight,
      ));
      runningOffset += headerHeight;

      // Chapter Nodes
      for (int nIdx = 0; nIdx < ch.nodes.length; nIdx++) {
        final node = ch.nodes[nIdx];
        double nodeHeight = 40.0;

        if (node.type == ContentNodeType.image) {
          nodeHeight = 220.0 + widget.typography.paragraphSpacing;
        } else if (node.type == ContentNodeType.heading) {
          nodeHeight = 55.0 + widget.typography.paragraphSpacing;
        } else if (node.type == ContentNodeType.quote) {
          final lines = math.max(1, (node.text.length / 55).ceil());
          nodeHeight = (lines * baseLineHeight) + widget.typography.paragraphSpacing + 12;
        } else {
          final lines = math.max(1, (node.text.length / 65).ceil());
          nodeHeight = (lines * baseLineHeight) + widget.typography.paragraphSpacing;
        }

        offsets.add(runningOffset);
        items.add(_ScrollItem(
          type: _ScrollItemType.node,
          chapterIndex: chIdx,
          chapterTitle: ch.title,
          node: node,
          anchorId: node.id,
          estimatedHeight: nodeHeight,
        ));
        runningOffset += nodeHeight;
      }

      // Chapter Divider
      offsets.add(runningOffset);
      const dividerHeight = 50.0;
      items.add(_ScrollItem(
        type: _ScrollItemType.chapterDivider,
        chapterIndex: chIdx,
        chapterTitle: ch.title,
        anchorId: 'ch_${chIdx}_divider',
        estimatedHeight: dividerHeight,
      ));
      runningOffset += dividerHeight;
    }

    _flatItems = items;
    _cumulativeOffsets = offsets;
  }

  void _scrollToInitialAnchor() {
    if (_hasScrolledToInitial || !_scrollController.hasClients) return;
    _hasScrolledToInitial = true;

    double targetOffset = 0.0;

    if (_activeAnchorNodeId != null && _flatItems.isNotEmpty) {
      final matchIndex = _flatItems.indexWhere((it) => it.anchorId == _activeAnchorNodeId);
      if (matchIndex >= 0 && matchIndex < _cumulativeOffsets.length) {
        targetOffset = _cumulativeOffsets[matchIndex];
      }
    } else if (widget.initialChapterIndex > 0) {
      final matchIndex = _flatItems.indexWhere(
        (it) => it.type == _ScrollItemType.chapterHeader && it.chapterIndex == widget.initialChapterIndex,
      );
      if (matchIndex >= 0 && matchIndex < _cumulativeOffsets.length) {
        targetOffset = _cumulativeOffsets[matchIndex];
      }
    }

    if (targetOffset > 0 && _scrollController.position.maxScrollExtent > 0) {
      final clamped = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(clamped);
    }
  }

  void jumpToChapter(int chapterIndex) {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;
    final matchIndex = _flatItems.indexWhere(
      (it) => it.type == _ScrollItemType.chapterHeader && it.chapterIndex == chapterIndex,
    );
    if (matchIndex >= 0 && matchIndex < _cumulativeOffsets.length) {
      final target = _cumulativeOffsets[matchIndex].clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void jumpToAnchor(String anchorId) {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;
    final matchIndex = _flatItems.indexWhere((it) => it.anchorId == anchorId);
    if (matchIndex >= 0 && matchIndex < _cumulativeOffsets.length) {
      final target = _cumulativeOffsets[matchIndex].clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onScroll() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), _updateReadingPosition);
  }

  void _updateReadingPosition() {
    if (!_scrollController.hasClients || _flatItems.isEmpty) return;

    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final double pct = maxScroll > 0 ? (currentOffset / maxScroll).clamp(0.0, 1.0) : 0.0;

    // Binary search in _cumulativeOffsets for currentOffset
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
    final maxContentWidth = math.min(760.0, screenWidth - (effectiveMargin * 2));

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
        final readMins = ReflowableEngine.estimateChapterReadingMinutes(chapter);
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

    if (node.type == ContentNodeType.heading) {
      final style = widget.typography.headingStyle(
        level: node.level,
        color: widget.theme.textColor,
      );
      return Padding(
        padding: EdgeInsets.only(
          top: 14,
          bottom: widget.typography.paragraphSpacing * 1.2,
        ),
        child: SelectableText(
          node.text,
          style: style,
          textAlign: widget.typography.textAlign,
          contextMenuBuilder: (ctx, state) => _buildContextMenu(ctx, state),
        ),
      );
    }

    if (node.type == ContentNodeType.quote) {
      final style = widget.typography.quoteStyle(
        color: widget.theme.textColor.withAlpha(210),
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
          child: SelectableText(
            node.text,
            style: style,
            textAlign: widget.typography.textAlign,
            contextMenuBuilder: (ctx, state) => _buildContextMenu(ctx, state),
          ),
        ),
      );
    }

    // Default Paragraph
    final style = widget.typography.bodyStyle(color: widget.theme.textColor);
    return Padding(
      padding: EdgeInsets.only(bottom: widget.typography.paragraphSpacing),
      child: SelectableText(
        node.text,
        style: style,
        textAlign: widget.typography.textAlign,
        contextMenuBuilder: (ctx, state) => _buildContextMenu(ctx, state),
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
            constraints: const BoxConstraints(maxHeight: 280),
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

  Widget _buildContextMenu(BuildContext context, EditableTextState state) {
    final text = state.textEditingValue.selection.textInside(
      state.textEditingValue.text,
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ...state.contextMenuButtonItems,
        if (text.trim().isNotEmpty && widget.onHighlightCreated != null)
          ContextMenuButtonItem(
            label: 'Sorot Emas',
            onPressed: () {
              widget.onHighlightCreated!(text.trim(), 'gold', 1);
              state.hideToolbar();
            },
          ),
        if (text.trim().isNotEmpty && widget.onHighlightCreated != null)
          ContextMenuButtonItem(
            label: 'Sorot Kuning',
            onPressed: () {
              widget.onHighlightCreated!(text.trim(), 'yellow', 1);
              state.hideToolbar();
            },
          ),
      ],
    );
  }
}
