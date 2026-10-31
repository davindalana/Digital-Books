import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import 'reflowable_book_reader.dart';

enum FlipDirection { forward, backward }

class BookPageTurnView extends StatefulWidget {
  final List<ReflowablePageContent> pages;
  final int initialPageIndex;
  final bool isTwoPageSpread;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final Function(int newPageIndex) onPageChanged;
  final VoidCallback onTapCenter;
  final Widget Function(ReflowablePageContent page, {bool? isLeftPage}) pageBuilder;

  const BookPageTurnView({
    super.key,
    required this.pages,
    this.initialPageIndex = 0,
    required this.isTwoPageSpread,
    required this.theme,
    required this.typography,
    required this.onPageChanged,
    required this.onTapCenter,
    required this.pageBuilder,
  });

  @override
  State<BookPageTurnView> createState() => BookPageTurnViewState();
}

class BookPageTurnViewState extends State<BookPageTurnView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late int _currentPageIndex;
  int? _targetPageIndex;
  FlipDirection _direction = FlipDirection.forward;
  bool _isFlipping = false;
  bool _isDragging = false;
  double? _dragStartX;

  // Gentle perspective factor to prevent any glyph explosion or clipping artifacts
  static const double _kPerspective = 0.00010;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.initialPageIndex.clamp(
      0,
      widget.pages.isNotEmpty ? widget.pages.length - 1 : 0,
    );
    if (widget.isTwoPageSpread && _currentPageIndex % 2 != 0) {
      _currentPageIndex -= 1;
    }

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_targetPageIndex != null) {
          setState(() {
            _currentPageIndex = _targetPageIndex!;
            _targetPageIndex = null;
            _isFlipping = false;
            _isDragging = false;
          });
          widget.onPageChanged(_currentPageIndex);
        }
        _controller.reset();
      } else if (status == AnimationStatus.dismissed) {
        setState(() {
          _targetPageIndex = null;
          _isFlipping = false;
          _isDragging = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant BookPageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.length != widget.pages.length) {
      _currentPageIndex = _currentPageIndex.clamp(
        0,
        widget.pages.isNotEmpty ? widget.pages.length - 1 : 0,
      );
    }
    if (widget.isTwoPageSpread && _currentPageIndex % 2 != 0) {
      _currentPageIndex = math.max(0, _currentPageIndex - 1);
    }
    if (oldWidget.initialPageIndex != widget.initialPageIndex &&
        !_isFlipping &&
        !_isDragging) {
      int clamped = widget.initialPageIndex.clamp(
        0,
        widget.pages.isNotEmpty ? widget.pages.length - 1 : 0,
      );
      if (widget.isTwoPageSpread && clamped % 2 != 0) {
        clamped -= 1;
      }
      _currentPageIndex = clamped;
      _targetPageIndex = null;
      _isFlipping = false;
      _isDragging = false;
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get currentPageIndex => _currentPageIndex;

  void flipForward() {
    if (_isFlipping || widget.pages.isEmpty) return;

    final step = widget.isTwoPageSpread ? 2 : 1;
    final target = _currentPageIndex + step;
    if (target < widget.pages.length) {
      setState(() {
        _direction = FlipDirection.forward;
        _targetPageIndex = target;
        _isFlipping = true;
      });
      _controller.forward(from: 0.0);
    }
  }

  void flipBackward() {
    if (_isFlipping || widget.pages.isEmpty) return;

    final step = widget.isTwoPageSpread ? 2 : 1;
    final target = _currentPageIndex - step;
    if (target >= 0) {
      setState(() {
        _direction = FlipDirection.backward;
        _targetPageIndex = target;
        _isFlipping = true;
      });
      _controller.forward(from: 0.0);
    }
  }

  void jumpTo(int pageIndex) {
    if (widget.pages.isEmpty) return;

    int clamped = pageIndex.clamp(0, widget.pages.length - 1);
    if (widget.isTwoPageSpread && clamped % 2 != 0) {
      clamped -= 1;
    }

    _controller.stop();
    setState(() {
      _currentPageIndex = clamped;
      _targetPageIndex = null;
      _isFlipping = false;
      _isDragging = false;
    });
    _controller.reset();
    widget.onPageChanged(_currentPageIndex);
  }

  // --- Interactive Drag Gesture Handling ("ketika melakukan geser") ---
  void _onHorizontalDragStart(DragStartDetails details, BoxConstraints constraints) {
    if (_isFlipping && !_isDragging) return;
    _dragStartX = details.localPosition.dx;
    _isDragging = true;
    _controller.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (!_isDragging || _dragStartX == null || widget.pages.isEmpty) return;

    final deltaX = details.localPosition.dx - _dragStartX!;
    final step = widget.isTwoPageSpread ? 2 : 1;
    final dragSpan = widget.isTwoPageSpread
        ? (constraints.maxWidth * 0.45)
        : (constraints.maxWidth * 0.85);

    if (deltaX < 0) {
      // Swiping left -> Turn forward to next page
      final target = _currentPageIndex + step;
      if (target >= widget.pages.length) return;

      if (_targetPageIndex != target || _direction != FlipDirection.forward) {
        setState(() {
          _direction = FlipDirection.forward;
          _targetPageIndex = target;
          _isFlipping = true;
        });
      }
      final progress = (-deltaX / dragSpan).clamp(0.0, 1.0);
      _controller.value = progress;
    } else if (deltaX > 0) {
      // Swiping right -> Turn backward to previous page
      final target = _currentPageIndex - step;
      if (target < 0) return;

      if (_targetPageIndex != target || _direction != FlipDirection.backward) {
        setState(() {
          _direction = FlipDirection.backward;
          _targetPageIndex = target;
          _isFlipping = true;
        });
      }
      final progress = (deltaX / dragSpan).clamp(0.0, 1.0);
      _controller.value = progress;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details, BoxConstraints constraints) {
    if (!_isDragging) return;
    _isDragging = false;
    _dragStartX = null;

    if (_targetPageIndex == null) {
      setState(() {
        _isFlipping = false;
      });
      _controller.reset();
      return;
    }

    final velocity = details.primaryVelocity ?? 0.0;
    final isForward = _direction == FlipDirection.forward;

    // Determine completion threshold: drag progress > 22% or fast flick velocity
    final completed = (isForward && (velocity < -250 || _controller.value > 0.22)) ||
        (!isForward && (velocity > 250 || _controller.value > 0.22));

    if (completed) {
      _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Snap back smoothly
      _controller.animateBack(
        0.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) {
      return Center(
        child: Text(
          'No pages to display',
          style: TextStyle(color: widget.theme.secondaryTextColor),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final x = details.localPosition.dx;
            final width = constraints.maxWidth;
            if (x < width * 0.22) {
              flipBackward();
            } else if (x > width * 0.78) {
              flipForward();
            } else {
              widget.onTapCenter();
            }
          },
          onHorizontalDragStart: (d) => _onHorizontalDragStart(d, constraints),
          onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, constraints),
          onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, constraints),
          child: Container(
            color: widget.theme.backgroundColor,
            child: widget.isTwoPageSpread
                ? _buildTwoPageDesktopSpread(constraints)
                : _buildSinglePageMobile(constraints),
          ),
        );
      },
    );
  }

  // ==========================================
  // 1. Two-Page Desktop Spread (Physical Turn)
  // ==========================================
  Widget _buildTwoPageDesktopSpread(BoxConstraints constraints) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;

            // Static state: left and right flat
            if (!_isFlipping || _targetPageIndex == null) {
              final leftPage = _currentPageIndex < widget.pages.length
                  ? widget.pages[_currentPageIndex]
                  : null;
              final rightPage = (_currentPageIndex + 1) < widget.pages.length
                  ? widget.pages[_currentPageIndex + 1]
                  : null;

              return Row(
                children: [
                  Expanded(child: _buildSolidPage(leftPage, isLeftPage: true)),
                  _buildSpineCrease(),
                  Expanded(child: _buildSolidPage(rightPage, isLeftPage: false)),
                ],
              );
            }

            // Animated realistic book leaf turn
            if (_direction == FlipDirection.forward) {
              return _buildForwardSpreadFlip(t);
            } else {
              return _buildBackwardSpreadFlip(t);
            }
          },
        ),
      ),
    );
  }

  Widget _buildForwardSpreadFlip(double t) {
    final curLeft = _currentPageIndex < widget.pages.length
        ? widget.pages[_currentPageIndex]
        : null;
    final curRight = (_currentPageIndex + 1) < widget.pages.length
        ? widget.pages[_currentPageIndex + 1]
        : null;

    final nextLeft = _targetPageIndex! < widget.pages.length
        ? widget.pages[_targetPageIndex!]
        : null;
    final nextRight = (_targetPageIndex! + 1) < widget.pages.length
        ? widget.pages[_targetPageIndex! + 1]
        : null;

    return Row(
      children: [
        // LEFT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: curLeft flat
              _buildSolidPage(curLeft, isLeftPage: true),

              // Phase 2 (t > 0.5): nextLeft lands down onto left page (from 90 deg down to 0 deg)
              if (t > 0.5 && nextLeft != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY((1.0 - t) * math.pi), // from +pi/2 to 0
                  alignment: Alignment.centerRight, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSolidPage(nextLeft, isLeftPage: true),
                      // Soft landing shadow that clears out as leaf lays flat
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black.withAlpha(((1.0 - t) * 120).toInt()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // CENTER SPINE CREASE
        _buildSpineCrease(),

        // RIGHT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: nextRight flat waiting
              _buildSolidPage(nextRight, isLeftPage: false),

              // Cast shadow on nextRight
              if (t < 0.99)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withAlpha(((1.0 - t) * 60).toInt()),
                    ),
                  ),
                ),

              // Phase 1 (t <= 0.5): curRight lifts off towards spine (from 0 to -90 deg)
              if (t <= 0.5 && curRight != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(-t * math.pi), // from 0 to -pi/2
                  alignment: Alignment.centerLeft, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSolidPage(curRight, isLeftPage: false),
                      // Sheen shadow as it curls up towards vertical
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withAlpha((t * 180).toInt()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackwardSpreadFlip(double t) {
    final curLeft = _currentPageIndex < widget.pages.length
        ? widget.pages[_currentPageIndex]
        : null;
    final curRight = (_currentPageIndex + 1) < widget.pages.length
        ? widget.pages[_currentPageIndex + 1]
        : null;

    final prevLeft = _targetPageIndex! < widget.pages.length
        ? widget.pages[_targetPageIndex!]
        : null;
    final prevRight = (_targetPageIndex! + 1) < widget.pages.length
        ? widget.pages[_targetPageIndex! + 1]
        : null;

    return Row(
      children: [
        // LEFT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: prevLeft flat waiting
              _buildSolidPage(prevLeft, isLeftPage: true),

              // Shadow on prevLeft
              if (t < 0.99)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withAlpha(((1.0 - t) * 60).toInt()),
                    ),
                  ),
                ),

              // Phase 1 (t <= 0.5): curLeft lifts off towards spine (from 0 to +90 deg)
              if (t <= 0.5 && curLeft != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(t * math.pi), // from 0 to +pi/2
                  alignment: Alignment.centerRight, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSolidPage(curLeft, isLeftPage: true),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withAlpha((t * 180).toInt()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // CENTER SPINE CREASE
        _buildSpineCrease(),

        // RIGHT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: curRight flat
              _buildSolidPage(curRight, isLeftPage: false),

              // Phase 2 (t > 0.5): prevRight unfolds down onto right page (from -90 to 0 deg)
              if (t > 0.5 && prevRight != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(-(1.0 - t) * math.pi), // from -pi/2 to 0
                  alignment: Alignment.centerLeft, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSolidPage(prevRight, isLeftPage: false),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black.withAlpha(((1.0 - t) * 120).toInt()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 2. Single-Page Mobile Reader (Page Curl)
  // ==========================================
  Widget _buildSinglePageMobile(BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        if (!_isFlipping || _targetPageIndex == null) {
          final curPage = _currentPageIndex < widget.pages.length
              ? widget.pages[_currentPageIndex]
              : null;
          return _buildSolidPage(curPage, isLeftPage: null);
        }

        final curPage = _currentPageIndex < widget.pages.length
            ? widget.pages[_currentPageIndex]
            : null;
        final targetPage = _targetPageIndex! < widget.pages.length
            ? widget.pages[_targetPageIndex!]
            : null;

        final isForward = _direction == FlipDirection.forward;

        if (isForward) {
          // Turning forward: target page is underneath, curPage rotates away
          return Stack(
            fit: StackFit.expand,
            children: [
              // Target Page flat underneath
              _buildSolidPage(targetPage, isLeftPage: null),

              // Shadow over target page as top page turns
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withAlpha(((1.0 - t) * 80).toInt()),
                  ),
                ),
              ),

              // Current page lifting off towards the left spine
              if (curPage != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(-t * (math.pi / 2.2)),
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSolidPage(curPage, isLeftPage: null),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withAlpha((t * 160).toInt()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        } else {
          // Turning backward: curPage is underneath, targetPage unfolds onto screen
          return Stack(
            fit: StackFit.expand,
            children: [
              // Current Page flat underneath
              _buildSolidPage(curPage, isLeftPage: null),

              // Target Page unfolding on top
              if (targetPage != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(-(1.0 - t) * (math.pi / 2.2)),
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSolidPage(targetPage, isLeftPage: null),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black.withAlpha(((1.0 - t) * 120).toInt()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
      },
    );
  }

  // Helper: Guarantees 100% solid opaque surface with RepaintBoundary
  Widget _buildSolidPage(ReflowablePageContent? page, {bool? isLeftPage}) {
    if (page == null) {
      return Container(
        color: widget.theme.backgroundColor,
      );
    }

    return RepaintBoundary(
      child: Container(
        color: widget.theme.backgroundColor, // Guaranteed 100% OPAQUE
        child: ClipRect(
          child: widget.pageBuilder(page, isLeftPage: isLeftPage),
        ),
      ),
    );
  }

  // Physical Book Center Spine Crease
  Widget _buildSpineCrease() {
    return Container(
      width: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withAlpha(widget.theme.isDark ? 80 : 25),
            Colors.black.withAlpha(widget.theme.isDark ? 190 : 70),
            Colors.black.withAlpha(widget.theme.isDark ? 80 : 25),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
