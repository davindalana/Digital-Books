import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
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
  final Function(int chapterIndex, int pageNumber, double percentage, String? anchorNodeId, int charOffset) onProgressChanged;
  final void Function(int totalPages)? onTotalPagesCalculated;
  final Function(String text, String color, int pageNumber)? onHighlightCreated;

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
    this.onHighlightCreated,
  });

  @override
  State<PaginatedReflowableReader> createState() => PaginatedReflowableReaderState();
}

class PaginatedReflowableReaderState extends State<PaginatedReflowableReader> {
  List<PaginatedPage> _pages = [];
  int _currentPageIndex = 0;
  bool _isNavigating = false;
  double _lastWidth = 0;
  double _lastHeight = 0;

  String? _activeAnchorNodeId;
  int _activeCharOffset = 0;

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
  void didUpdateWidget(covariant PaginatedReflowableReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typography.cacheKey != widget.typography.cacheKey ||
        oldWidget.document != widget.document) {
      _pages = [];
    }
  }

  void _ensureLayout(double width, double height) {
    if ((width - _lastWidth).abs() > 4 ||
        (height - _lastHeight).abs() > 4 ||
        _pages.isEmpty) {
      final oldTotal = _pages.length;
      final oldPage = _currentPageIndex;
      final oldAnchor = _activeAnchorNodeId;

      _lastWidth = width;
      _lastHeight = height;

      final newPages = PaginationEngine.paginateDocument(
        document: widget.document,
        viewportWidth: width,
        viewportHeight: height,
        typography: widget.typography,
      );

      int targetPage = _currentPageIndex;
      if (_activeAnchorNodeId != null && newPages.isNotEmpty) {
        targetPage = PaginationEngine.findPageIndexForAnchor(
          pages: newPages,
          anchorNodeId: _activeAnchorNodeId!,
          characterOffset: _activeCharOffset,
        );
      }

      _pages = newPages;
      _currentPageIndex = targetPage.clamp(0, math.max(0, newPages.length - 1));

      if (_pages.isNotEmpty && _pages[_currentPageIndex].slices.isNotEmpty) {
        _activeAnchorNodeId = _pages[_currentPageIndex].slices.first.node.id;
        _activeCharOffset = _pages[_currentPageIndex].slices.first.startCharOffset;
      }

      final pageChanged = _currentPageIndex != oldPage || _activeAnchorNodeId != oldAnchor;
      final totalChanged = _pages.length != oldTotal;

      if (totalChanged || pageChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (totalChanged) widget.onTotalPagesCalculated?.call(_pages.length);
            if (pageChanged) _notifyProgress();
          }
        });
      }
    }
  }

  void _notifyProgress() {
    if (_pages.isEmpty) return;
    final page = _pages[_currentPageIndex];

    if (page.slices.isNotEmpty) {
      _activeAnchorNodeId = page.slices.first.node.id;
      _activeCharOffset = page.slices.first.startCharOffset;
    }

    final double pct = _pages.isNotEmpty
        ? ((_currentPageIndex + 1) / _pages.length).clamp(0.0, 1.0)
        : 0.0;

    widget.onProgressChanged(
      page.chapterIndex,
      _currentPageIndex + 1,
      pct,
      _activeAnchorNodeId,
      _activeCharOffset,
    );
  }

  void nextPage() {
    if (_isNavigating || _pages.isEmpty) return;
    final isSpread = _isTwoPageSpreadActive;
    final step = isSpread ? 2 : 1;
    final nextTarget = _currentPageIndex + step;

    if (nextTarget < _pages.length) {
      _animateToPage(nextTarget);
    }
  }

  void previousPage() {
    if (_isNavigating || _pages.isEmpty) return;
    final isSpread = _isTwoPageSpreadActive;
    final step = isSpread ? 2 : 1;
    final prevTarget = _currentPageIndex - step;

    if (prevTarget >= 0) {
      _animateToPage(prevTarget);
    } else if (_currentPageIndex > 0) {
      _animateToPage(0);
    }
  }

  void jumpToPage(int pageNumber) {
    if (_pages.isEmpty) return;
    final target = (pageNumber - 1).clamp(0, _pages.length - 1);
    final isSpread = _isTwoPageSpreadActive;
    final normalized = isSpread && target % 2 != 0 ? target - 1 : target;

    setState(() {
      _currentPageIndex = normalized;
    });
    _notifyProgress();
  }

  void jumpToChapter(int chapterIndex) {
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].chapterIndex == chapterIndex) {
        jumpToPage(i + 1);
        return;
      }
    }
  }

  void _animateToPage(int targetIndex) {
    if (_isNavigating) return;
    _isNavigating = true;

    setState(() {
      _currentPageIndex = targetIndex;
    });
    _notifyProgress();

    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    });
  }

  bool get _isTwoPageSpreadActive =>
      _lastWidth >= 850 && widget.typography.twoPageSpread;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        _ensureLayout(width, height);

        if (_pages.isEmpty) {
          return Center(
            child: CircularProgressIndicator(
              color: widget.theme.textColor,
              strokeWidth: 2.5,
            ),
          );
        }

        final isSpread = width >= 850 && widget.typography.twoPageSpread;
        // Ensure even index on two-page spread
        final safeIndex = isSpread && _currentPageIndex % 2 != 0
            ? math.max(0, _currentPageIndex - 1)
            : _currentPageIndex.clamp(0, _pages.length - 1);

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              // Ignore if a text field or input has focus
              final primaryFocus = FocusManager.instance.primaryFocus;
              if (primaryFocus != null &&
                  primaryFocus.context != null &&
                  primaryFocus != node) {
                return KeyEventResult.ignored;
              }

              if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.pageUp) {
                previousPage();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  event.logicalKey == LogicalKeyboardKey.pageDown ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                nextPage();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < -200) {
                  nextPage();
                } else if (details.primaryVelocity! > 200) {
                  previousPage();
                }
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Reading Content Layer
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: KeyedSubtree(
                    key: ValueKey('page_${safeIndex}_spread_$isSpread'),
                    child: isSpread
                        ? _buildTwoPageSpread(width, height, safeIndex)
                        : _buildSinglePage(width, height, safeIndex),
                  ),
                ),

                // Touch/Click Margins for Apple Books Style Navigation
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
          onHighlightCreated: widget.onHighlightCreated,
        ),
      ),
    );
  }

  Widget _buildTwoPageSpread(double width, double height, int leftIndex) {
    final rightIndex = leftIndex + 1;
    final leftPage = _pages[leftIndex];
    final rightPage = rightIndex < _pages.length ? _pages[rightIndex] : null;

    final double halfWidth = (width - 32) / 2;
    final effectiveMargin = (halfWidth < 400)
        ? 16.0
        : (halfWidth < 650 ? 22.0 : widget.typography.horizontalMargin);
    final contentWidth = (halfWidth - (effectiveMargin * 2)).clamp(160.0, 800.0);

    return Row(
      children: [
        // Left Page
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: effectiveMargin,
              right: effectiveMargin * 0.75,
            ),
            child: ReflowablePageRenderer(
              page: leftPage,
              totalPagesInBook: _pages.length,
              theme: widget.theme,
              typography: widget.typography,
              contentWidth: contentWidth,
              showHeader: true,
              showFooter: true,
              isLeftPage: true,
              onHighlightCreated: widget.onHighlightCreated,
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
              ? Padding(
                  padding: EdgeInsets.only(
                    left: effectiveMargin * 0.75,
                    right: effectiveMargin,
                  ),
                  child: ReflowablePageRenderer(
                    page: rightPage,
                    totalPagesInBook: _pages.length,
                    theme: widget.theme,
                    typography: widget.typography,
                    contentWidth: contentWidth,
                    showHeader: true,
                    showFooter: true,
                    isLeftPage: false,
                    onHighlightCreated: widget.onHighlightCreated,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
