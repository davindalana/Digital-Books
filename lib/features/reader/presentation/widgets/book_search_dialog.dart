import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../domain/engines/in_book_search_engine.dart';
import '../../domain/models/reader_content.dart';
import '../../domain/services/book_search_indexer.dart';
import '../../models/book_document.dart';

class BookSearchDialog extends StatefulWidget {
  final String? bookId;
  final String? pdfPath;
  final DatabaseService? dbService;
  final ReaderDocument? readerDocument;
  final BookDocument? document;
  final ReadingThemeType theme;
  final bool isOcrRunning;
  final Function(InBookSearchResult result) onNavigateToResult;

  const BookSearchDialog({
    super.key,
    this.bookId,
    this.pdfPath,
    this.dbService,
    this.readerDocument,
    this.document,
    required this.theme,
    this.isOcrRunning = false,
    required this.onNavigateToResult,
  });

  @override
  State<BookSearchDialog> createState() => _BookSearchDialogState();
}

class _BookSearchDialogState extends State<BookSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<InBookSearchResult> _results = [];
  bool _isSearching = false;
  bool _isIndexing = false;
  String _indexingProgressText = '';
  int _searchToken = 0;
  Timer? _debounceTimer;

  ReaderDocument? _effectiveDoc;

  @override
  void initState() {
    super.initState();
    _effectiveDoc =
        widget.readerDocument ??
        (widget.document != null
            ? ReaderDocument.fromBookDocument(widget.document!)
            : null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    _checkAndTriggerIndexing();
  }

  Future<void> _checkAndTriggerIndexing() async {
    if (widget.bookId == null ||
        widget.pdfPath == null ||
        widget.dbService == null) {
      return;
    }

    try {
      final count = await widget.dbService!.getIndexedSearchPageCount(
        widget.bookId!,
      );
      if (count == 0 && mounted) {
        setState(() {
          _isIndexing = true;
          _indexingProgressText = 'Preparing index…';
        });

        final indexer = BookSearchIndexer(dbService: widget.dbService!);
        await indexer.indexBook(
          bookId: widget.bookId!,
          pdfPath: widget.pdfPath!,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _indexingProgressText = '$current / $total hal';
              });
            }
          },
        );

        if (mounted) {
          setState(() {
            _isIndexing = false;
          });
          // Re-trigger search if query already typed
          if (_searchController.text.trim().length >= 2) {
            _executeSearch(_searchController.text.trim());
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isIndexing = false);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    final clean = query.trim();

    if (clean.length < 2) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _executeSearch(clean);
    });
  }

  Future<void> _executeSearch(String query) async {
    final currentToken = ++_searchToken;

    List<InBookSearchResult> found = const [];

    if (widget.bookId != null && widget.dbService != null) {
      found = await InBookSearchEngine.searchIndexedBook(
        bookId: widget.bookId!,
        dbService: widget.dbService!,
        query: query,
        readerDocument: _effectiveDoc,
        isCancelled: () => currentToken != _searchToken,
      );
    } else if (_effectiveDoc != null) {
      found = await InBookSearchEngine.search(
        document: _effectiveDoc!,
        query: query,
        isCancelled: () => currentToken != _searchToken,
      );
    }

    if (!mounted || currentToken != _searchToken) return;

    setState(() {
      _results = found;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.isDark;

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 580,
              height: 620,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E).withAlpha(235)
                    : Colors.white.withAlpha(240),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(25)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 100 : 40),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Search Input Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: const Color(0xFF007AFF),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            onChanged: _onQueryChanged,
                            style: TextStyle(
                              color: widget.theme.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Find a word or phrase in this book…',
                              hintStyle: TextStyle(
                                color: widget.theme.secondaryTextColor
                                    .withAlpha(140),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              color: widget.theme.secondaryTextColor,
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: widget.theme.secondaryTextColor,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // OCR or Indexing status pill
                  if (_isIndexing || widget.isOcrRunning)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 6,
                      ),
                      color: const Color(
                        0xFF007AFF,
                      ).withAlpha(isDark ? 30 : 20),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isIndexing
                                  ? 'Preparing search index ($_indexingProgressText)…'
                                  : 'OCR sedang berjalan di latar belakang. Hasil pencarian terus diperbarui.',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Divider with result count & loading spinner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    color: isDark
                        ? Colors.white.withAlpha(6)
                        : Colors.black.withAlpha(5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _searchController.text.trim().length < 2
                              ? 'Ketik minimal 2 karakter untuk mencari'
                              : (_isSearching
                                    ? 'Mencari...'
                                    : '${_results.length} hasil ditemukan'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: widget.theme.secondaryTextColor,
                          ),
                        ),
                        if (_isSearching)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),

                  // Result List
                  Expanded(child: _buildResultsView(isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsView(bool isDark) {
    if (_searchController.text.trim().length < 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 48,
              color: widget.theme.secondaryTextColor.withAlpha(100),
            ),
            const SizedBox(height: 10),
            Text(
              'Search across all chapters and pages',
              style: TextStyle(
                color: widget.theme.secondaryTextColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (!_isSearching && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 44,
              color: widget.theme.secondaryTextColor.withAlpha(120),
            ),
            const SizedBox(height: 10),
            Text(
              'No matching results',
              style: TextStyle(
                color: widget.theme.textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Periksa ejaan kata atau coba kata kunci lain',
              style: TextStyle(
                color: widget.theme.secondaryTextColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 18,
        endIndent: 18,
        color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(12),
      ),
      itemBuilder: (context, index) {
        final res = _results[index];

        return InkWell(
          onTap: () {
            Navigator.of(context).pop();
            widget.onNavigateToResult(res);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chapter & Page Badge Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF007AFF,
                        ).withAlpha(isDark ? 40 : 25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        res.chapterTitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ),
                    if (res.isOcr) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF34C759,
                          ).withAlpha(isDark ? 45 : 30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'OCR',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF34C759),
                          ),
                        ),
                      ),
                    ],
                    if (res.isCrossPage) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFF9500,
                          ).withAlpha(isDark ? 45 : 30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Next Page',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF9500),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'hal. ${res.sourcePdfPage}',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.theme.secondaryTextColor.withAlpha(160),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Snippet with highlighted search term
                _buildSnippetText(res, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSnippetText(InBookSearchResult res, bool isDark) {
    final query = _searchController.text.trim();
    final snippet = res.snippet;
    final lowerSnippet = snippet.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final children = <TextSpan>[];
    int cursor = 0;

    while (cursor < snippet.length) {
      final idx = lowerSnippet.indexOf(lowerQuery, cursor);
      if (idx == -1) {
        children.add(
          TextSpan(
            text: snippet.substring(cursor),
            style: TextStyle(
              color: widget.theme.textColor.withAlpha(220),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        );
        break;
      }

      if (idx > cursor) {
        children.add(
          TextSpan(
            text: snippet.substring(cursor, idx),
            style: TextStyle(
              color: widget.theme.textColor.withAlpha(220),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        );
      }

      final matchEnd = idx + query.length;
      children.add(
        TextSpan(
          text: snippet.substring(idx, matchEnd),
          style: TextStyle(
            color: isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
            backgroundColor: const Color(
              0xFFFF9500,
            ).withValues(alpha: isDark ? 0.35 : 0.25),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            height: 1.35,
          ),
        ),
      );

      cursor = matchEnd;
    }

    return Text.rich(
      TextSpan(children: children),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
