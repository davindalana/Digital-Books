import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../processing/services/scanned_image_enhancer.dart';
import '../../providers/reader_settings_provider.dart';

enum FlipDirection { forward, backward }

/// Represents a 2-page spread (facing pages) in an open book.
class PdfSpread {
  final int spreadIndex;
  final int? leftPage; // null for Cover (Page 1) or leading blank
  final int? rightPage; // null if last page is even and has no facing page
  final bool isCover;

  const PdfSpread({
    required this.spreadIndex,
    this.leftPage,
    this.rightPage,
    this.isCover = false,
  });

  /// The primary page index for bookmarking / progress reporting
  int get primaryPage => rightPage ?? leftPage ?? 1;

  /// The secondary page index if facing page exists
  int? get secondaryPage =>
      (leftPage != null && rightPage != null) ? rightPage : null;

  /// Check whether a page number is inside this spread
  bool containsPage(int page) => leftPage == page || rightPage == page;
}

/// Retained decoded page bitmap for zero-latency, double-buffered page transitions.
class _CachedPageBitmap {
  final int pageNumber;
  final ui.Image image;
  final double width;
  final double height;
  final String configKey;

  _CachedPageBitmap({
    required this.pageNumber,
    required this.image,
    required this.width,
    required this.height,
    this.configKey = 'raw',
  });
}

class OriginalPdfReader extends StatefulWidget {
  final String pdfPath;
  final int initialPage;
  final ReadingThemeType theme;
  final PdfViewMode viewMode;
  final bool showControls;
  final ScanEnhancementConfig? enhancementConfig;
  final Function(int pageNumber, int totalPages) onPageChanged;
  final VoidCallback onTapContent;
  final VoidCallback? onSwitchToReflowable;
  final VoidCallback? onBack;
  final VoidCallback? onToggleViewMode;
  final VoidCallback? onRelinkPdf;
  final VoidCallback? onRemoveBook;

  const OriginalPdfReader({
    super.key,
    required this.pdfPath,
    required this.initialPage,
    required this.theme,
    this.viewMode = PdfViewMode.paginated,
    this.showControls = true,
    this.enhancementConfig = const ScanEnhancementConfig(),
    required this.onPageChanged,
    required this.onTapContent,
    this.onSwitchToReflowable,
    this.onBack,
    this.onToggleViewMode,
    this.onRelinkPdf,
    this.onRemoveBook,
  });

  @override
  State<OriginalPdfReader> createState() => OriginalPdfReaderState();
}

class OriginalPdfReaderState extends State<OriginalPdfReader>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _turnController;
  late TransformationController _zoomController;
  late final AnimationController _zoomAnimationController;
  late final CurvedAnimation _zoomCurvedAnimation;
  Animation<Matrix4>? _zoomAnimation;

  PdfDocument? _document;
  bool _isLoading = true;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _currentSpreadIndex = 0;
  int? _targetSpreadIndex;

  FlipDirection _direction = FlipDirection.forward;
  bool _isFlipping = false;
  bool _isDragging = false;
  double? _dragStartX;

  bool _userWantsSpread = true;
  bool _effectiveTwoPage = true;
  bool _isZoomed = false;

  // Gentle perspective factor to prevent glyph clipping artifacts
  static const double _kPerspective = 0.00010;

  // Retained bitmap cache and in-flight request tracking
  final Map<int, _CachedPageBitmap> _bitmapCache = {};
  final List<int> _cacheLruOrder = [];
  final Map<int, Future<void>> _inFlightRenders = {};
  final Map<int, PdfPageRenderCancellationToken> _cancellationTokens = {};
  static const int _maxCacheEntries = 14;

  double _lastKnownPageW = 600.0;
  double _lastKnownPageH = 850.0;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  PdfDocument? get document => _document;
  PdfViewMode get viewMode => widget.viewMode;
  bool get isTwoPageSpreadActive {
    final double width = mounted
        ? (MediaQuery.maybeSizeOf(context)?.width ?? 800.0)
        : 800.0;
    return _isEffectiveSpread(width);
  }

  @visibleForTesting
  int get cachedBitmapCount => _bitmapCache.length;

  @visibleForTesting
  bool isPageCached(int pageNumber) => _bitmapCache.containsKey(pageNumber);

  @visibleForTesting
  bool get isFlipping => _isFlipping;

  @visibleForTesting
  int? get targetSpreadIndex => _targetSpreadIndex;

  @visibleForTesting
  int get currentSpreadIndex => _currentSpreadIndex;

  int? get currentSecondaryPage {
    if (!_effectiveTwoPage) return null;
    final spreads = _getSpreads(true);
    if (_currentSpreadIndex >= 0 && _currentSpreadIndex < spreads.length) {
      final s = spreads[_currentSpreadIndex];
      if (!s.isCover && s.leftPage != null && s.rightPage != null) {
        return s.rightPage == _currentPage ? s.leftPage : s.rightPage;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
    _scrollController = ScrollController();
    _scrollController.addListener(_onContinuousScroll);

    _turnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _turnController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_targetSpreadIndex != null) {
          final isSpread = _effectiveTwoPage;
          final spreads = _getSpreads(isSpread);
          final newIndex = _targetSpreadIndex!.clamp(0, spreads.length - 1);
          final newSpread = spreads[newIndex];
          final newPage = newSpread.primaryPage;

          setState(() {
            _currentSpreadIndex = newIndex;
            _currentPage = newPage;
            _targetSpreadIndex = null;
            _isFlipping = false;
            _isDragging = false;
          });
          widget.onPageChanged(newPage, _totalPages);
          _warmCacheAroundSpread(newIndex, isSpread);
        }
        _turnController.reset();
      } else if (status == AnimationStatus.dismissed) {
        setState(() {
          _targetSpreadIndex = null;
          _isFlipping = false;
          _isDragging = false;
        });
      }
    });

    _zoomController = TransformationController();
    _zoomAnimationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (_zoomAnimation != null) {
            _zoomController.value = _zoomAnimation!.value;
          }
        });
    _zoomCurvedAnimation = CurvedAnimation(
      parent: _zoomAnimationController,
      curve: Curves.easeOutCubic,
    );

    _loadPdfDocument();
  }

  void _onContinuousScroll() {
    if (!_scrollController.hasClients || _totalPages <= 1) return;
    if (widget.viewMode != PdfViewMode.continuous) return;

    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final approxPageHeight =
        (maxScroll + _scrollController.position.viewportDimension) /
        _totalPages;
    final estimatedPage =
        ((offset + (approxPageHeight * 0.45)) / approxPageHeight).floor() + 1;
    final clampedPage = estimatedPage.clamp(1, _totalPages);
    if (clampedPage != _currentPage) {
      _currentPage = clampedPage;
      widget.onPageChanged(clampedPage, _totalPages);
    }
  }

  Future<void> _loadPdfDocument() async {
    final file = File(widget.pdfPath);
    if (!file.existsSync()) {
      if (mounted) {
        setState(() {
          _errorMessage = 'File PDF Asli tidak ditemukan di: ${widget.pdfPath}';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      if (_document != null) {
        _document?.dispose();
        _document = null;
      }
      final doc = await PdfDocument.openFile(widget.pdfPath);
      if (mounted) {
        final total = doc.pages.isNotEmpty ? doc.pages.length : 1;
        final targetPage = widget.initialPage.clamp(1, total);
        final isSpread = _effectiveTwoPage;
        final spreads = _generateSpreads(total, isSpread);
        final spreadIdx = _getSpreadIndexForPage(targetPage, spreads, isSpread);

        setState(() {
          _document = doc;
          _totalPages = total;
          _currentPage = targetPage;
          _currentSpreadIndex = spreadIdx;
          _isLoading = false;
        });
        widget.onPageChanged(targetPage, total);
        _warmCacheAroundSpread(spreadIdx, isSpread);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal membuka PDF: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _retryLoad() {
    _document?.dispose();
    _document = null;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _loadPdfDocument();
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
      _loadPdfDocument();
    } else if (oldWidget.initialPage != widget.initialPage &&
        widget.initialPage > 0 &&
        widget.initialPage != _currentPage) {
      jumpToPage(widget.initialPage);
    } else if (oldWidget.viewMode != widget.viewMode) {
      resetZoom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.viewMode == PdfViewMode.continuous &&
            _scrollController.hasClients) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final approxPageHeight =
              (maxScroll + _scrollController.position.viewportDimension) /
              (_totalPages > 0 ? _totalPages : 1);
          final targetOffset = ((_currentPage - 1) * approxPageHeight).clamp(
            0.0,
            maxScroll,
          );
          _scrollController.jumpTo(targetOffset);
        }
      });
    } else if (oldWidget.enhancementConfig != widget.enhancementConfig) {
      final isSpread = _effectiveTwoPage;
      _warmCacheAroundSpread(_currentSpreadIndex, isSpread, forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _turnController.dispose();
    _zoomAnimationController.dispose();
    _zoomCurvedAnimation.dispose();
    _zoomController.dispose();
    _scrollController.removeListener(_onContinuousScroll);
    _scrollController.dispose();

    for (final token in _cancellationTokens.values) {
      token.cancel();
    }
    _cancellationTokens.clear();
    _inFlightRenders.clear();

    for (final cached in _bitmapCache.values) {
      cached.image.dispose();
    }
    _bitmapCache.clear();
    _cacheLruOrder.clear();

    _document?.dispose();
    _document = null;
    super.dispose();
  }

  // ==========================================
  // Retained Double-Buffered Bitmap Cache Engine
  // ==========================================

  Set<int> _getActivePages() {
    final active = <int>{};
    final isSpread = _effectiveTwoPage;
    final spreads = _getSpreads(isSpread);
    if (_currentSpreadIndex >= 0 && _currentSpreadIndex < spreads.length) {
      final cur = spreads[_currentSpreadIndex];
      if (cur.leftPage != null) active.add(cur.leftPage!);
      if (cur.rightPage != null) active.add(cur.rightPage!);
    }
    if (_targetSpreadIndex != null &&
        _targetSpreadIndex! >= 0 &&
        _targetSpreadIndex! < spreads.length) {
      final tgt = spreads[_targetSpreadIndex!];
      if (tgt.leftPage != null) active.add(tgt.leftPage!);
      if (tgt.rightPage != null) active.add(tgt.rightPage!);
    }
    return active;
  }

  void _putBitmapToCache(
    int pageNumber,
    ui.Image image,
    double w,
    double h, {
    String configKey = 'raw',
  }) {
    if (_bitmapCache.containsKey(pageNumber)) {
      final old = _bitmapCache.remove(pageNumber);
      if (old?.image != image) {
        old?.image.dispose();
      }
      _cacheLruOrder.remove(pageNumber);
    }

    final activePages = _getActivePages();
    while (_bitmapCache.length >= _maxCacheEntries && _cacheLruOrder.isNotEmpty) {
      final evictCandidateIdx =
          _cacheLruOrder.indexWhere((p) => !activePages.contains(p));
      if (evictCandidateIdx != -1) {
        final evictPage = _cacheLruOrder.removeAt(evictCandidateIdx);
        _bitmapCache.remove(evictPage)?.image.dispose();
      } else {
        break;
      }
    }

    _bitmapCache[pageNumber] = _CachedPageBitmap(
      pageNumber: pageNumber,
      image: image,
      width: w,
      height: h,
      configKey: configKey,
    );
    _cacheLruOrder.add(pageNumber);
  }

  Future<void> _renderPageToCache(
    int pageNumber,
    double targetWidth,
    double targetHeight, {
    bool forceRefresh = false,
  }) async {
    final doc = _document;
    if (doc == null || pageNumber < 1 || pageNumber > doc.pages.length) return;
    if (targetWidth <= 0 || targetHeight <= 0 || targetWidth.isNaN || targetHeight.isNaN) {
      targetWidth = 600.0;
      targetHeight = 850.0;
    }

    final config = widget.enhancementConfig ?? const ScanEnhancementConfig();
    final expectedConfigKey = config.cacheKeySuffix;

    if (!forceRefresh && _bitmapCache.containsKey(pageNumber)) {
      final cached = _bitmapCache[pageNumber]!;
      if (cached.configKey == expectedConfigKey) {
        _cacheLruOrder.remove(pageNumber);
        _cacheLruOrder.add(pageNumber);
        return;
      }
    }

    if (_inFlightRenders.containsKey(pageNumber)) {
      await _inFlightRenders[pageNumber];
      return;
    }

    final page = doc.pages[pageNumber - 1];
    final swapWH = ((page.rotation.index) & 1) == 1;
    final w = swapWH ? page.height : page.width;
    final h = swapWH ? page.width : page.height;

    final scale = math.min(180 / 72.0, math.min(targetWidth / w, targetHeight / h));
    final renderW = (w * scale).roundToDouble();
    final renderH = (h * scale).roundToDouble();

    _cancellationTokens[pageNumber]?.cancel();
    final token = page.createCancellationToken();
    _cancellationTokens[pageNumber] = token;

    final renderFuture = () async {
      try {
        final pdfImage = await page.render(
          fullWidth: renderW,
          fullHeight: renderH,
          cancellationToken: token,
        );
        if (pdfImage == null) return;

        ui.Image uiImage;
        if (config.isEnabled) {
          final isLeft = (pageNumber % 2 == 0);
          final pageConfig = config.copyWith(isLeftPage: isLeft);
          final enhancedBytes = ScannedImageEnhancer.enhanceBgra(
            srcPixels: pdfImage.pixels,
            width: pdfImage.width,
            height: pdfImage.height,
            config: pageConfig,
          );
          final comp = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            enhancedBytes,
            pdfImage.width,
            pdfImage.height,
            ui.PixelFormat.bgra8888,
            (img) => comp.complete(img),
          );
          uiImage = await comp.future;
          pdfImage.dispose();
        } else {
          uiImage = await pdfImage.createImage();
          pdfImage.dispose();
        }

        if (!mounted) {
          uiImage.dispose();
          return;
        }

        _putBitmapToCache(
          pageNumber,
          uiImage,
          renderW,
          renderH,
          configKey: expectedConfigKey,
        );

        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        // Ignored if cancelled or disposed
      } finally {
        _inFlightRenders.remove(pageNumber);
        _cancellationTokens.remove(pageNumber);
      }
    }();

    _inFlightRenders[pageNumber] = renderFuture;
    await renderFuture;
  }

  void _warmCacheAroundSpread(
    int spreadIndex,
    bool isSpread, {
    bool forceRefresh = false,
  }) {
    if (_document == null) return;
    final spreads = _getSpreads(isSpread);
    if (spreadIndex < 0 || spreadIndex >= spreads.length) return;

    final pagesToWarm = <int>{};
    void addSpread(int idx) {
      if (idx >= 0 && idx < spreads.length) {
        final s = spreads[idx];
        if (s.leftPage != null) pagesToWarm.add(s.leftPage!);
        if (s.rightPage != null) pagesToWarm.add(s.rightPage!);
      }
    }

    addSpread(spreadIndex);
    addSpread(spreadIndex + 1);
    addSpread(spreadIndex - 1);
    addSpread(spreadIndex + 2);

    final config = widget.enhancementConfig ?? const ScanEnhancementConfig();
    final expectedConfigKey = config.cacheKeySuffix;

    for (final p in pagesToWarm) {
      final cached = _bitmapCache[p];
      if (forceRefresh || cached == null || cached.configKey != expectedConfigKey) {
        _renderPageToCache(
          p,
          _lastKnownPageW,
          _lastKnownPageH,
          forceRefresh: forceRefresh,
        );
      }
    }
  }

  // --- Spread Calculation & Mapping ---
  bool _isEffectiveSpread(double width) => width >= 720 && _userWantsSpread;

  List<PdfSpread> _getSpreads(bool isTwoPage) {
    return _generateSpreads(_totalPages, isTwoPage);
  }

  List<PdfSpread> _generateSpreads(int totalPages, bool isTwoPage) {
    if (totalPages <= 0) {
      return const [
        PdfSpread(spreadIndex: 0, leftPage: null, rightPage: 1, isCover: true),
      ];
    }

    if (!isTwoPage) {
      return List.generate(
        totalPages,
        (i) => PdfSpread(
          spreadIndex: i,
          leftPage: null,
          rightPage: i + 1,
          isCover: i == 0,
        ),
      );
    }

    // Spread 0: Cover page (Page 1 standalone)
    final spreads = <PdfSpread>[
      const PdfSpread(
        spreadIndex: 0,
        leftPage: null,
        rightPage: 1,
        isCover: true,
      ),
    ];

    int page = 2;
    int spreadIdx = 1;
    while (page <= totalPages) {
      final left = page;
      final right = (page + 1 <= totalPages) ? page + 1 : null;
      spreads.add(
        PdfSpread(
          spreadIndex: spreadIdx,
          leftPage: left,
          rightPage: right,
          isCover: false,
        ),
      );
      spreadIdx++;
      page += 2;
    }

    return spreads;
  }

  int _getSpreadIndexForPage(
    int page,
    List<PdfSpread> spreads,
    bool isTwoPage,
  ) {
    if (spreads.isEmpty) return 0;
    if (!isTwoPage) {
      return (page - 1).clamp(0, spreads.length - 1);
    }
    if (page <= 1) return 0;
    final idx = page ~/ 2;
    return idx.clamp(0, spreads.length - 1);
  }

  // --- Public Reader Actions ---
  void toggleTwoPageSpread() {
    setState(() {
      _userWantsSpread = !_userWantsSpread;
    });
  }

  void jumpToPage(int pageNumber) {
    final target = pageNumber.clamp(1, _totalPages > 0 ? _totalPages : 1);
    resetZoom();
    _turnController.stop();

    final isSpread = _effectiveTwoPage;
    final spreads = _getSpreads(isSpread);
    final targetSpreadIdx = _getSpreadIndexForPage(target, spreads, isSpread);

    setState(() {
      _currentPage = target;
      _currentSpreadIndex = targetSpreadIdx;
      _targetSpreadIndex = null;
      _isFlipping = false;
      _isDragging = false;
    });
    _turnController.reset();

    _warmCacheAroundSpread(targetSpreadIdx, isSpread);

    if (widget.viewMode == PdfViewMode.continuous &&
        _scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final approxHeight =
          (maxScroll + _scrollController.position.viewportDimension) /
          (_totalPages > 0 ? _totalPages : 1);
      final targetOffset = ((target - 1) * approxHeight).clamp(0.0, maxScroll);
      _scrollController.jumpTo(targetOffset);
    }

    widget.onPageChanged(target, _totalPages);
  }

  void nextPage() {
    if (_document == null) return;
    if (widget.viewMode == PdfViewMode.continuous) {
      jumpToPage(_currentPage + 1);
      return;
    }

    final isSpread = _effectiveTwoPage;
    final spreads = _getSpreads(isSpread);

    if (_isFlipping) {
      if (_direction == FlipDirection.forward) {
        // Fast-forward commit current transition immediately
        if (_targetSpreadIndex != null) {
          final committedIndex =
              _targetSpreadIndex!.clamp(0, spreads.length - 1);
          final committedSpread = spreads[committedIndex];
          final committedPage = committedSpread.primaryPage;
          _currentSpreadIndex = committedIndex;
          _currentPage = committedPage;
          widget.onPageChanged(committedPage, _totalPages);
        }
        _turnController.stop();
        _turnController.reset();

        // Start next forward turn if not at the end
        if (_currentSpreadIndex < spreads.length - 1) {
          resetZoom();
          final nextTarget = _currentSpreadIndex + 1;
          setState(() {
            _direction = FlipDirection.forward;
            _targetSpreadIndex = nextTarget;
            _isFlipping = true;
          });
          _warmCacheAroundSpread(nextTarget, isSpread);
          _turnController.forward(from: 0.0);
        } else {
          setState(() {
            _targetSpreadIndex = null;
            _isFlipping = false;
          });
        }
        return;
      } else {
        // Was turning backward, user requested next -> reverse back smoothly!
        _turnController.reverse();
        return;
      }
    }

    if (_currentSpreadIndex < spreads.length - 1) {
      resetZoom();
      final target = _currentSpreadIndex + 1;
      setState(() {
        _direction = FlipDirection.forward;
        _targetSpreadIndex = target;
        _isFlipping = true;
      });
      _warmCacheAroundSpread(target, isSpread);
      _turnController.forward(from: 0.0);
    }
  }

  void previousPage() {
    if (_document == null) return;
    if (widget.viewMode == PdfViewMode.continuous) {
      jumpToPage(_currentPage - 1);
      return;
    }

    final isSpread = _effectiveTwoPage;
    final spreads = _getSpreads(isSpread);

    if (_isFlipping) {
      if (_direction == FlipDirection.backward) {
        // Fast-forward commit current backward transition immediately
        if (_targetSpreadIndex != null) {
          final committedIndex =
              _targetSpreadIndex!.clamp(0, spreads.length - 1);
          final committedSpread = spreads[committedIndex];
          final committedPage = committedSpread.primaryPage;
          _currentSpreadIndex = committedIndex;
          _currentPage = committedPage;
          widget.onPageChanged(committedPage, _totalPages);
        }
        _turnController.stop();
        _turnController.reset();

        // Start next backward turn if not at beginning
        if (_currentSpreadIndex > 0) {
          resetZoom();
          final prevTarget = _currentSpreadIndex - 1;
          setState(() {
            _direction = FlipDirection.backward;
            _targetSpreadIndex = prevTarget;
            _isFlipping = true;
          });
          _warmCacheAroundSpread(prevTarget, isSpread);
          _turnController.forward(from: 0.0);
        } else {
          setState(() {
            _targetSpreadIndex = null;
            _isFlipping = false;
          });
        }
        return;
      } else {
        // Was turning forward, user requested previous -> reverse back smoothly!
        _turnController.reverse();
        return;
      }
    }

    if (_currentSpreadIndex > 0) {
      resetZoom();
      final target = _currentSpreadIndex - 1;
      setState(() {
        _direction = FlipDirection.backward;
        _targetSpreadIndex = target;
        _isFlipping = true;
      });
      _warmCacheAroundSpread(target, isSpread);
      _turnController.forward(from: 0.0);
    }
  }

  // --- Zoom Actions ---
  void zoomIn() {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale + 0.4).clamp(1.0, 3.5);
    _zoomToScale(targetScale);
  }

  void zoomOut() {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale - 0.4).clamp(1.0, 3.5);
    _zoomToScale(targetScale);
  }

  void resetZoom() {
    _zoomToScale(1.0);
  }

  void _zoomToScale(double targetScale) {
    if (targetScale <= 1.02) {
      _animateZoomToMatrix(Matrix4.identity(), false);
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(800, 600);
    final center = Offset(size.width / 2, size.height / 2);

    final target = Matrix4.identity()
      ..setTranslationRaw(
        center.dx * (1 - targetScale),
        center.dy * (1 - targetScale),
        0.0,
      )
      // ignore: deprecated_member_use
      ..scale(targetScale, targetScale, 1.0);

    _animateZoomToMatrix(target, true);
  }

  void _animateZoomToMatrix(Matrix4 targetMatrix, bool willBeZoomed) {
    _zoomAnimationController.stop();
    _zoomAnimation = Matrix4Tween(
      begin: _zoomController.value,
      end: targetMatrix,
    ).animate(_zoomCurvedAnimation);
    _zoomAnimationController.forward(from: 0.0);
    if (_isZoomed != willBeZoomed) {
      setState(() => _isZoomed = willBeZoomed);
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_isZoomed) {
      resetZoom();
    } else {
      final position = details.localPosition;
      final target = Matrix4.identity()
        ..setTranslationRaw(-position.dx, -position.dy, 0.0)
        // ignore: deprecated_member_use
        ..scale(2.0, 2.0, 1.0);
      _animateZoomToMatrix(target, true);
    }
  }

  // --- Interactive Drag Handling ---
  void _onHorizontalDragStart(
    DragStartDetails details,
    BoxConstraints constraints,
  ) {
    if (_isZoomed) return;
    if (_isFlipping && !_isDragging) {
      _turnController.stop();
      if (_targetSpreadIndex != null && _turnController.value > 0.5) {
        final isSpread = _effectiveTwoPage;
        final spreads = _getSpreads(isSpread);
        _currentSpreadIndex = _targetSpreadIndex!.clamp(0, spreads.length - 1);
        _currentPage = spreads[_currentSpreadIndex].primaryPage;
        widget.onPageChanged(_currentPage, _totalPages);
      }
      _turnController.reset();
      _isFlipping = false;
      _targetSpreadIndex = null;
    }
    _dragStartX = details.localPosition.dx;
  }

  void _onHorizontalDragUpdate(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    if (_isZoomed || _dragStartX == null || _document == null) return;
    final deltaX = details.localPosition.dx - _dragStartX!;
    if (!_isDragging && deltaX.abs() < 8.0) return;

    final isSpread = _effectiveTwoPage;
    final spreads = _getSpreads(isSpread);
    final dragSpan = isSpread
        ? (constraints.maxWidth * 0.45)
        : (constraints.maxWidth * 0.80);

    if (deltaX < 0) {
      // Swiping left -> Turn forward to next spread
      final target = _currentSpreadIndex + 1;
      if (target >= spreads.length) return;

      if (!_isDragging ||
          _targetSpreadIndex != target ||
          _direction != FlipDirection.forward) {
        setState(() {
          _isDragging = true;
          _direction = FlipDirection.forward;
          _targetSpreadIndex = target;
          _isFlipping = true;
        });
      }
      final progress = (-deltaX / dragSpan).clamp(0.0, 1.0);
      _turnController.value = progress;
    } else if (deltaX > 0) {
      // Swiping right -> Turn backward to previous spread
      final target = _currentSpreadIndex - 1;
      if (target < 0) return;

      if (!_isDragging ||
          _targetSpreadIndex != target ||
          _direction != FlipDirection.backward) {
        setState(() {
          _isDragging = true;
          _direction = FlipDirection.backward;
          _targetSpreadIndex = target;
          _isFlipping = true;
        });
      }
      final progress = (deltaX / dragSpan).clamp(0.0, 1.0);
      _turnController.value = progress;
    }
  }

  void _onHorizontalDragEnd(
    DragEndDetails details,
    BoxConstraints constraints,
  ) {
    if (!_isDragging) {
      _dragStartX = null;
      return;
    }
    _isDragging = false;
    _dragStartX = null;

    if (_targetSpreadIndex == null) {
      setState(() => _isFlipping = false);
      _turnController.reset();
      return;
    }

    final velocity = details.primaryVelocity ?? 0.0;
    final isForward = _direction == FlipDirection.forward;
    final completed =
        (isForward && (velocity < -250 || _turnController.value > 0.20)) ||
        (!isForward && (velocity > 250 || _turnController.value > 0.20));

    if (completed) {
      _turnController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _turnController.animateBack(
        0.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

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
                'Menyiapkan tampilan buku untuk dibaca',
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
          onRelinkPdf: widget.onRelinkPdf,
          onRemoveBook: widget.onRemoveBook,
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
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): zoomIn,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): zoomOut,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): resetZoom,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            resetZoom,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: widget.theme.backgroundColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktopOrTablet = constraints.maxWidth >= 700;
              final isContinuous = widget.viewMode == PdfViewMode.continuous;
              final isSpread = _isEffectiveSpread(constraints.maxWidth);
              _effectiveTwoPage = isSpread;

              final spreads = _getSpreads(isSpread);
              if (_currentSpreadIndex >= spreads.length) {
                _currentSpreadIndex = _getSpreadIndexForPage(
                  _currentPage,
                  spreads,
                  isSpread,
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: ScrollConfiguration(
                      behavior: const ScrollBehavior().copyWith(
                        dragDevices: {
                          ui.PointerDeviceKind.touch,
                          ui.PointerDeviceKind.mouse,
                          ui.PointerDeviceKind.trackpad,
                          ui.PointerDeviceKind.stylus,
                        },
                        scrollbars: isContinuous,
                      ),
                      child: isContinuous
                          ? _buildContinuousView(doc, constraints)
                          : _buildInteractiveBookView(
                              doc,
                              constraints,
                              isSpread,
                              spreads,
                            ),
                    ),
                  ),

                  // Floating Previous Button on left edge
                  if (isDesktopOrTablet &&
                      !isContinuous &&
                      widget.showControls &&
                      _currentSpreadIndex > 0)
                    Positioned(
                      left: 16,
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
                  if (isDesktopOrTablet &&
                      !isContinuous &&
                      widget.showControls &&
                      _currentSpreadIndex < spreads.length - 1)
                    Positioned(
                      right: 16,
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

  // ==========================================
  // Open-Book Interactive View
  // ==========================================
  Widget _buildInteractiveBookView(
    PdfDocument doc,
    BoxConstraints constraints,
    bool isSpread,
    List<PdfSpread> spreads,
  ) {
    final curSpread = spreads[_currentSpreadIndex.clamp(0, spreads.length - 1)];

    Widget content = AnimatedBuilder(
      animation: _turnController,
      builder: (context, _) {
        final t = _turnController.value;

        if (!_isFlipping || _targetSpreadIndex == null) {
          return _buildSolidSpread(doc, curSpread, constraints, isSpread);
        }

        final targetSpread =
            spreads[_targetSpreadIndex!.clamp(0, spreads.length - 1)];

        if (isSpread) {
          return _buildTwoPageFlip(
            doc,
            constraints,
            curSpread,
            targetSpread,
            t,
          );
        } else {
          return _buildSinglePageFlip(
            doc,
            constraints,
            curSpread,
            targetSpread,
            t,
          );
        }
      },
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        if (_isZoomed) {
          widget.onTapContent();
          return;
        }
        final width = constraints.maxWidth;
        final x = details.localPosition.dx;
        if (x < width * 0.20) {
          previousPage();
        } else if (x > width * 0.80) {
          nextPage();
        } else {
          widget.onTapContent();
        }
      },
      onDoubleTapDown: _onDoubleTapDown,
      onHorizontalDragStart: (d) => _onHorizontalDragStart(d, constraints),
      onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, constraints),
      onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, constraints),
      child: InteractiveViewer(
        transformationController: _zoomController,
        minScale: 1.0,
        maxScale: 3.5,
        panEnabled: _isZoomed,
        scaleEnabled: true,
        clipBehavior: Clip.none,
        onInteractionEnd: (details) {
          final scale = _zoomController.value.getMaxScaleOnAxis();
          if (scale <= 1.05 && _isZoomed) {
            setState(() => _isZoomed = false);
          } else if (scale > 1.05 && !_isZoomed) {
            setState(() => _isZoomed = true);
          }
        },
        child: content,
      ),
    );
  }

  // Sizing Geometry for Open Book
  ({double bookW, double bookH, double pageW, double pageH})
  _calculateBookGeometry(
    PdfDocument doc,
    BoxConstraints constraints,
    bool isTwoPage,
    bool isCover,
  ) {
    final horizontalMargin = constraints.maxWidth < 600
        ? 10.0
        : (constraints.maxWidth > 1200 ? 36.0 : 20.0);
    final verticalMargin = constraints.maxHeight < 600 ? 10.0 : 18.0;

    final availW = math.max(
      100.0,
      constraints.maxWidth - (horizontalMargin * 2),
    );
    final availH = math.max(
      100.0,
      constraints.maxHeight - (verticalMargin * 2),
    );

    double pageRatio = 1.0 / 1.414;
    if (doc.pages.isNotEmpty && doc.pages.first.height > 0) {
      pageRatio = doc.pages.first.width / doc.pages.first.height;
    }

    if (isTwoPage && !isCover) {
      final spreadRatio = 2.0 * pageRatio;
      double bookW, bookH;
      if (availH.isInfinite || availW / availH <= spreadRatio) {
        bookW = availW;
        bookH = bookW / spreadRatio;
      } else {
        bookH = availH;
        bookW = bookH * spreadRatio;
      }
      return (bookW: bookW, bookH: bookH, pageW: bookW / 2.0, pageH: bookH);
    } else {
      double bookW, bookH;
      if (availH.isInfinite || availW / availH <= pageRatio) {
        bookW = availW;
        bookH = bookW / pageRatio;
      } else {
        bookH = availH;
        bookW = bookH * pageRatio;
      }
      return (bookW: bookW, bookH: bookH, pageW: bookW, pageH: bookH);
    }
  }

  // Static Spread: Clean, crisp, RepaintBoundary protected
  Widget _buildSolidSpread(
    PdfDocument doc,
    PdfSpread spread,
    BoxConstraints constraints,
    bool isTwoPage,
  ) {
    final geo = _calculateBookGeometry(
      doc,
      constraints,
      isTwoPage,
      spread.isCover,
    );
    _lastKnownPageW = geo.pageW;
    _lastKnownPageH = geo.pageH;

    final paperColor = widget.theme.isDark
        ? const Color(0xFF232325)
        : (widget.theme == ReadingThemeType.sepia
            ? const Color(0xFFF4ECD8)
            : const Color(0xFFFAF9F6));

    if (!isTwoPage || spread.isCover) {
      // Single Page / Cover card
      final curPageNum = spread.rightPage ?? spread.leftPage ?? 1;

      return Center(
        child: Container(
          width: geo.pageW,
          height: geo.pageH,
          decoration: BoxDecoration(
            color: paperColor,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 40),
                blurRadius: widget.theme.isDark ? 30 : 20,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(widget.theme.isDark ? 90 : 20),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPageSurface(
                doc: doc,
                pageNumber: curPageNum,
                isLeft: null,
                width: geo.pageW,
                height: geo.pageH,
              ),
              // Subtle spine fold on left edge for closed cover
              if (spread.isCover)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 14,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withAlpha(
                              widget.theme.isDark ? 90 : 45,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Two-Page Open Book Spread
    return Center(
      child: Container(
        width: geo.bookW,
        height: geo.bookH,
        decoration: BoxDecoration(
          color: paperColor,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 40),
              blurRadius: widget.theme.isDark ? 32 : 22,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withAlpha(widget.theme.isDark ? 85 : 20),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: _buildPageSurface(
                doc: doc,
                pageNumber: spread.leftPage,
                isLeft: true,
                width: geo.pageW,
                height: geo.pageH,
              ),
            ),
            _buildCenterSpineCrease(),
            Expanded(
              child: _buildPageSurface(
                doc: doc,
                pageNumber: spread.rightPage,
                isLeft: false,
                width: geo.pageW,
                height: geo.pageH,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Realistic Page Surface with Retained Double-Buffered Bitmaps & Spine Shadowing
  Widget _buildPageSurface({
    required PdfDocument doc,
    required int? pageNumber,
    required bool? isLeft,
    required double width,
    required double height,
  }) {
    final paperColor = widget.theme.isDark
        ? const Color(0xFF232325)
        : (widget.theme == ReadingThemeType.sepia
            ? const Color(0xFFF4ECD8)
            : const Color(0xFFFAF9F6));

    if (pageNumber == null) {
      return Container(color: paperColor);
    }

    _lastKnownPageW = width;
    _lastKnownPageH = height;

    final config = widget.enhancementConfig ?? const ScanEnhancementConfig();
    final expectedKey = config.cacheKeySuffix;
    final cached = _bitmapCache[pageNumber];

    if (cached == null || cached.configKey != expectedKey) {
      _renderPageToCache(pageNumber, width, height);
    }

    return RepaintBoundary(
      child: Container(
        color: paperColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: paperColor),

            if (cached != null)
              Align(
                alignment: Alignment.center,
                child: AspectRatio(
                  aspectRatio: cached.width / cached.height,
                  child: RawImage(
                    image: cached.image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              )
            else
              Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.theme.isDark
                        ? const Color(0xFF6B7280)
                        : const Color(0xFFD4AF37),
                  ),
                ),
              ),

            // Inner Spine Crease Shadow (realistic book fold)
            if (isLeft != null)
              Positioned(
                top: 0,
                bottom: 0,
                left: isLeft ? null : 0,
                right: isLeft ? 0 : null,
                width: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isLeft
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        end: isLeft
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        colors: [
                          Colors.transparent,
                          Colors.black.withAlpha(widget.theme.isDark ? 55 : 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Subtle outer page stack edge
            if (isLeft != null)
              Positioned(
                top: 0,
                bottom: 0,
                left: isLeft ? 0 : null,
                right: isLeft ? null : 0,
                width: 8,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isLeft
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        end: isLeft
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        colors: [
                          Colors.black.withAlpha(widget.theme.isDark ? 25 : 12),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterSpineCrease() {
    return Container(
      width: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.theme.isDark ? Colors.black87 : const Color(0xFFD0D0D0),
            widget.theme.isDark ? Colors.black54 : const Color(0xFFE5E5E5),
            widget.theme.isDark ? Colors.black87 : const Color(0xFFD0D0D0),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 3D Two-Page Spread Flip Animation
  // ==========================================
  Widget _buildTwoPageFlip(
    PdfDocument doc,
    BoxConstraints constraints,
    PdfSpread curSpread,
    PdfSpread targetSpread,
    double t,
  ) {
    final isForward = _direction == FlipDirection.forward;
    final geo = _calculateBookGeometry(doc, constraints, true, false);

    return Center(
      child: Container(
        width: geo.bookW,
        height: geo.bookH,
        decoration: BoxDecoration(
          color: widget.theme.isDark
              ? const Color(0xFF232325)
              : (widget.theme == ReadingThemeType.sepia
                  ? const Color(0xFFF4ECD8)
                  : const Color(0xFFFAF9F6)),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 40),
              blurRadius: widget.theme.isDark ? 32 : 22,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: isForward
            ? _buildForwardSpreadTurn(doc, geo, curSpread, targetSpread, t)
            : _buildBackwardSpreadTurn(doc, geo, curSpread, targetSpread, t),
      ),
    );
  }

  Widget _buildForwardSpreadTurn(
    PdfDocument doc,
    ({double bookW, double bookH, double pageW, double pageH}) geo,
    PdfSpread curSpread,
    PdfSpread nextSpread,
    double t,
  ) {
    return Row(
      children: [
        // LEFT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: current left page flat
              _buildPageSurface(
                doc: doc,
                pageNumber: curSpread.leftPage,
                isLeft: true,
                width: geo.pageW,
                height: geo.pageH,
              ),

              // Phase 2 (t > 0.5): next left page lands down onto left page (from 90 to 0 deg)
              if (t > 0.5 && nextSpread.leftPage != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY((1.0 - t) * math.pi),
                  alignment: Alignment.centerRight, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPageSurface(
                        doc: doc,
                        pageNumber: nextSpread.leftPage,
                        isLeft: true,
                        width: geo.pageW,
                        height: geo.pageH,
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black.withAlpha(
                              ((1.0 - t) * 110).toInt(),
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
        _buildCenterSpineCrease(),

        // RIGHT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: next right page flat waiting
              _buildPageSurface(
                doc: doc,
                pageNumber: nextSpread.rightPage,
                isLeft: false,
                width: geo.pageW,
                height: geo.pageH,
              ),

              // Cast shadow on next right
              if (t < 0.99)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withAlpha(((1.0 - t) * 60).toInt()),
                    ),
                  ),
                ),

              // Phase 1 (t <= 0.5): current right page lifts up towards spine (from 0 to -90 deg)
              if (t <= 0.5 && curSpread.rightPage != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(-t * math.pi),
                  alignment: Alignment.centerLeft, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPageSurface(
                        doc: doc,
                        pageNumber: curSpread.rightPage,
                        isLeft: false,
                        width: geo.pageW,
                        height: geo.pageH,
                      ),
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
          ),
        ),
      ],
    );
  }

  Widget _buildBackwardSpreadTurn(
    PdfDocument doc,
    ({double bookW, double bookH, double pageW, double pageH}) geo,
    PdfSpread curSpread,
    PdfSpread prevSpread,
    double t,
  ) {
    return Row(
      children: [
        // LEFT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: prev left page flat waiting
              _buildPageSurface(
                doc: doc,
                pageNumber: prevSpread.leftPage,
                isLeft: true,
                width: geo.pageW,
                height: geo.pageH,
              ),

              if (t < 0.99)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withAlpha(((1.0 - t) * 60).toInt()),
                    ),
                  ),
                ),

              // Phase 1 (t <= 0.5): cur left page lifts up towards spine (from 0 to +90 deg)
              if (t <= 0.5 && curSpread.leftPage != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(t * math.pi),
                  alignment: Alignment.centerRight, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPageSurface(
                        doc: doc,
                        pageNumber: curSpread.leftPage,
                        isLeft: true,
                        width: geo.pageW,
                        height: geo.pageH,
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
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
          ),
        ),

        // CENTER SPINE CREASE
        _buildCenterSpineCrease(),

        // RIGHT COLUMN
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath: cur right page flat
              _buildPageSurface(
                doc: doc,
                pageNumber: curSpread.rightPage,
                isLeft: false,
                width: geo.pageW,
                height: geo.pageH,
              ),

              // Phase 2 (t > 0.5): prev right page lands down (from -90 to 0 deg)
              if (t > 0.5 && prevSpread.rightPage != null)
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _kPerspective)
                    ..rotateY(-(1.0 - t) * math.pi),
                  alignment: Alignment.centerLeft, // Hinges at spine
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPageSurface(
                        doc: doc,
                        pageNumber: prevSpread.rightPage,
                        isLeft: false,
                        width: geo.pageW,
                        height: geo.pageH,
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black.withAlpha(
                              ((1.0 - t) * 110).toInt(),
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

  // ==========================================
  // Single-Page Curl Animation (Mobile / Narrow)
  // ==========================================
  Widget _buildSinglePageFlip(
    PdfDocument doc,
    BoxConstraints constraints,
    PdfSpread curSpread,
    PdfSpread targetSpread,
    double t,
  ) {
    final isForward = _direction == FlipDirection.forward;
    final geo = _calculateBookGeometry(doc, constraints, false, false);

    final curPage = curSpread.rightPage ?? curSpread.leftPage;
    final targetPage = targetSpread.rightPage ?? targetSpread.leftPage;

    return Center(
      child: Container(
        width: geo.pageW,
        height: geo.pageH,
        decoration: BoxDecoration(
          color: widget.theme.isDark
              ? const Color(0xFF232325)
              : (widget.theme == ReadingThemeType.sepia
                  ? const Color(0xFFF4ECD8)
                  : const Color(0xFFFAF9F6)),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 40),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: isForward
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _buildPageSurface(
                    doc: doc,
                    pageNumber: targetPage,
                    isLeft: null,
                    width: geo.pageW,
                    height: geo.pageH,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withAlpha(((1.0 - t) * 70).toInt()),
                      ),
                    ),
                  ),
                  if (curPage != null)
                    Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, _kPerspective)
                        ..rotateY(-t * (math.pi / 2.2)),
                      alignment: Alignment.centerLeft,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPageSurface(
                            doc: doc,
                            pageNumber: curPage,
                            isLeft: null,
                            width: geo.pageW,
                            height: geo.pageH,
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withAlpha((t * 150).toInt()),
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
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _buildPageSurface(
                    doc: doc,
                    pageNumber: curPage,
                    isLeft: null,
                    width: geo.pageW,
                    height: geo.pageH,
                  ),
                  if (targetPage != null)
                    Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, _kPerspective)
                        ..rotateY(-(1.0 - t) * (math.pi / 2.2)),
                      alignment: Alignment.centerLeft,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPageSurface(
                            doc: doc,
                            pageNumber: targetPage,
                            isLeft: null,
                            width: geo.pageW,
                            height: geo.pageH,
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: Colors.black.withAlpha(
                                  ((1.0 - t) * 110).toInt(),
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
    );
  }

  // ==========================================
  // Continuous Vertical Scroll View
  // ==========================================
  Widget _buildContinuousView(PdfDocument doc, BoxConstraints constraints) {
    final horizontalPadding = constraints.maxWidth < 600
        ? 8.0
        : (constraints.maxWidth > 1200 ? 36.0 : 20.0);

    return ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.vertical,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      cacheExtent: 1500.0,
      itemCount: _totalPages,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 20,
      ),
      itemBuilder: (context, index) {
        final pageNum = index + 1;
        final geo = _calculateBookGeometry(doc, constraints, false, false);

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: Container(
              width: geo.pageW,
              height: geo.pageH,
              decoration: BoxDecoration(
                color: widget.theme.isDark
                    ? const Color(0xFF232325)
                    : (widget.theme == ReadingThemeType.sepia
                        ? const Color(0xFFF4ECD8)
                        : const Color(0xFFFAF9F6)),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(
                      widget.theme.isDark ? 150 : 35,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildPageSurface(
                doc: doc,
                pageNumber: pageNum,
                isLeft: null,
                width: geo.pageW,
                height: geo.pageH,
              ),
            ),
          ),
        );
      },
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
    final bgAlpha = _isHovered
        ? (widget.isDark ? 210 : 190)
        : (widget.isDark ? 90 : 70);
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

class _PdfErrorView extends StatelessWidget {
  final String title;
  final String message;
  final ReadingThemeType theme;
  final VoidCallback onRetry;
  final VoidCallback? onSwitchToReflowable;
  final VoidCallback? onBack;
  final VoidCallback? onRelinkPdf;
  final VoidCallback? onRemoveBook;

  const _PdfErrorView({
    required this.title,
    required this.message,
    required this.theme,
    required this.onRetry,
    this.onSwitchToReflowable,
    this.onBack,
    this.onRelinkPdf,
    this.onRemoveBook,
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
              color: theme.isDark
                  ? Colors.white.withAlpha(25)
                  : Colors.black.withAlpha(15),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Coba Lagi',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.chrome_reader_mode_outlined,
                        size: 18,
                      ),
                      label: const Text(
                        'Buka Versi Teks',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: onSwitchToReflowable,
                    ),
                  if (onRelinkPdf != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF007AFF),
                        side: const BorderSide(color: Color(0xFF007AFF)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text(
                        'Tautkan Ulang PDF',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: onRelinkPdf,
                    ),
                  if (onRemoveBook != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(
                          color: Colors.redAccent.withAlpha(120),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text(
                        'Hapus Buku',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: onRemoveBook,
                    ),
                  if (onBack != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.secondaryTextColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
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
