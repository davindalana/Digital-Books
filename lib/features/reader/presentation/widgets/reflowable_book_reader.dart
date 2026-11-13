import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/theme/typography_settings.dart';
import '../../domain/models/book_document.dart';
import 'book_page_turn_view.dart';

class ReflowablePageContent {
  final int chapterIndex;
  final String chapterTitle;
  final List<BookBlock> blocks;
  final int pageIndexInBook;
  final int totalEstimatedPages;

  const ReflowablePageContent({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.blocks,
    required this.pageIndexInBook,
    required this.totalEstimatedPages,
  });
}

class ReflowableBookReader extends StatefulWidget {
  final BookDocument document;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final int initialChapterIndex;
  final int initialPosition;
  final Function(int chapterIndex, int pageNumber, double percentage)
  onProgressChanged;
  final void Function(int totalPages)? onTotalPagesCalculated;
  final VoidCallback onTapContent;
  final VoidCallback? onSwitchToPdfMode;
  final Function(String text, String color, int pageNumber)? onHighlightCreated;

  const ReflowableBookReader({
    super.key,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialChapterIndex = 0,
    this.initialPosition = 0,
    required this.onProgressChanged,
    this.onTotalPagesCalculated,
    required this.onTapContent,
    this.onSwitchToPdfMode,
    this.onHighlightCreated,
  });

  @override
  State<ReflowableBookReader> createState() => ReflowableBookReaderState();
}

class ReflowableBookReaderState extends State<ReflowableBookReader> {
  final GlobalKey<BookPageTurnViewState> _turnKey =
      GlobalKey<BookPageTurnViewState>();
  List<ReflowablePageContent> _pages = [];
  int _currentPageIndex = 0;

  int get totalPages => _pages.length;

  double _lastWidth = 0;
  double _lastHeight = 0;
  final Map<int, int> _chapterFirstPageMap = {};

  @override
  void initState() {
    super.initState();
    _currentPageIndex = 0;
  }

  @override
  void didUpdateWidget(covariant ReflowableBookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typography.fontSize != widget.typography.fontSize ||
        oldWidget.typography.lineSpacing != widget.typography.lineSpacing ||
        oldWidget.typography.horizontalMargin !=
            widget.typography.horizontalMargin ||
        oldWidget.typography.twoPageSpread != widget.typography.twoPageSpread ||
        oldWidget.document != widget.document) {
      if (_lastWidth > 0 && _lastHeight > 0) {
        _recomputePagination(_lastWidth, _lastHeight);
      }
    }
  }

  int _calculateInitialPageIndex() {
    if (_pages.isEmpty) return 0;
    if (widget.initialPosition > 0 && widget.initialPosition <= _pages.length) {
      return widget.initialPosition - 1;
    }
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].chapterIndex == widget.initialChapterIndex) {
        return i;
      }
    }
    return 0;
  }

  void jumpToChapter(int chapterIndex) {
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].chapterIndex == chapterIndex) {
        jumpToPage(i + 1);
        return;
      }
    }
  }

  void jumpToPage(int pageNumber) {
    final target = (pageNumber - 1).clamp(
      0,
      _pages.isNotEmpty ? _pages.length - 1 : 0,
    );
    _currentPageIndex = target;
    _turnKey.currentState?.jumpTo(target);
  }

  void nextPage() {
    _turnKey.currentState?.flipForward();
  }

  void previousPage() {
    _turnKey.currentState?.flipBackward();
  }

  void _recomputePagination(double width, double height) {
    final currentFraction = _pages.isNotEmpty
        ? (_currentPageIndex / _pages.length)
        : 0.0;

    _lastWidth = width;
    _lastHeight = height;
    _paginateContent(width, height);

    _currentPageIndex = (_pages.length * currentFraction).round().clamp(
      0,
      _pages.isNotEmpty ? _pages.length - 1 : 0,
    );
    _turnKey.currentState?.jumpTo(_currentPageIndex);
  }

  void _paginateContent(double width, double height) {
    final List<ReflowablePageContent> generated = [];
    final chapters = widget.document.chapters;
    _chapterFirstPageMap.clear();

    final isTwoPageSpread = width >= 850 && widget.typography.twoPageSpread;
    final double rawPageWidth = isTwoPageSpread ? ((width - 32) / 2) : width;
    final double effectiveMargin = (rawPageWidth < 400)
        ? 16.0
        : (rawPageWidth < 650 ? 22.0 : widget.typography.horizontalMargin);
    final double contentWidth = (rawPageWidth - (effectiveMargin * 2)).clamp(
      180.0,
      1200.0,
    );

    // Height budget:
    // Vertical container padding (40px) + Running header (30px) + Running footer (28px) + Safety buffer (30px)
    final double availableHeight = (height - 128.0).clamp(160.0, 3000.0);
    final double lineHeight =
        widget.typography.fontSize * widget.typography.lineSpacing;

    // Conservative line budget: subtract 3 lines so text NEVER touches or clips at the bottom
    final int maxLinesPerPage = math.max(
      4,
      (availableHeight / lineHeight).floor() - 3,
    );
    final int charsPerLine = math.max(
      20,
      (contentWidth / (widget.typography.fontSize * 0.60)).floor(),
    );

    int runningPageIndex = 0;

    for (int chIdx = 0; chIdx < chapters.length; chIdx++) {
      final chapter = chapters[chIdx];
      _chapterFirstPageMap[chIdx] = runningPageIndex;

      List<BookBlock> pageBlocks = [];
      int currentLinesUsed = 0;

      void pushPage() {
        if (pageBlocks.isNotEmpty) {
          generated.add(
            ReflowablePageContent(
              chapterIndex: chIdx,
              chapterTitle: chapter.title,
              blocks: List.from(pageBlocks),
              pageIndexInBook: runningPageIndex++,
              totalEstimatedPages: 0,
            ),
          );
          pageBlocks.clear();
          currentLinesUsed = 0;
        }
      }

      for (int blkIdx = 0; blkIdx < chapter.blocks.length; blkIdx++) {
        final block = chapter.blocks[blkIdx];
        final text = block.text.trim();
        if (block.type == BlockType.paragraph && text.isEmpty) continue;

        int lines = 1;
        if (block.type == BlockType.image) {
          lines = 13;
        } else if (block.type == BlockType.heading ||
            block.type == BlockType.documentTitle) {
          lines = 4;
        } else if (block.type == BlockType.sectionHeading) {
          lines = 3;
        } else if (block.type == BlockType.quote) {
          lines = math.max(1, (text.length / (charsPerLine * 0.85)).ceil()) + 2;
        } else if (block.type == BlockType.copyrightBlock ||
            block.type == BlockType.metadataBlock) {
          lines = math.max(1, (text.length / (charsPerLine * 0.90)).ceil()) + 3;
        } else if (block.type == BlockType.orderedList ||
            block.type == BlockType.unorderedList ||
            block.type == BlockType.listItem) {
          lines = math.max(1, (text.length / (charsPerLine * 0.88)).ceil()) + 1;
        } else if (block.type == BlockType.caption ||
            block.type == BlockType.footnote) {
          lines = math.max(1, (text.length / (charsPerLine * 0.90)).ceil()) + 1;
        } else {
          // Paragraph: calculate lines with word wrap buffer + paragraph margin
          lines = math.max(1, (text.length / charsPerLine).ceil()) + 1;
        }

        if (currentLinesUsed + lines <= maxLinesPerPage) {
          pageBlocks.add(block);
          currentLinesUsed += lines;
        } else {
          if (pageBlocks.isNotEmpty) {
            pushPage();
          }

          if (lines <= maxLinesPerPage) {
            pageBlocks.add(block);
            currentLinesUsed += lines;
          } else {
            // Block is longer than an entire slide: split cleanly
            _splitAndDistributeParagraph(
              block: block,
              charsPerLine: charsPerLine,
              maxLinesPerPage: maxLinesPerPage,
              onAddChunk: (chunkBlock, chunkLines) {
                if (currentLinesUsed + chunkLines > maxLinesPerPage &&
                    pageBlocks.isNotEmpty) {
                  pushPage();
                }
                pageBlocks.add(chunkBlock);
                currentLinesUsed += chunkLines;
              },
            );
          }
        }
      }

      pushPage();
    }

    if (generated.isEmpty) {
      generated.add(
        ReflowablePageContent(
          chapterIndex: 0,
          chapterTitle: widget.document.title,
          blocks: [
            BookBlock(
              id: 'default',
              type: BlockType.paragraph,
              text: 'No content to display.',
            ),
          ],
          pageIndexInBook: 0,
          totalEstimatedPages: 1,
        ),
      );
    }

    _pages = generated;
    if (widget.onTotalPagesCalculated != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onTotalPagesCalculated!(_pages.length);
        }
      });
    }
  }

  void _splitAndDistributeParagraph({
    required BookBlock block,
    required int charsPerLine,
    required int maxLinesPerPage,
    required void Function(BookBlock chunkBlock, int chunkLines) onAddChunk,
  }) {
    final text = block.text;
    final int maxCharsPerSlide = (maxLinesPerPage - 1) * charsPerLine;

    int startIndex = 0;
    while (startIndex < text.length) {
      int endIndex = math.min(startIndex + maxCharsPerSlide, text.length);

      if (endIndex < text.length) {
        final searchStart = startIndex + (maxCharsPerSlide ~/ 2);
        final candidateSlice = text.substring(searchStart, endIndex);

        // Try breaking at sentence end (. ! ? ")
        final sentenceBreak = candidateSlice.lastIndexOf(RegExp(r'[.!?"]\s'));
        if (sentenceBreak != -1) {
          endIndex = searchStart + sentenceBreak + 1;
        } else {
          // Break at word space
          final spaceBreak = candidateSlice.lastIndexOf(' ');
          if (spaceBreak != -1) {
            endIndex = searchStart + spaceBreak;
          }
        }
      }

      final chunkText = text.substring(startIndex, endIndex).trim();
      final chunkLines =
          math.max(1, (chunkText.length / charsPerLine).ceil()) + 1;

      onAddChunk(
        BookBlock(
          id: '${block.id}_$startIndex',
          type: BlockType.paragraph,
          text: chunkText,
          originalPageNumber: block.originalPageNumber,
        ),
        chunkLines,
      );

      startIndex = endIndex;
      while (startIndex < text.length && text[startIndex] == ' ') {
        startIndex++;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.document.chapters.any((c) => c.blocks.isNotEmpty);
    if (!hasContent) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: widget.theme.isDark
                ? const Color(0xFF1E1E22)
                : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.theme.isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(widget.theme.isDark ? 90 : 25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories,
                  size: 30,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Scanned Document',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.theme.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This book contains original visuals, diagrams, or images. Switch to Original PDF mode to preserve the full layout and image quality.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: widget.theme.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 22),
              if (widget.onSwitchToPdfMode != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text(
                    'Open in Original PDF Mode',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  onPressed: widget.onSwitchToPdfMode,
                ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Recalculate dynamic pagination if size changed significantly
        if ((w - _lastWidth).abs() > 10 ||
            (h - _lastHeight).abs() > 10 ||
            _pages.isEmpty) {
          final previousRatio = _pages.isNotEmpty
              ? (_currentPageIndex / _pages.length)
              : 0.0;
          _lastWidth = w;
          _lastHeight = h;
          _paginateContent(w, h);
          if (_currentPageIndex == 0) {
            _currentPageIndex = _calculateInitialPageIndex();
          } else {
            _currentPageIndex = (_pages.length * previousRatio).round().clamp(
              0,
              math.max(0, _pages.length - 1),
            );
          }
        }

        final isDesktopWide = w >= 850 && widget.typography.twoPageSpread;
        if (isDesktopWide && _currentPageIndex % 2 != 0) {
          _currentPageIndex = math.max(0, _currentPageIndex - 1);
        }

        return Stack(
          children: [
            BookPageTurnView(
              key: _turnKey,
              pages: _pages,
              initialPageIndex: _currentPageIndex,
              isTwoPageSpread: isDesktopWide,
              theme: widget.theme,
              typography: widget.typography,
              onPageChanged: (newIndex) {
                setState(() {
                  _currentPageIndex = newIndex;
                });
                if (newIndex < _pages.length) {
                  final activePage = _pages[newIndex];
                  final progress = _pages.isNotEmpty
                      ? (newIndex / _pages.length)
                      : 0.0;
                  widget.onProgressChanged(
                    activePage.chapterIndex,
                    newIndex + 1,
                    progress,
                  );
                }
              },
              onTapCenter: widget.onTapContent,
              pageBuilder: (page, {isLeftPage}) =>
                  _buildBookPageView(page, isLeftPage: isLeftPage),
            ),

            // Subtle Floating Previous Arrow on desktop/tablet
            if (_currentPageIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _FloatingReaderArrow(
                    icon: Icons.chevron_left,
                    isDark: widget.theme.isDark,
                    onPressed: previousPage,
                  ),
                ),
              ),

            // Subtle Floating Next Arrow on desktop/tablet
            if (_currentPageIndex < _pages.length - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _FloatingReaderArrow(
                    icon: Icons.chevron_right,
                    isDark: widget.theme.isDark,
                    onPressed: nextPage,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // --- Book Page View with Running Header and Footer ---
  Widget _buildBookPageView(ReflowablePageContent page, {bool? isLeftPage}) {
    final firstPageOfChapter = _chapterFirstPageMap[page.chapterIndex] ?? 0;
    final isFirstPageOfChapter = page.pageIndexInBook == firstPageOfChapter;

    final double rawPageWidth =
        (_lastWidth >= 850 && widget.typography.twoPageSpread)
        ? ((_lastWidth - 32) / 2)
        : (_lastWidth > 0 ? _lastWidth : 600);
    final double effectiveMargin = (rawPageWidth < 400)
        ? 16.0
        : (rawPageWidth < 650 ? 22.0 : widget.typography.horizontalMargin);

    return Container(
      color: widget.theme.backgroundColor,
      padding: EdgeInsets.symmetric(horizontal: effectiveMargin, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Running Header (Book title or chapter title)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              isLeftPage == true
                  ? widget.document.title.toUpperCase()
                  : page.chapterTitle.toUpperCase(),
              textAlign: isLeftPage == true
                  ? TextAlign.left
                  : (isLeftPage == false ? TextAlign.right : TextAlign.center),
              style: TextStyle(
                color: widget.theme.secondaryTextColor.withAlpha(140),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Main Text Content: Fits cleanly without cut off
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < page.blocks.length; i++)
                    _renderBlock(
                      page.blocks[i],
                      isFirstParagraphOfChapter:
                          isFirstPageOfChapter &&
                          i == 0 &&
                          page.blocks[i].type == BlockType.paragraph,
                    ),
                ],
              ),
            ),
          ),

          // Running Footer (Page Number)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${page.pageIndexInBook + 1}',
              textAlign: isLeftPage == true
                  ? TextAlign.left
                  : (isLeftPage == false ? TextAlign.right : TextAlign.center),
              style: TextStyle(
                color: widget.theme.secondaryTextColor.withAlpha(150),
                fontSize: 11,
                fontFamily: 'serif',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderBlock(
    BookBlock block, {
    bool isFirstParagraphOfChapter = false,
  }) {
    // 1. Image Block with Interactive Lightbox
    if (block.type == BlockType.image) {
      final file = block.imagePath != null ? File(block.imagePath!) : null;
      if (file == null || !file.existsSync()) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Center(
          child: GestureDetector(
            onTap: () => _openImageLightbox(context, file, block.text),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.theme.isDark
                      ? Colors.white.withAlpha(35)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(
                      widget.theme.isDark ? 130 : 35,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Image.file(file, fit: BoxFit.contain),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(180),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(40)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Zoom',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (block.text.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(200),
                            ],
                          ),
                        ),
                        child: Text(
                          block.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 2. Heading Block (Chapter / Law Header)
    if (block.type == BlockType.heading) {
      final text = block.text.trim();
      final hukumMatch = RegExp(
        r'^(hukum\s+\d+|chapter\s+\d+|bab\s+\d+)(:|\s-|\s–)?\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(text);

      String badgeText = '';
      String titleText = text;

      if (hukumMatch != null) {
        badgeText = hukumMatch.group(1) ?? '';
        titleText = hukumMatch.group(3) ?? text;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0),
        child: Column(
          children: [
            if (badgeText.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withAlpha(25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withAlpha(120),
                    width: 1,
                  ),
                ),
                child: Text(
                  '✦  ${badgeText.toUpperCase()}  ✦',
                  style: const TextStyle(
                    color: Color(0xFFE5C058),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: widget.typography.fontFamily.getTextStyle(
                fontSize: widget.typography.fontSize * 1.32,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
                height: 1.25,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: widget.theme.secondaryTextColor.withAlpha(35),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '❖',
                    style: TextStyle(
                      color: const Color(0xFFD4AF37).withAlpha(160),
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: widget.theme.secondaryTextColor.withAlpha(35),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 3. Quote Block
    if (block.type == BlockType.quote) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.theme.isDark
              ? const Color(0xFF141416)
              : const Color(0xFFF7F5F0),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: const BorderSide(color: Color(0xFFD4AF37), width: 3.5),
            top: BorderSide(
              color: widget.theme.isDark
                  ? Colors.white.withAlpha(15)
                  : Colors.black.withAlpha(10),
            ),
            right: BorderSide(
              color: widget.theme.isDark
                  ? Colors.white.withAlpha(15)
                  : Colors.black.withAlpha(10),
            ),
            bottom: BorderSide(
              color: widget.theme.isDark
                  ? Colors.white.withAlpha(15)
                  : Colors.black.withAlpha(10),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(widget.theme.isDark ? 50 : 12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '“ ',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 24,
                fontFamily: 'serif',
                height: 1.0,
              ),
            ),
            Expanded(
              child: Text(
                block.text,
                textAlign: widget.typography.textAlign,
                style: widget.typography.fontFamily
                    .getTextStyle(
                      fontSize: widget.typography.fontSize * 0.95,
                      fontWeight: FontWeight.normal,
                      color: widget.theme.textColor.withAlpha(235),
                      height: 1.6,
                      letterSpacing: 0.2,
                    )
                    .copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      );
    }

    // 4. Document Title Block
    if (block.type == BlockType.documentTitle) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Column(
          children: [
            Text(
              block.text.trim(),
              textAlign: TextAlign.center,
              style: widget.typography.fontFamily.getTextStyle(
                fontSize: widget.typography.fontSize * 1.5,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
                height: 1.25,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 50,
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );
    }

    // 5. Section Heading Block (H2 / Subheadings)
    if (block.type == BlockType.sectionHeading) {
      return Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3.5,
              height: widget.typography.fontSize * 1.15,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Text(
                block.text.trim(),
                style: widget.typography.fontFamily.getTextStyle(
                  fontSize: widget.typography.fontSize * 1.15,
                  fontWeight: FontWeight.w700,
                  color: widget.theme.textColor,
                  height: 1.3,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 6. Ordered List Item Block
    if (block.type == BlockType.orderedList ||
        block.type == BlockType.listItem) {
      final itemText = block.text.trim();
      final match = RegExp(
        r'^(\d+[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]+\))\s*(.*)$',
        dotAll: true,
      ).firstMatch(itemText);
      final marker = match?.group(1) ?? '•';
      final content = match?.group(2) ?? itemText;

      return Padding(
        padding: EdgeInsets.only(
          left: 12.0,
          right: 8.0,
          bottom: widget.typography.fontSize * 0.45,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 28),
              margin: const EdgeInsets.only(right: 8, top: 1),
              child: Text(
                marker,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4AF37),
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                content,
                textAlign: widget.typography.textAlign,
                style: widget.typography.fontFamily.getTextStyle(
                  fontSize: widget.typography.fontSize,
                  fontWeight: widget.typography.fontWeight,
                  color: widget.theme.textColor,
                  height: widget.typography.lineSpacing,
                  letterSpacing: widget.typography.letterSpacing,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 7. Unordered List Item Block
    if (block.type == BlockType.unorderedList) {
      final itemText = block.text.trim();
      final match = RegExp(
        r'^([•\-\*–—]|[\u2022\u2023\u25E6\u2043\u2219])\s*(.*)$',
        dotAll: true,
      ).firstMatch(itemText);
      final content = match?.group(2) ?? itemText;

      return Padding(
        padding: EdgeInsets.only(
          left: 14.0,
          right: 8.0,
          bottom: widget.typography.fontSize * 0.45,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10.0, top: 7.0),
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFD4AF37),
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                content,
                textAlign: widget.typography.textAlign,
                style: widget.typography.fontFamily.getTextStyle(
                  fontSize: widget.typography.fontSize,
                  fontWeight: widget.typography.fontWeight,
                  color: widget.theme.textColor,
                  height: widget.typography.lineSpacing,
                  letterSpacing: widget.typography.letterSpacing,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 8. Copyright & Publishing Metadata Block
    if (block.type == BlockType.copyrightBlock ||
        block.type == BlockType.metadataBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: widget.theme.isDark
              ? Colors.white.withAlpha(8)
              : Colors.black.withAlpha(6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.theme.secondaryTextColor.withAlpha(35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: widget.theme.secondaryTextColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'INFORMASI PENERBITAN & HAK CIPTA',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: widget.theme.secondaryTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              block.text.trim(),
              style: widget.typography.fontFamily.getTextStyle(
                fontSize: widget.typography.fontSize * 0.85,
                fontWeight: FontWeight.normal,
                height: 1.5,
                color: widget.theme.secondaryTextColor.withAlpha(220),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    }

    // 9. Caption Block
    if (block.type == BlockType.caption) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 13,
              color: widget.theme.secondaryTextColor.withAlpha(160),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                block.text.trim(),
                textAlign: TextAlign.center,
                style: widget.typography.fontFamily
                    .getTextStyle(
                      fontSize: widget.typography.fontSize * 0.88,
                      fontWeight: FontWeight.normal,
                      height: 1.4,
                      color: widget.theme.secondaryTextColor,
                      letterSpacing: 0.2,
                    )
                    .copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      );
    }

    // 10. Footnote Block
    if (block.type == BlockType.footnote) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(
              color: widget.theme.secondaryTextColor.withAlpha(40),
              thickness: 0.8,
            ),
            const SizedBox(height: 4),
            SelectableText(
              block.text.trim(),
              style: widget.typography.fontFamily.getTextStyle(
                fontSize: widget.typography.fontSize * 0.82,
                fontWeight: FontWeight.normal,
                height: 1.4,
                color: widget.theme.secondaryTextColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    }

    // 11. Regular Paragraph / Standalone Line Block
    final text = block.text;

    // Check if line is a standalone title / subtitle / disclaimer header that should be centered
    final isShortCentered =
        (text.length <= 50 &&
            !text.endsWith('.') &&
            !text.endsWith(',') &&
            !text.startsWith('(') &&
            !text.startsWith('"') &&
            !text.startsWith('“') &&
            !text.startsWith('-')) ||
        (text.length <= 60 &&
            (text == text.toUpperCase() ||
                text.startsWith('Sanksi') ||
                text.startsWith('Undang-undang') ||
                text.startsWith('tentang ')));

    if (isShortCentered) {
      return Padding(
        padding: EdgeInsets.only(bottom: widget.typography.fontSize * 0.7),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: widget.typography.fontFamily.getTextStyle(
            fontSize: widget.typography.fontSize * 1.05,
            fontWeight: FontWeight.w600,
            color: widget.theme.textColor,
            height: 1.4,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // Drop Cap: ONLY for genuine opening paragraphs (> 100 chars, begins with valid word of >= 3 letters containing vowels)
    final words = text.split(RegExp(r'\s+'));
    final firstWord = words.isNotEmpty
        ? words.first.replaceAll(RegExp(r'[^a-zA-Z]'), '')
        : '';
    final hasRealWord =
        firstWord.length >= 3 && RegExp(r'[aeiouyAEIOUY]').hasMatch(firstWord);

    final canHaveDropCap =
        isFirstParagraphOfChapter &&
        text.length > 100 &&
        hasRealWord &&
        RegExp(r'^[A-Za-z]').hasMatch(text) &&
        !text.startsWith('"') &&
        !text.startsWith('“') &&
        !text.startsWith('-') &&
        !text.startsWith('(');

    if (canHaveDropCap) {
      final firstLetter = text[0];
      final remaining = text.substring(1);

      return Padding(
        padding: EdgeInsets.only(bottom: widget.typography.fontSize * 0.7),
        child: RichText(
          textAlign: widget.typography.textAlign,
          text: TextSpan(
            children: [
              TextSpan(
                text: firstLetter,
                style: widget.typography.fontFamily.getTextStyle(
                  fontSize: widget.typography.fontSize * 2.2,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE5C058),
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              TextSpan(
                text: remaining,
                style: widget.typography.fontFamily.getTextStyle(
                  fontSize: widget.typography.fontSize,
                  fontWeight: widget.typography.fontWeight,
                  color: widget.theme.textColor,
                  height: widget.typography.lineSpacing,
                  letterSpacing: widget.typography.letterSpacing,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Clean justified continuous narrative text with interactive highlighting
    return Padding(
      padding: EdgeInsets.only(bottom: widget.typography.fontSize * 0.7),
      child: SelectableText(
        text,
        textAlign: widget.typography.textAlign,
        style: widget.typography.fontFamily.getTextStyle(
          fontSize: widget.typography.fontSize,
          fontWeight: widget.typography.fontWeight,
          color: widget.theme.textColor,
          height: widget.typography.lineSpacing,
          letterSpacing: widget.typography.letterSpacing,
        ),
        contextMenuBuilder: (context, editableTextState) {
          final buttonItems = editableTextState.contextMenuButtonItems;
          if (widget.onHighlightCreated != null) {
            buttonItems.insert(
              0,
              ContextMenuButtonItem(
                label: '✦ Sorot Emas',
                onPressed: () {
                  final sel = editableTextState.textEditingValue.selection;
                  final selectedText = sel.textInside(text).trim();
                  editableTextState.hideToolbar();
                  if (selectedText.isNotEmpty) {
                    widget.onHighlightCreated!(
                      selectedText,
                      'gold',
                      block.originalPageNumber,
                    );
                  }
                },
              ),
            );
            buttonItems.insert(
              1,
              ContextMenuButtonItem(
                label: '✦ Sorot Kuning',
                onPressed: () {
                  final sel = editableTextState.textEditingValue.selection;
                  final selectedText = sel.textInside(text).trim();
                  editableTextState.hideToolbar();
                  if (selectedText.isNotEmpty) {
                    widget.onHighlightCreated!(
                      selectedText,
                      'yellow',
                      block.originalPageNumber,
                    );
                  }
                },
              ),
            );
          }
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: buttonItems,
          );
        },
      ),
    );
  }

  void _openImageLightbox(BuildContext context, File file, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(220),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(file),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingReaderArrow extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;

  const _FloatingReaderArrow({
    required this.icon,
    required this.isDark,
    required this.onPressed,
  });

  @override
  State<_FloatingReaderArrow> createState() => _FloatingReaderArrowState();
}

class _FloatingReaderArrowState extends State<_FloatingReaderArrow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgAlpha = _isHovered
        ? (widget.isDark ? 210 : 190)
        : (widget.isDark ? 80 : 60);
    final borderAlpha = _isHovered ? 80 : 30;

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
                color: Colors.black.withAlpha(widget.isDark ? 60 : 20),
                blurRadius: 10,
                offset: const Offset(0, 3),
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
