import 'dart:io';
import 'package:flutter/material.dart';
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

    return Container(
      color: widget.theme.backgroundColor,
      child: PdfViewer.file(
        widget.pdfPath,
        controller: _controller,
        initialPageNumber: _currentPage,
        params: PdfViewerParams(
          backgroundColor: widget.theme.backgroundColor,
          margin: 24.0,
          pageDropShadow: BoxShadow(
            color: Colors.black.withAlpha(widget.theme.isDark ? 160 : 45),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 4),
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
                if (!handleLinkTap(details.localPosition)) {
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
    );
  }
}
