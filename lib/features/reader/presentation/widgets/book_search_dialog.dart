import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../domain/engines/in_book_search_engine.dart';
import '../../domain/models/reader_content.dart';
import '../../models/book_document.dart';

class BookSearchDialog extends StatefulWidget {
  final ReaderDocument? readerDocument;
  final BookDocument? document;
  final ReadingThemeType theme;
  final Function(InBookSearchResult result) onNavigateToResult;

  const BookSearchDialog({
    super.key,
    this.readerDocument,
    this.document,
    required this.theme,
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
    if (_effectiveDoc == null) {
      setState(() => _isSearching = false);
      return;
    }

    final currentToken = ++_searchToken;

    final found = await InBookSearchEngine.search(
      document: _effectiveDoc!,
      query: query,
      isCancelled: () => currentToken != _searchToken,
    );

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
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: 600,
              height: 650,
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
                  // Top Search Input Bar
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
                              onChanged: _onQueryChanged,
                              style: TextStyle(
                                color: widget.theme.textColor,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Cari kata, karakter, atau frasa...',
                                hintStyle: TextStyle(
                                  color: widget.theme.secondaryTextColor
                                      .withAlpha(160),
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
                                          color:
                                              widget.theme.secondaryTextColor,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          _onQueryChanged('');
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
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
              'Cari di seluruh bab dokumen',
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
              'Tidak ada hasil yang cocok',
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
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 18,
        endIndent: 18,
        color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(8),
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
                // Chapter & Page Badge
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
