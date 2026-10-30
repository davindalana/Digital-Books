import 'dart:ui';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/utils/file_storage_service.dart';
import '../../models/book_document.dart';
import '../../providers/reader_settings_provider.dart';
import '../widgets/appearance_sheet.dart';
import '../widgets/original_pdf_reader.dart';
import '../widgets/reflowable_book_reader.dart';
import '../widgets/toc_dialog.dart';

class ReadingScreen extends ConsumerStatefulWidget {
  final Book book;

  const ReadingScreen({super.key, required this.book});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  bool _showControls = true;
  BookDocument? _document;
  bool _isLoadingDoc = true;

  int _currentPage = 1;
  int _totalPages = 1;
  int _currentChapter = 0;
  double _progressPercentage = 0.0;

  final GlobalKey<State<ReflowableBookReader>> _reflowableKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadBookDocumentAndProgress();
  }

  Future<void> _loadBookDocumentAndProgress() async {
    // 1. Load progress
    final dbService = ref.read(databaseServiceProvider);
    final progress = await dbService.getProgress(widget.book.id);
    if (progress != null) {
      setState(() {
        _currentChapter = progress.currentChapter;
        _currentPage = progress.currentPosition > 0 ? progress.currentPosition : 1;
        _progressPercentage = progress.progressPercentage;
      });
    }

    // 2. Load processed book document if available
    if (widget.book.processedBookPath != null) {
      try {
        final jsonStr = await FileStorageService.readProcessedBook(widget.book.processedBookPath!);
        if (jsonStr != null) {
          _document = BookDocument.fromJsonString(jsonStr);
        }
      } catch (_) {}
    }

    // If document is empty or book is scanned, default to Original PDF mode if preferred
    if (widget.book.isScanned && _document == null) {
      ref.read(activeReadingModeProvider(widget.book.id).notifier).state =
          ReadingMode.originalPdf;
    }

    setState(() {
      _isLoadingDoc = false;
      _totalPages = widget.book.totalPages > 0 ? widget.book.totalPages : 1;
    });
  }

  void _saveProgress({
    required int chapter,
    required int position,
    required double percentage,
  }) {
    setState(() {
      _currentChapter = chapter;
      _currentPage = position;
      _progressPercentage = percentage;
    });

    final dbService = ref.read(databaseServiceProvider);
    dbService.upsertProgress(ReadingProgressesCompanion(
      id: drift.Value(const Uuid().v4()),
      bookId: drift.Value(widget.book.id),
      currentChapter: drift.Value(chapter),
      currentPosition: drift.Value(position),
      progressPercentage: drift.Value(percentage.clamp(0.0, 1.0)),
      lastReadAt: drift.Value(DateTime.now()),
    ));
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _openAppearanceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AppearanceSheet(),
    );
  }

  void _openTocDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (_) => TocDialog(
        bookId: widget.book.id,
        bookDocument: _document,
        onNavigateToChapter: (chIndex, pageNum) {
          _saveProgress(
            chapter: chIndex,
            position: pageNum,
            percentage: _totalPages > 0 ? (pageNum / _totalPages) : 0.0,
          );
        },
        onNavigateToPosition: (pos) {
          _saveProgress(
            chapter: _currentChapter,
            position: pos,
            percentage: _totalPages > 0 ? (pos / _totalPages) : 0.0,
          );
        },
      ),
    );
  }

  Future<void> _toggleBookmark() async {
    final dbService = ref.read(databaseServiceProvider);
    final bookmarks = await dbService.watchBookmarks(widget.book.id).first;
    final existing = bookmarks.where((b) => b.position == _currentPage);

    if (existing.isNotEmpty) {
      for (final b in existing) {
        await dbService.deleteBookmark(b.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bookmark removed'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      await dbService.addBookmark(BookmarksCompanion(
        id: drift.Value(const Uuid().v4()),
        bookId: drift.Value(widget.book.id),
        position: drift.Value(_currentPage),
        label: drift.Value('Page $_currentPage'),
        createdAt: drift.Value(DateTime.now()),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bookmarked page $_currentPage'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final typoSettings = ref.watch(typographySettingsStateProvider);
    final readingMode = ref.watch(activeReadingModeProvider(widget.book.id));
    final bookmarksAsync = ref.watch(bookBookmarksStreamProvider(widget.book.id));
    final isBookmarked = bookmarksAsync.value?.any((b) => b.position == _currentPage) ?? false;

    return Scaffold(
      backgroundColor: activeTheme.backgroundColor,
      body: Stack(
        children: [
          // 1. Reading Body Engine
          Positioned.fill(
            child: _isLoadingDoc
                ? Center(
                    child: CircularProgressIndicator(
                      color: activeTheme.textColor,
                    ),
                  )
                : (readingMode == ReadingMode.reflowable && _document != null)
                    ? ReflowableBookReader(
                        key: _reflowableKey,
                        document: _document!,
                        theme: activeTheme,
                        typography: typoSettings,
                        initialChapterIndex: _currentChapter,
                        initialPosition: _currentPage,
                        onTapContent: _toggleControls,
                        onProgressChanged: (ch, page, pct) {
                          _saveProgress(
                            chapter: ch,
                            position: page,
                            percentage: pct,
                          );
                        },
                      )
                    : OriginalPdfReader(
                        pdfPath: widget.book.originalPdfPath,
                        initialPage: _currentPage,
                        theme: activeTheme,
                        onPageChanged: (page, total) {
                          setState(() {
                            _totalPages = total;
                          });
                          _saveProgress(
                            chapter: 0,
                            position: page,
                            percentage: total > 0 ? (page / total) : 0.0,
                          );
                        },
                      ),
          ),

          // 2. Minimalist Floating Apple Books Top Toolbar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            top: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: _buildFloatingTopBar(activeTheme, readingMode, isBookmarked),
          ),

          // 3. Minimalist Floating Bottom Bar with Slider
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            bottom: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: _buildFloatingBottomBar(activeTheme),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTopBar(
    ReadingThemeType activeTheme,
    ReadingMode readingMode,
    bool isBookmarked,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: activeTheme.isDark
                    ? const Color(0xFF1E1E22).withAlpha(200)
                    : const Color(0xFFFFFFFF).withAlpha(210),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: activeTheme.isDark
                      ? Colors.white.withAlpha(25)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha( activeTheme.isDark ? 80 : 25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      color: activeTheme.textColor,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  // Book Title & Chapter subtitle
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          style: TextStyle(
                            color: activeTheme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.book.author,
                          style: TextStyle(
                            color: activeTheme.secondaryTextColor,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Mode Switcher: Reflowable vs PDF
                  Container(
                    height: 32,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: activeTheme.isDark
                          ? Colors.white.withAlpha(20)
                          : Colors.black.withAlpha(12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _ModePillButton(
                          label: 'Book',
                          isSelected: readingMode == ReadingMode.reflowable,
                          activeTheme: activeTheme,
                          onTap: () {
                            ref
                                .read(activeReadingModeProvider(widget.book.id).notifier)
                                .state = ReadingMode.reflowable;
                          },
                        ),
                        _ModePillButton(
                          label: 'PDF',
                          isSelected: readingMode == ReadingMode.originalPdf,
                          activeTheme: activeTheme,
                          onTap: () {
                            ref
                                .read(activeReadingModeProvider(widget.book.id).notifier)
                                .state = ReadingMode.originalPdf;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Table of Contents
                  IconButton(
                    icon: Icon(
                      Icons.list_alt,
                      color: activeTheme.textColor,
                      size: 20,
                    ),
                    onPressed: _openTocDialog,
                  ),

                  // Appearance Settings (aA)
                  IconButton(
                    icon: Text(
                      'aA',
                      style: TextStyle(
                        color: activeTheme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _openAppearanceSheet,
                  ),

                  // Bookmark button
                  IconButton(
                    icon: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked
                          ? const Color(0xFF007AFF)
                          : activeTheme.textColor,
                      size: 20,
                    ),
                    onPressed: _toggleBookmark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomBar(ReadingThemeType activeTheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: activeTheme.isDark
                    ? const Color(0xFF1E1E22).withAlpha(200)
                    : const Color(0xFFFFFFFF).withAlpha(210),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: activeTheme.isDark
                      ? Colors.white.withAlpha(25)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(activeTheme.isDark ? 80 : 25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Page $_currentPage of $_totalPages',
                        style: TextStyle(
                          color: activeTheme.secondaryTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(_progressPercentage * 100).toInt()}%',
                        style: TextStyle(
                          color: activeTheme.textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFF007AFF),
                      inactiveTrackColor: activeTheme.isDark
                          ? Colors.white.withAlpha(30)
                          : Colors.black.withAlpha(20),
                      thumbColor: Colors.white,
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: _progressPercentage.clamp(0.0, 1.0),
                      onChanged: (val) {
                        final targetPage = (val * _totalPages).round().clamp(1, _totalPages);
                        _saveProgress(
                          chapter: _currentChapter,
                          position: targetPage,
                          percentage: val,
                        );
                      },
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
}

class _ModePillButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ReadingThemeType activeTheme;
  final VoidCallback onTap;

  const _ModePillButton({
    required this.label,
    required this.isSelected,
    required this.activeTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (activeTheme.isDark
                  ? Colors.white.withAlpha(45)
                  : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected && !activeTheme.isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? activeTheme.textColor
                : activeTheme.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}

