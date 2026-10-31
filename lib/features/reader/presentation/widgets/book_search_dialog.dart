import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../models/book_document.dart';

class BookSearchResult {
  final int chapterIndex;
  final String chapterTitle;
  final int pageNumber;
  final String fullText;
  final int matchStartIndex;
  final int matchEndIndex;

  BookSearchResult({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.pageNumber,
    required this.fullText,
    required this.matchStartIndex,
    required this.matchEndIndex,
  });

  String get snippet {
    const int contextRadius = 45;
    final start = (matchStartIndex - contextRadius).clamp(0, fullText.length);
    final end = (matchEndIndex + contextRadius).clamp(0, fullText.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < fullText.length ? '...' : '';
    return '$prefix${fullText.substring(start, end).replaceAll('\n', ' ')}$suffix';
  }
}

class BookSearchDialog extends StatefulWidget {
  final BookDocument document;
  final ReadingThemeType theme;
  final Function(int chapterIndex, int pageNumber) onNavigateToResult;

  const BookSearchDialog({
    super.key,
    required this.document,
    required this.theme,
    required this.onNavigateToResult,
  });

  @override
  State<BookSearchDialog> createState() => _BookSearchDialogState();
}

class _BookSearchDialogState extends State<BookSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<BookSearchResult> _results = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final List<BookSearchResult> found = [];
    final chapters = widget.document.chapters;

    for (int chIdx = 0; chIdx < chapters.length; chIdx++) {
      final ch = chapters[chIdx];
      for (final block in ch.blocks) {
        if (block.type == BlockType.image) continue;
        final text = block.text;
        final lowerText = text.toLowerCase();

        int startIndex = 0;
        while (startIndex < lowerText.length) {
          final idx = lowerText.indexOf(q, startIndex);
          if (idx == -1) break;

          found.add(BookSearchResult(
            chapterIndex: chIdx,
            chapterTitle: ch.title,
            pageNumber: block.originalPageNumber,
            fullText: text,
            matchStartIndex: idx,
            matchEndIndex: idx + q.length,
          ));

          startIndex = idx + q.length;
          if (found.length >= 100) break; // Limit to 100 top matches for blazing performance
        }
        if (found.length >= 100) break;
      }
      if (found.length >= 100) break;
    }

    setState(() {
      _results = found;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.isDark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: 580,
            height: 640,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E22).withAlpha(240)
                  : const Color(0xFFF9F9FB).withAlpha(245),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 90 : 30),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Top Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withAlpha(20)
                                : Colors.black.withAlpha(12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            style: TextStyle(
                              color: widget.theme.textColor,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Cari kata, karakter, atau kalimat...',
                              hintStyle: TextStyle(
                                color: widget.theme.secondaryTextColor.withAlpha(160),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: widget.theme.secondaryTextColor,
                                size: 20,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        color: widget.theme.secondaryTextColor,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        _performSearch('');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            onChanged: _performSearch,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: widget.theme.secondaryTextColor,
                          size: 22,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Search Results Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        _searchController.text.trim().length >= 2
                            ? '${_results.length} hasil ditemukan'
                            : 'Ketik minimal 2 karakter untuk mencari',
                        style: TextStyle(
                          color: widget.theme.secondaryTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (_isSearching)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                    ],
                  ),
                ),

                const Divider(height: 16),

                // Results List
                Expanded(
                  child: _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.find_in_page_outlined,
                                size: 48,
                                color: widget.theme.secondaryTextColor.withAlpha(100),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchController.text.trim().length >= 2
                                    ? 'Tidak ada hasil untuk "${_searchController.text.trim()}"'
                                    : 'Cari topik atau nama tokoh di buku ini',
                                style: TextStyle(
                                  color: widget.theme.secondaryTextColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _results.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                            color: isDark
                                ? Colors.white.withAlpha(10)
                                : Colors.black.withAlpha(10),
                          ),
                          itemBuilder: (context, index) {
                            final res = _results[index];
                            return InkWell(
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onNavigateToResult(
                                  res.chapterIndex,
                                  res.pageNumber,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD4AF37).withAlpha(30),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFFD4AF37).withAlpha(100),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            res.chapterTitle,
                                            style: const TextStyle(
                                              color: Color(0xFFE5C058),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          'Halaman ${res.pageNumber}',
                                          style: TextStyle(
                                            color: widget.theme.secondaryTextColor,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _buildHighlightedSnippet(
                                      res.snippet,
                                      _searchController.text.trim(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedSnippet(String snippet, String query) {
    if (query.isEmpty) {
      return Text(
        snippet,
        style: TextStyle(color: widget.theme.textColor, fontSize: 13, height: 1.4),
      );
    }

    final lowerSnippet = snippet.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final List<TextSpan> spans = [];

    int start = 0;
    while (start < snippet.length) {
      final index = lowerSnippet.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(
          text: snippet.substring(start),
          style: TextStyle(color: widget.theme.textColor, fontSize: 13, height: 1.4),
        ));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(
          text: snippet.substring(start, index),
          style: TextStyle(color: widget.theme.textColor, fontSize: 13, height: 1.4),
        ));
      }

      spans.add(TextSpan(
        text: snippet.substring(index, index + query.length),
        style: const TextStyle(
          color: Color(0xFF007AFF),
          backgroundColor: Color(0x33007AFF),
          fontWeight: FontWeight.bold,
          fontSize: 13,
          height: 1.4,
        ),
      ));

      start = index + query.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

