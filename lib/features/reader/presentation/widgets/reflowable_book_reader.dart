import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import '../../models/book_document.dart';

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
  final Function(int chapterIndex, int pageNumber, double percentage) onProgressChanged;
  final VoidCallback onTapContent;

  const ReflowableBookReader({
    super.key,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialChapterIndex = 0,
    this.initialPosition = 0,
    required this.onProgressChanged,
    required this.onTapContent,
  });

  @override
  State<ReflowableBookReader> createState() => _ReflowableBookReaderState();
}

class _ReflowableBookReaderState extends State<ReflowableBookReader> {
  late PageController _pageController;
  List<ReflowablePageContent> _pages = [];
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _paginateContent();
    _currentPageIndex = _calculateInitialPageIndex();
    _pageController = PageController(initialPage: _currentPageIndex);
  }

  @override
  void didUpdateWidget(covariant ReflowableBookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typography.fontSize != widget.typography.fontSize ||
        oldWidget.typography.lineSpacing != widget.typography.lineSpacing ||
        oldWidget.typography.horizontalMargin != widget.typography.horizontalMargin ||
        oldWidget.document != widget.document) {
      final currentFraction = _pages.isNotEmpty
          ? (_currentPageIndex / _pages.length)
          : 0.0;
      _paginateContent();
      _currentPageIndex = (_pages.length * currentFraction).round().clamp(0, _pages.isNotEmpty ? _pages.length - 1 : 0);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPageIndex);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _calculateInitialPageIndex() {
    if (_pages.isEmpty) return 0;
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
        _pageController.animateToPage(
          i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
    }
  }

  void jumpToPage(int pageNumber) {
    final target = (pageNumber - 1).clamp(0, _pages.length - 1);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _paginateContent() {
    final List<ReflowablePageContent> generated = [];
    final chapters = widget.document.chapters;

    // Approximate words per page based on font size and line spacing
    final int wordsPerPage = (260 * (18.0 / widget.typography.fontSize)).round().clamp(120, 500);

    int runningPageIndex = 0;

    for (int chIdx = 0; chIdx < chapters.length; chIdx++) {
      final chapter = chapters[chIdx];
      List<BookBlock> pageBlocks = [];
      int currentWordCount = 0;

      for (int blkIdx = 0; blkIdx < chapter.blocks.length; blkIdx++) {
        final block = chapter.blocks[blkIdx];
        final words = block.text.split(RegExp(r'\s+')).length;

        // If block is a major heading and page is not empty, start a new page
        if (block.type == BlockType.heading && pageBlocks.isNotEmpty) {
          generated.add(ReflowablePageContent(
            chapterIndex: chIdx,
            chapterTitle: chapter.title,
            blocks: List.from(pageBlocks),
            pageIndexInBook: runningPageIndex++,
            totalEstimatedPages: 0,
          ));
          pageBlocks.clear();
          currentWordCount = 0;
        }

        pageBlocks.add(block);
        currentWordCount += words;

        if (currentWordCount >= wordsPerPage) {
          generated.add(ReflowablePageContent(
            chapterIndex: chIdx,
            chapterTitle: chapter.title,
            blocks: List.from(pageBlocks),
            pageIndexInBook: runningPageIndex++,
            totalEstimatedPages: 0,
          ));
          pageBlocks.clear();
          currentWordCount = 0;
        }
      }

      // Trailing blocks of chapter
      if (pageBlocks.isNotEmpty) {
        generated.add(ReflowablePageContent(
          chapterIndex: chIdx,
          chapterTitle: chapter.title,
          blocks: List.from(pageBlocks),
          pageIndexInBook: runningPageIndex++,
          totalEstimatedPages: 0,
        ));
      }
    }

    if (generated.isEmpty) {
      generated.add(ReflowablePageContent(
        chapterIndex: 0,
        chapterTitle: widget.document.title,
        blocks: [
          BookBlock(
            id: 'default',
            type: BlockType.paragraph,
            text: 'No content available.',
          ),
        ],
        pageIndexInBook: 0,
        totalEstimatedPages: 1,
      ));
    }

    _pages = generated;
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return Center(
        child: Text(
          'Preparing pages...',
          style: TextStyle(color: widget.theme.secondaryTextColor),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopWide = constraints.maxWidth >= 900 && widget.typography.twoPageSpread;

        if (isDesktopWide) {
          return _buildTwoPageDesktopSpread(constraints);
        } else {
          return _buildSinglePageMobile(constraints);
        }
      },
    );
  }

  // --- 1. Desktop Two-Page Spread (Apple Books macOS Style) ---
  Widget _buildTwoPageDesktopSpread(BoxConstraints constraints) {
    // In two-page mode, each PageView slide shows 2 book pages (Left & Right)
    final int spreadCount = (_pages.length / 2).ceil();
    final int currentSpread = (_currentPageIndex / 2).floor().clamp(0, spreadCount - 1);

    return Container(
      color: widget.theme.backgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1300),
          child: PageView.builder(
            controller: PageController(initialPage: currentSpread),
            itemCount: spreadCount,
            onPageChanged: (spreadIndex) {
              final leftPageIdx = spreadIndex * 2;
              setState(() {
                _currentPageIndex = leftPageIdx;
              });
              final activePage = _pages[leftPageIdx];
              final progress = _pages.isNotEmpty
                  ? (leftPageIdx / _pages.length)
                  : 0.0;
              widget.onProgressChanged(
                activePage.chapterIndex,
                leftPageIdx + 1,
                progress,
              );
            },
            itemBuilder: (context, spreadIndex) {
              final leftIdx = spreadIndex * 2;
              final rightIdx = leftIdx + 1;
              final leftPage = leftIdx < _pages.length ? _pages[leftIdx] : null;
              final rightPage = rightIdx < _pages.length ? _pages[rightIdx] : null;

              return Row(
                children: [
                  // Left Page
                  Expanded(
                    child: leftPage != null
                        ? _buildBookPageView(leftPage, isLeftPage: true)
                        : const SizedBox(),
                  ),

                  // Center Spine Crease / Gutter Shadow
                  Container(
                    width: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withAlpha(widget.theme.isDark ? 80 : 25),
                          Colors.black.withAlpha(widget.theme.isDark ? 160 : 60),
                          Colors.black.withAlpha(widget.theme.isDark ? 80 : 25),
                        ],
                      ),
                    ),
                  ),

                  // Right Page
                  Expanded(
                    child: rightPage != null
                        ? _buildBookPageView(rightPage, isLeftPage: false)
                        : const SizedBox(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // --- 2. Mobile / Narrow Single-Page Reader ---
  Widget _buildSinglePageMobile(BoxConstraints constraints) {
    return Container(
      color: widget.theme.backgroundColor,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _pages.length,
        onPageChanged: (index) {
          setState(() {
            _currentPageIndex = index;
          });
          final activePage = _pages[index];
          final progress = _pages.isNotEmpty ? (index / _pages.length) : 0.0;
          widget.onProgressChanged(
            activePage.chapterIndex,
            index + 1,
            progress,
          );
        },
        itemBuilder: (context, index) {
          return _buildBookPageView(_pages[index], isLeftPage: null);
        },
      ),
    );
  }

  // --- Book Page View with Running Header and Footer ---
  Widget _buildBookPageView(ReflowablePageContent page, {bool? isLeftPage}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapContent,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.typography.horizontalMargin,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Running Header (Book title or chapter title)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                isLeftPage == true
                    ? widget.document.title.toUpperCase()
                    : page.chapterTitle.toUpperCase(),
                textAlign: isLeftPage == true
                    ? TextAlign.left
                    : (isLeftPage == false ? TextAlign.right : TextAlign.center),
                style: TextStyle(
                  color: widget.theme.secondaryTextColor.withAlpha(150),
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Main Text Content
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: page.blocks.map((b) => _renderBlock(b)).toList(),
                ),
              ),
            ),

            // Running Footer (Page Number)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${page.pageIndexInBook + 1}',
                textAlign: isLeftPage == true
                    ? TextAlign.left
                    : (isLeftPage == false ? TextAlign.right : TextAlign.center),
                style: TextStyle(
                  color: widget.theme.secondaryTextColor.withAlpha(160),
                  fontSize: 11,
                  fontFamily: 'serif',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderBlock(BookBlock block) {
    if (block.type == BlockType.heading) {
      final isH1 = block.headingLevel == 1;
      return Padding(
        padding: EdgeInsets.only(
          top: isH1 ? 18.0 : 12.0,
          bottom: 12.0,
        ),
        child: Text(
          block.text,
          textAlign: TextAlign.center,
          style: widget.typography.fontFamily.getTextStyle(
            fontSize: isH1
                ? widget.typography.fontSize * 1.45
                : widget.typography.fontSize * 1.2,
            fontWeight: FontWeight.bold,
            color: widget.theme.textColor,
            height: 1.25,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // Paragraph
    return Padding(
      padding: EdgeInsets.only(
        bottom: widget.typography.fontSize * 0.7,
      ),
      child: Text(
        block.text,
        textAlign: widget.typography.textAlign,
        style: widget.typography.fontFamily.getTextStyle(
          fontSize: widget.typography.fontSize,
          fontWeight: widget.typography.fontWeight,
          color: widget.theme.textColor,
          height: widget.typography.lineSpacing,
          letterSpacing: widget.typography.letterSpacing,
        ),
      ),
    );
  }
}

