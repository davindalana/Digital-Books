import 'dart:io';
import 'dart:math' as math;
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
  PdfViewerController? _controller;
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
    _controller = PdfViewerController();
  }

  void jumpToPage(int pageNumber) {
    if (_controller != null && _controller!.isReady) {
      final target = pageNumber.clamp(1, _totalPages > 0 ? _totalPages : 1);
      _controller!.goToPage(pageNumber: target);
    }
  }

  void nextPage() {
    if (_controller != null && _controller!.isReady) {
      if (_currentPage < _totalPages) {
        jumpToPage(_currentPage + 1);
      }
    }
  }

  void previousPage() {
    if (_controller != null && _controller!.isReady) {
      if (_currentPage > 1) {
        jumpToPage(_currentPage - 1);
      }
    }
  }

  void zoomIn() {
    if (_controller != null && _controller!.isReady) {
      _controller!.zoomUp();
    }
  }

  void zoomOut() {
    if (_controller != null && _controller!.isReady) {
      _controller!.zoomDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.pdfPath);
    if (!file.existsSync()) {
      return Center(
        child: Text(
          'Original PDF file not found at: ${widget.pdfPath}',
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
          child: PdfViewer.file(
            widget.pdfPath,
            controller: _controller,
            initialPageNumber: _currentPage,
            params: PdfViewerParams(
              backgroundColor: widget.theme.backgroundColor,
              margin: 16.0,
              scrollHorizontallyByMouseWheel: true,
              layoutPages: (pages, params) {
                final height = pages.fold(
                  0.0,
                  (prev, page) => math.max(prev, page.height),
                ) + params.margin * 2;
                final pageLayouts = <Rect>[];
                double x = params.margin;
                for (final page in pages) {
                  pageLayouts.add(
                    Rect.fromLTWH(
                      x,
                      (height - page.height) / 2, // center vertically
                      page.width,
                      page.height,
                    ),
                  );
                  x += page.width + params.margin;
                }
                return PdfPageLayout(
                  pageLayouts: pageLayouts,
                  documentSize: Size(x, height),
                );
              },
              pageDropShadow: BoxShadow(
                color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 45),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
              onPageChanged: (page) {
                if (page != null && page != _currentPage) {
                  setState(() => _currentPage = page);
                  widget.onPageChanged(page, _totalPages);
                }
              },
              onViewerReady: (document, controller) {
                setState(() {
                  _totalPages = document.pages.length;
                });
                widget.onPageChanged(_currentPage, _totalPages);
              },
              viewerOverlayBuilder: (context, size, handleLinkTap) => [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    if (handleLinkTap(details.localPosition)) return;
                    final x = details.localPosition.dx;
                    final width = size.width;
                    if (x < width * 0.22) {
                      previousPage();
                    } else if (x > width * 0.78) {
                      nextPage();
                    } else {
                      widget.onTapContent();
                    }
                  },
                  child: IgnorePointer(
                    child: SizedBox(width: size.width, height: size.height),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
