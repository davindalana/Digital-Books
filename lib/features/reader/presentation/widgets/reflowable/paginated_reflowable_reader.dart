import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'reflowable_page_renderer.dart';

class PaginatedReflowableReader extends StatefulWidget {
  final ReaderDocument document;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final int initialPageIndex;
  final String? initialAnchorNodeId;
  final int initialCharOffset;
  final VoidCallback onTapContent;
  final Function(
    int chapterIndex,
    int pageNumber,
    double percentage,
    String? anchorNodeId,
    int charOffset,
  )
  onProgressChanged;
  final void Function(int totalPages)? onTotalPagesCalculated;
  final List<Highlight> highlights;
  final List<ActiveSearchMatch> searchMatches;
  final HighlightCreationCallback? onHighlightCreated;
  final void Function(Highlight highlight)? onHighlightTap;

  const PaginatedReflowableReader({
    super.key,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialPageIndex = 0,
    this.initialAnchorNodeId,
    this.initialCharOffset = 0,
    required this.onTapContent,
    required this.onProgressChanged,
    this.onTotalPagesCalculated,
    this.highlights = const [],
    this.searchMatches = const [],
    this.onHighlightCreated,
    this.onHighlightTap,
  });

  @override
  State<PaginatedReflowableReader> createState() =>
      PaginatedReflowableReaderState();
}

class PaginatedReflowableReaderState extends State<PaginatedReflowableReader> {
  List<PaginatedPage> _pages = [];
  int _currentPageIndex = 0;
  bool _isNavigating = false;
  double _lastWidth = 0;
  double _lastHeight = 0;

  String? _activeAnchorNodeId;
  int _activeCharOffset = 0;
  Timer? _navTimer;

  int get totalPages => _pages.length;
  int get currentPageIndex => _currentPageIndex;
  List<PaginatedPage> get pages => _pages;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.initialPageIndex;
    _activeAnchorNodeId = widget.initialAnchorNodeId;
    _activeCharOffset = widget.initialCharOffset;
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PaginatedReflowableReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typography != widget.typography ||
        oldWidget.document != widget.document) {
      _recalculateLayoutPreservingAnchor();
    }
  }

  void _recalculateLayoutPreservingAnchor() {
    if (_lastWidth <= 0 || _lastHeight <= 0) return;

    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;

    final newPages = PaginationEngine.paginateDocument(
      document: widget.document,
      typography: widget.typography,
      viewportWidth: _lastWidth,
      viewportHeight: _lastHeight,
    );

    int targetIndex = _currentPageIndex;
    if (_activeAnchorNodeId != null) {
      targetIndex = PaginationEngine.findPageIndexForAnchor(
        pages: newPages,
        anchorNodeId: _activeAnchorNodeId!,
        characterOffset: _activeCharOffset,
      );
      if (isTwoPage && targetIndex % 2 != 0) {
        targetIndex -= 1;
      }
    }

    setState(() {
      _pages = newPages;
      _currentPageIndex = targetIndex.clamp(
        0,
        math.max(0, newPages.length - 1),
      );
    });

    widget.onTotalPagesCalculated?.call(_pages.length);
  }

  void nextPage() {
    if (_isNavigating || _pages.isEmpty) return;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    final step = isTwoPage ? 2 : 1;
    final nextIndex = _currentPageIndex + step;

    if (nextIndex < _pages.length) {
      _isNavigating = true;
      setState(() {
        _currentPageIndex = nextIndex;
      });
      _onPageSelected(nextIndex);
      _navTimer?.cancel();
      _navTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) _isNavigating = false;
      });
    }
  }

  void previousPage() {
    if (_isNavigating || _pages.isEmpty) return;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    final step = isTwoPage ? 2 : 1;
    final prevIndex = _currentPageIndex - step;

    if (prevIndex >= 0) {
      _isNavigating = true;
      setState(() {
        _currentPageIndex = prevIndex;
      });
      _onPageSelected(prevIndex);
      _navTimer?.cancel();
      _navTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) _isNavigating = false;
      });
    }
  }

  void jumpToPage(int pageIndex) {
    if (_pages.isEmpty) return;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    int target = pageIndex.clamp(0, _pages.length - 1);
    if (isTwoPage && target % 2 != 0) {
      target -= 1;
    }
    setState(() {
      _currentPageIndex = target;
    });
    _onPageSelected(target);
  }

  void jumpToAnchor(String nodeId, [int charOffset = 0]) {
    if (_pages.isEmpty) return;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    int target = PaginationEngine.findPageIndexForAnchor(
      pages: _pages,
      anchorNodeId: nodeId,
      characterOffset: charOffset,
    );
    if (isTwoPage && target % 2 != 0) {
      target -= 1;
    }
    setState(() {
      _currentPageIndex = target;
      _activeAnchorNodeId = nodeId;
      _activeCharOffset = charOffset;
    });
    _onPageSelected(target);
  }

  void jumpToChapter(int chapterIndex) {
    if (_pages.isEmpty) return;
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].chapterIndex == chapterIndex) {
        jumpToPage(i);
        return;
      }
    }
  }

  void _onPageSelected(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pages.length) return;
    final page = _pages[pageIndex];

    if (page.slices.isNotEmpty) {
      _activeAnchorNodeId = page.slices.first.node.id;
      _activeCharOffset = page.slices.first.startCharOffset;
    }

    final total = _pages.length;
    final pct = total > 0 ? ((pageIndex + 1) / total).clamp(0.0, 1.0) : 0.0;

    widget.onProgressChanged(
      page.chapterIndex,
      pageIndex + 1,
      pct,
      _activeAnchorNodeId,
      _activeCharOffset,
    );
  }

  void _ensureLayout(double width, double height) {
    final isTwoPage = widget.typography.twoPageSpread && width >= 850.0;

    final pages = PaginationEngine.paginateDocument(
      document: widget.document,
      typography: widget.typography,
      viewportWidth: width,
      viewportHeight: height,
    );

    int targetIndex = _currentPageIndex;
    if (_activeAnchorNodeId != null) {
      targetIndex = PaginationEngine.findPageIndexForAnchor(
        pages: pages,
        anchorNodeId: _activeAnchorNodeId!,
        characterOffset: _activeCharOffset,
      );
      if (isTwoPage && targetIndex % 2 != 0) {
        targetIndex -= 1;
      }
    }

    _lastWidth = width;
    _lastHeight = height;
    final totalChanged = _pages.length != pages.length;
    final pageChanged = _currentPageIndex != targetIndex;

    _pages = pages;
    _currentPageIndex = targetIndex.clamp(0, math.max(0, pages.length - 1));

    if (totalChanged || pageChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onTotalPagesCalculated?.call(_pages.length);
        if (_pages.isNotEmpty) {
          _onPageSelected(_currentPageIndex);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        if (_pages.isEmpty ||
            (width - _lastWidth).abs() > 2.0 ||
            (height - _lastHeight).abs() > 2.0) {
          _ensureLayout(width, height);
        }

        if (_pages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final isTwoPage = widget.typography.twoPageSpread && width >= 850.0;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): nextPage,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): previousPage,
            const SingleActivator(LogicalKeyboardKey.space): nextPage,
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                // Page Content
                Positioned.fill(
                  child: isTwoPage
                      ? _buildTwoPageSpread(width, height, _currentPageIndex)
                      : _buildSinglePage(width, height, _currentPageIndex),
                ),

                // Left 15% tap -> Previous Page
                Positioned(
                  left: 0,
                  top: 50,
                  bottom: 50,
                  width: math.max(48.0, width * 0.15),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: previousPage,
                    ),
                  ),
                ),

                // Right 15% tap -> Next Page
                Positioned(
                  right: 0,
                  top: 50,
                  bottom: 50,
                  width: math.max(48.0, width * 0.15),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: nextPage,
                    ),
                  ),
                ),

                // Center 70% tap -> Toggle Controls
                Positioned(
                  left: math.max(48.0, width * 0.15),
                  right: math.max(48.0, width * 0.15),
                  top: 50,
                  bottom: 50,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onTapContent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSinglePage(double width, double height, int index) {
    final page = _pages[index];
    final effectiveMargin = (width < 400)
        ? 16.0
        : (width < 650 ? 22.0 : widget.typography.horizontalMargin);
    final contentWidth = (width - (effectiveMargin * 2)).clamp(160.0, 900.0);

    return Center(
      key: ValueKey('page_${index}_spread_false'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: effectiveMargin),
        child: ReflowablePageRenderer(
          page: page,
          totalPagesInBook: _pages.length,
          theme: widget.theme,
          typography: widget.typography,
          contentWidth: contentWidth,
          showHeader: true,
          showFooter: true,
          isLeftPage: false,
          highlights: widget.highlights,
          searchMatches: widget.searchMatches,
          onHighlightCreated: widget.onHighlightCreated,
          onHighlightTap: widget.onHighlightTap,
        ),
      ),
    );
  }

  Widget _buildTwoPageSpread(double width, double height, int leftIndex) {
    final rightIndex = leftIndex + 1;
    final leftPage = _pages[leftIndex];
    final rightPage = rightIndex < _pages.length ? _pages[rightIndex] : null;

    final double halfWidth = (width - 16.0) / 2;
    final effectiveMargin = (halfWidth < 400)
        ? 16.0
        : (halfWidth < 650 ? 22.0 : widget.typography.horizontalMargin);
    final contentWidth = (halfWidth - (effectiveMargin * 2)).clamp(
      160.0,
      800.0,
    );

    return Row(
      key: ValueKey('page_${leftIndex}_spread_true'),
      children: [
        // Left Page
        Expanded(
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: ReflowablePageRenderer(
                page: leftPage,
                totalPagesInBook: _pages.length,
                theme: widget.theme,
                typography: widget.typography,
                contentWidth: contentWidth,
                showHeader: true,
                showFooter: true,
                isLeftPage: true,
                highlights: widget.highlights,
                searchMatches: widget.searchMatches,
                onHighlightCreated: widget.onHighlightCreated,
                onHighlightTap: widget.onHighlightTap,
              ),
            ),
          ),
        ),

        // Physical Center Spine Crease (Apple Books Open Book depth)
        Container(
          width: 16,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withAlpha(widget.theme.isDark ? 40 : 25),
                Colors.transparent,
                Colors.black.withAlpha(widget.theme.isDark ? 40 : 25),
              ],
            ),
          ),
        ),

        // Right Page
        Expanded(
          child: rightPage != null
              ? Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: ReflowablePageRenderer(
                      page: rightPage,
                      totalPagesInBook: _pages.length,
                      theme: widget.theme,
                      typography: widget.typography,
                      contentWidth: contentWidth,
                      showHeader: true,
                      showFooter: true,
                      isLeftPage: false,
                      highlights: widget.highlights,
                      searchMatches: widget.searchMatches,
                      onHighlightCreated: widget.onHighlightCreated,
                      onHighlightTap: widget.onHighlightTap,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
