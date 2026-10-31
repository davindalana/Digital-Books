import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
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
  final VoidCallback? onSwitchToReflowable;
  final VoidCallback? onBack;

  const OriginalPdfReader({
    super.key,
    required this.pdfPath,
    required this.initialPage,
    required this.theme,
    required this.onPageChanged,
    required this.onTapContent,
    this.onSwitchToReflowable,
    this.onBack,
  });

  @override
  State<OriginalPdfReader> createState() => OriginalPdfReaderState();
}

class OriginalPdfReaderState extends State<OriginalPdfReader> {
  late PageController _pageController;
  PdfDocument? _document;
  bool _isLoading = true;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  bool _isJumping = false;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  PdfDocument? get document => _document;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
    _pageController = PageController(initialPage: _currentPage - 1);
    _loadPdfDocument();
  }

  void _retryLoad() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _loadPdfDocument();
  }

  Future<void> _loadPdfDocument() async {
    debugPrint('[PDF_DIAGNOSTIC] === OriginalPdfReader._loadPdfDocument ===');
    debugPrint('[PDF_DIAGNOSTIC] Target PDF Path: ${widget.pdfPath}');

    final file = File(widget.pdfPath);
    final exists = file.existsSync();
    debugPrint('[PDF_DIAGNOSTIC] File exists check: $exists');

    if (!exists) {
      debugPrint('[PDF_DIAGNOSTIC] ERROR: File does not exist at ${widget.pdfPath}');
      if (mounted) {
        setState(() {
          _errorMessage = 'File PDF Asli tidak ditemukan di: ${widget.pdfPath}';
          _isLoading = false;
        });
      }
      return;
    }

    final fileSize = file.lengthSync();
    debugPrint('[PDF_DIAGNOSTIC] File size: $fileSize bytes (${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB)');
    debugPrint('[PDF_DIAGNOSTIC] Calling PdfDocument.openFile()...');

    try {
      final stopwatch = Stopwatch()..start();
      final doc = await PdfDocument.openFile(widget.pdfPath);
      stopwatch.stop();

      debugPrint('[PDF_DIAGNOSTIC] PdfDocument.openFile SUCCEEDED in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('[PDF_DIAGNOSTIC] Total PDF pages found: ${doc.pages.length}');

      if (mounted) {
        setState(() {
          _document = doc;
          _totalPages = doc.pages.isNotEmpty ? doc.pages.length : 1;
          _isLoading = false;
        });
        widget.onPageChanged(_currentPage, _totalPages);
      }
    } catch (e, stack) {
      debugPrint('[PDF_DIAGNOSTIC] PDFium/openFile EXCEPTION: $e');
      debugPrint('[PDF_DIAGNOSTIC] Stack trace: $stack');
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal membuka PDF: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant OriginalPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath) {
      _document?.dispose();
      _document = null;
      _isLoading = true;
      _errorMessage = null;
      _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
      _pageController = PageController(initialPage: _currentPage - 1);
      _loadPdfDocument();
    } else if (oldWidget.initialPage != widget.initialPage &&
        widget.initialPage > 0 &&
        widget.initialPage != _currentPage) {
      jumpToPage(widget.initialPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _document?.dispose();
    super.dispose();
  }

  void jumpToPage(int pageNumber) {
    final target = pageNumber.clamp(1, _totalPages > 0 ? _totalPages : 1);
    if (_currentPage != target) {
      _isJumping = true;
      setState(() => _currentPage = target);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(target - 1);
      }
      widget.onPageChanged(target, _totalPages);
      Future.microtask(() => _isJumping = false);
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
    if (_isLoading) {
      return Container(
        color: widget.theme.backgroundColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  color: Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Memuat Dokumen PDF...',
                style: TextStyle(
                  color: widget.theme.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Menyiapkan halaman buku untuk dibaca',
                style: TextStyle(
                  color: widget.theme.secondaryTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _document == null) {
      final fileExists = File(widget.pdfPath).existsSync();
      return Container(
        color: widget.theme.backgroundColor,
        child: _PdfErrorView(
          title: fileExists
              ? 'Gagal Membuka Berkas PDF'
              : 'Berkas PDF Tidak Ditemukan',
          message: _errorMessage ?? 'Dokumen PDF tidak dapat dimuat.',
          theme: widget.theme,
          onRetry: _retryLoad,
          onSwitchToReflowable: widget.onSwitchToReflowable,
          onBack: widget.onBack,
        ),
      );
    }

    final doc = _document!;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              debugPrint('[PDF_DIAGNOSTIC] OriginalPdfReader constraints: ${constraints.maxWidth.toStringAsFixed(1)}x${constraints.maxHeight.toStringAsFixed(1)}');
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Horizontal PageView with snap physics & multi-device drag support
                  Positioned.fill(
                    child: ScrollConfiguration(
                      behavior: const ScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                        scrollbars: false,
                      ),
                      child: PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.horizontal,
                        physics: const PageScrollPhysics(),
                        itemCount: _totalPages,
                        onPageChanged: (index) {
                          if (_isJumping) return;
                          final newPage = index + 1;
                          setState(() => _currentPage = newPage);
                          widget.onPageChanged(newPage, _totalPages);
                        },
                        itemBuilder: (context, index) {
                          return _PdfPageItemView(
                            key: ValueKey('pdf_page_${index + 1}'),
                            document: doc,
                            pageNumber: index + 1,
                            theme: widget.theme,
                            onTapContent: widget.onTapContent,
                            onNextPage: nextPage,
                            onPreviousPage: previousPage,
                          );
                        },
                      ),
                    ),
                  ),

                  // Floating Previous Button on left edge
                  if (_currentPage > 1)
                    Positioned(
                      left: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _FloatingNavArrow(
                          icon: Icons.chevron_left,
                          isDark: widget.theme.isDark,
                          onPressed: previousPage,
                        ),
                      ),
                    ),

                  // Floating Next Button on right edge
                  if (_currentPage < _totalPages)
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _FloatingNavArrow(
                          icon: Icons.chevron_right,
                          isDark: widget.theme.isDark,
                          onPressed: nextPage,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FloatingNavArrow extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;

  const _FloatingNavArrow({
    required this.icon,
    required this.isDark,
    required this.onPressed,
  });

  @override
  State<_FloatingNavArrow> createState() => _FloatingNavArrowState();
}

class _FloatingNavArrowState extends State<_FloatingNavArrow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgAlpha = _isHovered ? (widget.isDark ? 210 : 190) : (widget.isDark ? 90 : 70);
    final borderAlpha = _isHovered ? 80 : 35;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.isDark
                ? Color.fromARGB(bgAlpha, 25, 25, 28)
                : Color.fromARGB(bgAlpha, 255, 255, 255),
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isDark
                  ? Color.fromARGB(borderAlpha, 255, 255, 255)
                  : Color.fromARGB(borderAlpha, 0, 0, 0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(widget.isDark ? 70 : 25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            size: 26,
            color: widget.isDark ? Colors.white : Colors.black87,
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
  final VoidCallback onTapContent;
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;

  const _PdfPageItemView({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.theme,
    required this.onTapContent,
    this.onNextPage,
    this.onPreviousPage,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageIdx = widget.pageNumber - 1;
        final page = (pageIdx >= 0 && pageIdx < widget.document.pages.length)
            ? widget.document.pages[pageIdx]
            : null;

        // Compute aspect-ratio fitted page size with 20px padding
        final maxW = math.max(100.0, constraints.maxWidth - 28.0);
        final maxH = math.max(100.0, constraints.maxHeight - 28.0);

        final pageRatio = page != null && page.height > 0
            ? (page.width / page.height)
            : (1.0 / 1.414);

        double targetW, targetH;
        if (maxW / maxH > pageRatio) {
          targetH = maxH;
          targetW = maxH * pageRatio;
        } else {
          targetW = maxW;
          targetH = maxW / pageRatio;
        }

        debugPrint('[PDF_DIAGNOSTIC] _PdfPageItemView page ${widget.pageNumber} layout: constraints=(${constraints.maxWidth.toStringAsFixed(1)}x${constraints.maxHeight.toStringAsFixed(1)}), targetSheet=(${targetW.toStringAsFixed(1)}x${targetH.toStringAsFixed(1)}), ratio=${pageRatio.toStringAsFixed(3)}');

        Widget pageContent = Center(
          child: Container(
            width: targetW,
            height: targetH,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 45),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFD4AF37),
                    ),
                  ),
                ),
                PdfPageView(
                  document: widget.document,
                  pageNumber: widget.pageNumber,
                  maximumDpi: 300,
                  decorationBuilder: (context, pageSize, page, pageImage) {
                    if (pageImage != null) {
                      debugPrint('[PDF_DIAGNOSTIC] >>> PDFium SUCCESS: Page ${widget.pageNumber} rendered bitmap ${pageImage.image?.width}x${pageImage.image?.height} on pageSize ${pageSize.width.toStringAsFixed(1)}x${pageSize.height.toStringAsFixed(1)} <<<');
                    } else {
                      debugPrint('[PDF_DIAGNOSTIC] ... PDFium RENDERING: Page ${widget.pageNumber} rasterizing in progress on pageSize ${pageSize.width.toStringAsFixed(1)}x${pageSize.height.toStringAsFixed(1)} ...');
                    }
                    return Align(
                      alignment: Alignment.center,
                      child: AspectRatio(
                        aspectRatio: pageSize.width / pageSize.height,
                        child: pageImage ?? const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );

        // When zoomed, wrap in InteractiveViewer for panning
        if (_isZoomed) {
          pageContent = InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 3.5,
            panEnabled: true,
            scaleEnabled: true,
            onInteractionEnd: (details) {
              final scale = _transformationController.value.getMaxScaleOnAxis();
              if (scale <= 1.05 && _isZoomed) {
                setState(() => _isZoomed = false);
              }
            },
            child: pageContent,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) {
            if (_isZoomed) {
              widget.onTapContent();
              return;
            }
            final width = constraints.maxWidth;
            final x = details.localPosition.dx;
            if (x < width * 0.22) {
              widget.onPreviousPage?.call();
            } else if (x > width * 0.78) {
              widget.onNextPage?.call();
            } else {
              widget.onTapContent();
            }
          },
          onDoubleTapDown: _onDoubleTapDown,
          child: pageContent,
        );
      },
    );
  }
}

class _PdfErrorView extends StatelessWidget {
  final String title;
  final String message;
  final ReadingThemeType theme;
  final VoidCallback onRetry;
  final VoidCallback? onSwitchToReflowable;
  final VoidCallback? onBack;

  const _PdfErrorView({
    required this.title,
    required this.message,
    required this.theme,
    required this.onRetry,
    this.onSwitchToReflowable,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: theme.isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(theme.isDark ? 90 : 25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  size: 32,
                  color: Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Coba Lagi',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    onPressed: onRetry,
                  ),
                  if (onSwitchToReflowable != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.textColor,
                        side: BorderSide(
                          color: theme.isDark ? Colors.white24 : Colors.black26,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.chrome_reader_mode_outlined, size: 18),
                      label: const Text(
                        'Buka Versi Teks',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      onPressed: onSwitchToReflowable,
                    ),
                  if (onBack != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.secondaryTextColor,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Kembali ke Library'),
                      onPressed: onBack,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
