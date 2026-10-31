import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'paginated_reflowable_reader.dart';
import 'scrolling_reflowable_reader.dart';

class ReflowableReaderContainer extends ConsumerStatefulWidget {
  final String bookId;
  final ReaderDocument document;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final int initialChapterIndex;
  final int initialPosition;
  final String? initialAnchorNodeId;
  final int initialCharOffset;
  final VoidCallback onTapContent;
  final Function(int chapterIndex, int position, double percentage, String? anchorNodeId, int charOffset) onProgressChanged;
  final void Function(int totalPages)? onTotalPagesCalculated;
  final Function(String text, String color, int pageNumber)? onHighlightCreated;

  const ReflowableReaderContainer({
    super.key,
    required this.bookId,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialChapterIndex = 0,
    this.initialPosition = 0,
    this.initialAnchorNodeId,
    this.initialCharOffset = 0,
    required this.onTapContent,
    required this.onProgressChanged,
    this.onTotalPagesCalculated,
    this.onHighlightCreated,
  });

  @override
  ConsumerState<ReflowableReaderContainer> createState() => ReflowableReaderContainerState();
}

class ReflowableReaderContainerState extends ConsumerState<ReflowableReaderContainer> {
  final GlobalKey<PaginatedReflowableReaderState> _paginatedKey =
      GlobalKey<PaginatedReflowableReaderState>();
  final GlobalKey<ScrollingReflowableReaderState> _scrollingKey =
      GlobalKey<ScrollingReflowableReaderState>();

  String? _activeAnchorNodeId;
  int _activeCharOffset = 0;
  int _currentChapter = 0;
  int _currentPage = 1;
  int _totalPages = 1;

  int get totalPages => _paginatedKey.currentState?.totalPages ?? _totalPages;
  int get currentPage => _currentPage;
  String? get activeAnchorNodeId => _activeAnchorNodeId;

  @override
  void initState() {
    super.initState();
    _activeAnchorNodeId = widget.initialAnchorNodeId;
    _activeCharOffset = widget.initialCharOffset;
    _currentChapter = widget.initialChapterIndex;
    _currentPage = widget.initialPosition > 0 ? widget.initialPosition : 1;
  }

  void nextPage() {
    final mode = ref.read(reflowableLayoutModeProvider(widget.bookId));
    if (mode == ReflowableLayoutMode.paginated) {
      _paginatedKey.currentState?.nextPage();
    }
  }

  void previousPage() {
    final mode = ref.read(reflowableLayoutModeProvider(widget.bookId));
    if (mode == ReflowableLayoutMode.paginated) {
      _paginatedKey.currentState?.previousPage();
    }
  }

  void jumpToPage(int pageNumber) {
    final mode = ref.read(reflowableLayoutModeProvider(widget.bookId));
    if (mode == ReflowableLayoutMode.paginated) {
      _paginatedKey.currentState?.jumpToPage(pageNumber);
    }
  }

  void jumpToChapter(int chapterIndex) {
    final mode = ref.read(reflowableLayoutModeProvider(widget.bookId));
    if (mode == ReflowableLayoutMode.paginated) {
      _paginatedKey.currentState?.jumpToChapter(chapterIndex);
    } else {
      _scrollingKey.currentState?.jumpToChapter(chapterIndex);
    }
  }

  void _handleProgressChanged(
    int chapterIndex,
    int position,
    double percentage,
    String? anchorNodeId,
    int charOffset,
  ) {
    _currentChapter = chapterIndex;
    _currentPage = position;
    if (anchorNodeId != null) {
      _activeAnchorNodeId = anchorNodeId;
      _activeCharOffset = charOffset;
    }

    widget.onProgressChanged(
      chapterIndex,
      position,
      percentage,
      anchorNodeId,
      charOffset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutMode = ref.watch(reflowableLayoutModeProvider(widget.bookId));

    final Widget content;
    if (layoutMode == ReflowableLayoutMode.scrolling) {
      content = ScrollingReflowableReader(
        key: _scrollingKey,
        document: widget.document,
        theme: widget.theme,
        typography: widget.typography,
        initialAnchorNodeId: _activeAnchorNodeId,
        initialChapterIndex: _currentChapter,
        onTapContent: widget.onTapContent,
        onProgressChanged: _handleProgressChanged,
        onHighlightCreated: widget.onHighlightCreated,
      );
    } else {
      content = PaginatedReflowableReader(
        key: _paginatedKey,
        document: widget.document,
        theme: widget.theme,
        typography: widget.typography,
        initialPageIndex: _currentPage > 0 ? _currentPage - 1 : 0,
        initialAnchorNodeId: _activeAnchorNodeId,
        initialCharOffset: _activeCharOffset,
        onTapContent: widget.onTapContent,
        onProgressChanged: (ch, page, pct, anchor, offset) {
          _handleProgressChanged(ch, page, pct, anchor, offset);
        },
        onTotalPagesCalculated: (total) {
          _totalPages = total;
          widget.onTotalPagesCalculated?.call(total);
        },
        onHighlightCreated: widget.onHighlightCreated,
      );
    }

    return Container(
      color: widget.theme.backgroundColor,
      child: content,
    );
  }
}
