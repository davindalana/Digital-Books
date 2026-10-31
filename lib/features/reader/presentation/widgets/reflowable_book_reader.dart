import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import '../../models/book_document.dart';
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
  final VoidCallback onTapContent;
  final VoidCallback? onSwitchToPdfMode;

  const ReflowableBookReader({
    super.key,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialChapterIndex = 0,
    this.initialPosition = 0,
    required this.onProgressChanged,
    required this.onTapContent,
    this.onSwitchToPdfMode,
  });

  @override
  State<ReflowableBookReader> createState() => ReflowableBookReaderState();
}

class ReflowableBookReaderState extends State<ReflowableBookReader> {
  final GlobalKey<BookPageTurnViewState> _turnKey =
      GlobalKey<BookPageTurnViewState>();
  List<ReflowablePageContent> _pages = [];
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _paginateContent();
    _currentPageIndex = _calculateInitialPageIndex();
  }

  @override
  void didUpdateWidget(covariant ReflowableBookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typography.fontSize != widget.typography.fontSize ||
        oldWidget.typography.lineSpacing != widget.typography.lineSpacing ||
        oldWidget.typography.horizontalMargin !=
            widget.typography.horizontalMargin ||
        oldWidget.document != widget.document) {
      final currentFraction = _pages.isNotEmpty
          ? (_currentPageIndex / _pages.length)
          : 0.0;
      _paginateContent();
      _currentPageIndex = (_pages.length * currentFraction).round().clamp(
        0,
        _pages.isNotEmpty ? _pages.length - 1 : 0,
      );
      _turnKey.currentState?.jumpTo(_currentPageIndex);
    }
  }

  @override
  void dispose() {
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

  void _paginateContent() {
    final List<ReflowablePageContent> generated = [];
    final chapters = widget.document.chapters;

    // Approximate words per page based on font size and line spacing
    final int wordsPerPage = (260 * (18.0 / widget.typography.fontSize))
        .round()
        .clamp(120, 500);

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
          currentWordCount = 0;
        }

        pageBlocks.add(block);
        currentWordCount += words;

        if (currentWordCount >= wordsPerPage) {
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
          currentWordCount = 0;
        }
      }

      // Trailing blocks of chapter
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
      }
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
              text: 'No content available.',
            ),
          ],
          pageIndexInBook: 0,
          totalEstimatedPages: 1,
        ),
      );
    }

    _pages = generated;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.document.isScanned) {
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
                'Buku Dokumen Hasil Pindai',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.theme.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Buku ini berisi visual asli, denah, atau gambar. Beralih ke Mode PDF Asli untuk tata letak lengkap dan ketajaman visual terbaik seperti di Apple Books.',
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
                    'Buka dalam Mode PDF Asli',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  onPressed: widget.onSwitchToPdfMode,
                ),
            ],
          ),
        ),
      );
    }

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
        final isDesktopWide =
            constraints.maxWidth >= 900 && widget.typography.twoPageSpread;

        return BookPageTurnView(
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
        );
      },
    );
  }

  // --- Book Page View with Running Header and Footer ---
  Widget _buildBookPageView(ReflowablePageContent page, {bool? isLeftPage}) {
    return Container(
      color: widget.theme.backgroundColor,
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
                children: [
                  for (int i = 0; i < page.blocks.length; i++)
                    _renderBlock(
                      page.blocks[i],
                      isFirstParagraphOfChapter:
                          i == 0 && page.blocks[i].type == BlockType.paragraph,
                    ),
                ],
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
        padding: const EdgeInsets.symmetric(vertical: 14.0),
        child: Center(
          child: GestureDetector(
            onTap: () => _openImageLightbox(context, file, block.text),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.theme.isDark
                      ? Colors.white.withAlpha(35)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(
                      widget.theme.isDark ? 140 : 40,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Image.file(file, fit: BoxFit.contain),
                    Positioned(
                      top: 10,
                      right: 10,
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
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(210),
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
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Column(
          children: [
            if (badgeText.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 5,
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
                    letterSpacing: 2.2,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: widget.typography.fontFamily.getTextStyle(
                fontSize: widget.typography.fontSize * 1.35,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
                height: 1.3,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 14),
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
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
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
              color: Colors.black.withAlpha(widget.theme.isDark ? 60 : 15),
              blurRadius: 10,
              offset: const Offset(0, 3),
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
                fontSize: 26,
                fontFamily: 'serif',
                height: 1.0,
              ),
            ),
            Expanded(
              child: Text(
                block.text,
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

    // 4. Regular Paragraph (with Drop Cap if opening chapter)
    final text = block.text;
    if (isFirstParagraphOfChapter && text.length > 3) {
      final firstLetter = text[0];
      final remaining = text.substring(1);

      return Padding(
        padding: EdgeInsets.only(bottom: widget.typography.fontSize * 0.75),
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

    return Padding(
      padding: EdgeInsets.only(bottom: widget.typography.fontSize * 0.75),
      child: Text(
        text,
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
