import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../core/theme/reading_theme.dart';

class OriginalPdfReader extends StatefulWidget {
  final String pdfPath;
  final int initialPage;
  final ReadingThemeType theme;
  final Function(int pageNumber, int totalPages) onPageChanged;

  const OriginalPdfReader({
    super.key,
    required this.pdfPath,
    required this.initialPage,
    required this.theme,
    required this.onPageChanged,
  });

  @override
  State<OriginalPdfReader> createState() => _OriginalPdfReaderState();
}

class _OriginalPdfReaderState extends State<OriginalPdfReader> {
  PdfViewerController? _controller;
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
    _controller = PdfViewerController();
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
        ),
      ),
    );
  }
}

