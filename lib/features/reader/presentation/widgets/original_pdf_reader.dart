import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../core/theme/reading_theme.dart';

class OriginalPdfReader extends StatefulWidget {
  final String pdfPath;
  final int initialPage;
  final ReadingThemeType theme;
  final Function(int pageNumber, int totalPages) onPageChanged;
  final VoidCallback onTapContent;

  const OriginalPdfReader({
    super.key,
    required this.pdfPath,
    required this.initialPage,
    required this.theme,
    required this.onPageChanged,
    required this.onTapContent,
  });

  @override
  State<OriginalPdfReader> createState() => OriginalPdfReaderState();
}

class OriginalPdfReaderState extends State<OriginalPdfReader> {
  late PageController _pageController;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasReportedTotal = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
    _pageController = PageController(initialPage: _currentPage - 1);
  }

  @override
  void didUpdateWidget(covariant OriginalPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPage != widget.initialPage &&
        widget.initialPage > 0 &&
        widget.initialPage != _currentPage) {
      jumpToPage(widget.initialPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void jumpToPage(int pageNumber) {
    final target = pageNumber.clamp(1, _totalPages > 0 ? _totalPages : 1);
    if (_currentPage != target) {
      setState(() => _currentPage = target);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(target - 1);
      }
      widget.onPageChanged(target, _totalPages);
    }
  }

  void nextPage() {
    if (_pageController.hasClients && _currentPage < _totalPages) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void previousPage() {
    if (_pageController.hasClients && _currentPage > 1) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void zoomIn() {}
  void zoomOut() {}

  @override
  Widget build(BuildContext context) {
    final file = File(widget.pdfPath);
    if (!file.existsSync()) {
      return Center(
        child: Text(
          'File PDF Asli tidak ditemukan di: ${widget.pdfPath}',
          style: TextStyle(color: widget.theme.textColor),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): previousPage,
        const SingleActivator(LogicalKeyboardKey.arrowRight): nextPage,
        const SingleActivator(LogicalKeyboardKey.pageUp): previousPage,
        const SingleActivator(LogicalKeyboardKey.pageDown): nextPage,
        const SingleActivator(LogicalKeyboardKey.space): nextPage,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: widget.theme.backgroundColor,
          child: PdfDocumentViewBuilder.file(
            widget.pdfPath,
            loadingBuilder: (context) => const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD4AF37),
              ),
            ),
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                'Gagal memuat PDF: $error',
                style: TextStyle(color: widget.theme.textColor),
              ),
            ),
            builder: (context, document) {
              if (document == null) {
                return Center(
                  child: CircularProgressIndicator(
                    color: const Color(0xFFD4AF37),
                  ),
                );
              }

              if (_totalPages != document.pages.length) {
                _totalPages = document.pages.length;
                if (!_hasReportedTotal) {
                  _hasReportedTotal = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      widget.onPageChanged(_currentPage, _totalPages);
                    }
                  });
                }
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Horizontal PageView with snap physics
                      PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.horizontal,
                        physics: const PageScrollPhysics(),
                        itemCount: _totalPages,
                        onPageChanged: (index) {
                          final newPage = index + 1;
                          setState(() => _currentPage = newPage);
                          widget.onPageChanged(newPage, _totalPages);
                        },
                        itemBuilder: (context, index) {
                          return _PdfPageItemView(
                            key: ValueKey('pdf_page_${index + 1}'),
                            document: document,
                            pageNumber: index + 1,
                            theme: widget.theme,
                          );
                        },
                      ),

                      // Touch navigation zones (Left 22% = Prev, Right 22% = Next, Center = Menu)
                      Positioned.fill(
                        child: Row(
                          children: [
                            // Left Tap Zone (Previous page)
                            Expanded(
                              flex: 22,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: previousPage,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            // Center Tap Zone (Toggle UI overlay)
                            Expanded(
                              flex: 56,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: widget.onTapContent,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            // Right Tap Zone (Next page)
                            Expanded(
                              flex: 22,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: nextPage,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PdfPageItemView extends StatefulWidget {
  final PdfDocument document;
  final int pageNumber;
  final ReadingThemeType theme;

  const _PdfPageItemView({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.theme,
  });

  @override
  State<_PdfPageItemView> createState() => _PdfPageItemViewState();
}

class _PdfPageItemViewState extends State<_PdfPageItemView>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_animation != null) {
          _transformationController.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_isZoomed) {
      _animation = Matrix4Tween(
        begin: _transformationController.value,
        end: Matrix4.identity(),
      ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
      );
      _animationController.forward(from: 0);
      setState(() => _isZoomed = false);
    } else {
      final position = details.localPosition;
      final target = Matrix4.identity()
        ..setTranslationRaw(-position.dx * 1.0, -position.dy * 1.0, 0.0)
        // ignore: deprecated_member_use
        ..scale(2.0, 2.0, 1.0);
      _animation = Matrix4Tween(
        begin: _transformationController.value,
        end: target,
      ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
      );
      _animationController.forward(from: 0);
      setState(() => _isZoomed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _onDoubleTapDown,
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: 3.5,
        panEnabled: _isZoomed,
        scaleEnabled: true,
        onInteractionEnd: (details) {
          final scale = _transformationController.value.getMaxScaleOnAxis();
          if (scale > 1.08 && !_isZoomed) {
            setState(() => _isZoomed = true);
          } else if (scale <= 1.08 && _isZoomed) {
            setState(() => _isZoomed = false);
          }
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 14.0),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 45),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: PdfPageView(
                document: widget.document,
                pageNumber: widget.pageNumber,
                maximumDpi: 300,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
