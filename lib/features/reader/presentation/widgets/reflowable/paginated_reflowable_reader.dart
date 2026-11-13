import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
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
  Timer? _navTimer;
  double _lastWidth = 0;
  double _lastHeight = 0;

  String? _activeAnchorNodeId;
  int _activeCharOffset = 0;
  bool _isHoveringLeft = false;
  bool _isHoveringRight = false;

  int get totalPages => _pages.length;
  int get currentPageIndex => _currentPageIndex;
  List<PaginatedPage> get pages => _pages;

  bool get canGoPrevious => _currentPageIndex > 0;
  bool get canGoNext {
    if (_pages.isEmpty) return false;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    final step = isTwoPage ? 2 : 1;
    return _currentPageIndex + step < _pages.length;
  }

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
    } else if (isTwoPage && targetIndex % 2 != 0) {
      targetIndex -= 1;
    }

    _pages = newPages;
    _currentPageIndex = targetIndex.clamp(0, math.max(0, newPages.length - 1));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onTotalPagesCalculated?.call(_pages.length);
      if (_pages.isNotEmpty) {
        _onPageSelected(_currentPageIndex);
      }
    });
  }

  void nextPage() {
    if (_isNavigating || _pages.isEmpty || !canGoNext) return;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    final step = isTwoPage ? 2 : 1;
    final nextIndex = _currentPageIndex + step;
    final target = (isTwoPage && nextIndex % 2 != 0)
        ? nextIndex - 1
        : nextIndex;

    if (target < _pages.length) {
      _isNavigating = true;
      setState(() {
        _currentPageIndex = target;
      });
      _onPageSelected(target);
      _navTimer?.cancel();
      _navTimer = Timer(const Duration(milliseconds: 50), () {
        if (mounted) {
          setState(() => _isNavigating = false);
        }
      });
    }
  }

  void previousPage() {
    if (_isNavigating || _pages.isEmpty || !canGoPrevious) return;
    final isTwoPage = widget.typography.twoPageSpread && _lastWidth >= 850.0;
    final step = isTwoPage ? 2 : 1;
    final prevIndex = math.max(0, _currentPageIndex - step);
    final target = (isTwoPage && prevIndex % 2 != 0)
        ? math.max(0, prevIndex - 1)
        : prevIndex;

    if (target >= 0) {
      _isNavigating = true;
      setState(() {
        _currentPageIndex = target;
      });
      _onPageSelected(target);
      _navTimer?.cancel();
      _navTimer = Timer(const Duration(milliseconds: 50), () {
        if (mounted) {
          setState(() => _isNavigating = false);
        }
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
      if (_activeAnchorNodeId == null ||
          !page.containsAnchor(_activeAnchorNodeId!, _activeCharOffset)) {
        _activeAnchorNodeId = page.slices.first.node.id;
        _activeCharOffset = page.slices.first.startCharOffset;
      }
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
            const SingleActivator(LogicalKeyboardKey.space, shift: true):
                previousPage,
          },
          child: Focus(
            autofocus: true,
            child: Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  if (pointerSignal.scrollDelta.dx > 25) {
                    nextPage();
                  } else if (pointerSignal.scrollDelta.dx < -25) {
                    previousPage();
                  }
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final vx = details.primaryVelocity ?? 0;
                  if (vx < -200) {
                    nextPage();
                  } else if (vx > 200) {
                    previousPage();
                  }
                },
                child: Stack(
                  children: [
                    // Page Content
                    Positioned.fill(
                      child: isTwoPage
                          ? _buildTwoPageSpread(
                              width,
                              height,
                              _currentPageIndex,
                            )
                          : _buildSinglePage(width, height, _currentPageIndex),
                    ),

                    // Left 15% tap -> Previous Page
                    Positioned(
                      left: 0,
                      top: 50,
                      bottom: 50,
                      width: math.max(48.0, width * 0.15),
                      child: MouseRegion(
                        cursor: canGoPrevious
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onEnter: (_) {
                          if (mounted && !_isHoveringLeft) {
                            setState(() => _isHoveringLeft = true);
                          }
                        },
                        onExit: (_) {
                          if (mounted && _isHoveringLeft) {
                            setState(() => _isHoveringLeft = false);
                          }
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: canGoPrevious ? previousPage : null,
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
                        cursor: canGoNext
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onEnter: (_) {
                          if (mounted && !_isHoveringRight) {
                            setState(() => _isHoveringRight = true);
                          }
                        },
                        onExit: (_) {
                          if (mounted && _isHoveringRight) {
                            setState(() => _isHoveringRight = false);
                          }
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: canGoNext ? nextPage : null,
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
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onTapContent,
                      ),
                    ),

                    // Desktop Left Chevron Control (revealed on hover)
                    if (canGoPrevious)
                      Positioned(
                        left: 14,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            opacity: _isHoveringLeft ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !_isHoveringLeft,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) {
                                  if (mounted && !_isHoveringLeft) {
                                    setState(() => _isHoveringLeft = true);
                                  }
                                },
                                onExit: (_) {
                                  if (mounted && _isHoveringLeft) {
                                    setState(() => _isHoveringLeft = false);
                                  }
                                },
                                child: GestureDetector(
                                  onTap: previousPage,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: widget.theme.isDark
                                          ? Colors.white.withAlpha(22)
                                          : Colors.black.withAlpha(14),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: widget.theme.secondaryTextColor
                                            .withAlpha(35),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.chevron_left_rounded,
                                      size: 22,
                                      color: widget.theme.textColor.withAlpha(
                                        200,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Desktop Right Chevron Control (revealed on hover)
                    if (canGoNext)
                      Positioned(
                        right: 14,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            opacity: _isHoveringRight ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !_isHoveringRight,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) {
                                  if (mounted && !_isHoveringRight) {
                                    setState(() => _isHoveringRight = true);
                                  }
                                },
                                onExit: (_) {
                                  if (mounted && _isHoveringRight) {
                                    setState(() => _isHoveringRight = false);
                                  }
                                },
                                child: GestureDetector(
                                  onTap: nextPage,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: widget.theme.isDark
                                          ? Colors.white.withAlpha(22)
                                          : Colors.black.withAlpha(14),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: widget.theme.secondaryTextColor
                                            .withAlpha(35),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      size: 22,
                                      color: widget.theme.textColor.withAlpha(
                                        200,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSinglePage(double width, double height, int index) {
    final page = _pages[index];
    final effectiveMargin = PaginationEngine.horizontalPageMargin(
      pageWidth: width,
      typography: widget.typography,
    );
    final contentWidth = (width - (effectiveMargin * 2.0)).clamp(160.0, 680.0);

    return Center(
      key: ValueKey('page_${index}_spread_false'),
      child: SizedBox(
        width: contentWidth,
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

    const double spineWidth = PaginationEngine.spreadGutterWidth;
    final double halfWidth = (width - spineWidth) / 2.0;
    final effectiveMargin = PaginationEngine.horizontalPageMargin(
      pageWidth: halfWidth,
      typography: widget.typography,
    );
    final contentWidth = (halfWidth - (effectiveMargin * 2.0)).clamp(
      160.0,
      620.0,
    );

    return Center(
      key: ValueKey('page_${leftIndex}_spread_true'),
      child: SizedBox(
        width: (contentWidth * 2) + spineWidth + (effectiveMargin * 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Page
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
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
              width: spineWidth,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withAlpha(widget.theme.isDark ? 45 : 24),
                    Colors.black.withAlpha(widget.theme.isDark ? 15 : 8),
                    Colors.black.withAlpha(widget.theme.isDark ? 60 : 32),
                    Colors.black.withAlpha(widget.theme.isDark ? 15 : 8),
                    Colors.black.withAlpha(widget.theme.isDark ? 45 : 24),
                  ],
                  stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                ),
              ),
            ),

            // Right Page
            Expanded(
              child: rightPage != null
                  ? Align(
                      alignment: Alignment.centerLeft,
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
        ),
      ),
    );
  }
}
