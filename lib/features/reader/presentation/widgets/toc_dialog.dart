import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../models/book_document.dart';
import '../../providers/reader_settings_provider.dart';

class TocDialog extends ConsumerStatefulWidget {
  final String bookId;
  final BookDocument? bookDocument;
  final Function(int chapterIndex, int pageNumber) onNavigateToChapter;
  final Function(int position) onNavigateToPosition;

  const TocDialog({
    super.key,
    required this.bookId,
    required this.bookDocument,
    required this.onNavigateToChapter,
    required this.onNavigateToPosition,
  });

  @override
  ConsumerState<TocDialog> createState() => _TocDialogState();
}

class _TocDialogState extends ConsumerState<TocDialog> {
  int _selectedTab = 0; // 0: Contents, 1: Bookmarks, 2: Highlights

  @override
  Widget build(BuildContext context) {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final bookmarksAsync = ref.watch(bookBookmarksStreamProvider(widget.bookId));
    final highlightsAsync = ref.watch(bookHighlightsStreamProvider(widget.bookId));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: 540,
            height: 600,
            decoration: BoxDecoration(
              color: activeTheme.isDark
                  ? const Color(0xFF1E1E22).withAlpha(240)
                  : const Color(0xFFF9F9FB).withAlpha(245),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: activeTheme.isDark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(20),
              ),
            ),
            child: Column(
              children: [
                // Header with segmented tabs & close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
                  child: Row(
                    children: [
                      // Segmented Control
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: activeTheme.isDark
                                ? Colors.white.withAlpha(18)
                                : Colors.black.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              _TabItem(
                                title: 'Contents',
                                isSelected: _selectedTab == 0,
                                activeTheme: activeTheme,
                                onTap: () => setState(() => _selectedTab = 0),
                              ),
                              _TabItem(
                                title: 'Bookmarks',
                                isSelected: _selectedTab == 1,
                                activeTheme: activeTheme,
                                onTap: () => setState(() => _selectedTab = 1),
                              ),
                              _TabItem(
                                title: 'Notes',
                                isSelected: _selectedTab == 2,
                                activeTheme: activeTheme,
                                onTap: () => setState(() => _selectedTab = 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: activeTheme.secondaryTextColor,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: activeTheme.isDark
                      ? Colors.white.withAlpha(20)
                      : Colors.black.withAlpha(15),
                ),

                // Content View
                Expanded(
                  child: _selectedTab == 0
                      ? _buildChaptersList(activeTheme)
                      : _selectedTab == 1
                          ? _buildBookmarksList(bookmarksAsync, activeTheme)
                          : _buildHighlightsList(highlightsAsync, activeTheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChaptersList(ReadingThemeType activeTheme) {
    final chapters = widget.bookDocument?.chapters ?? [];
    if (chapters.isEmpty) {
      return Center(
        child: Text(
          'No chapters detected',
          style: TextStyle(color: activeTheme.secondaryTextColor),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chapters.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 20,
        endIndent: 20,
        color: activeTheme.isDark
            ? Colors.white.withAlpha(10)
            : Colors.black.withAlpha(10),
      ),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final firstBlock = chapter.blocks.isNotEmpty ? chapter.blocks.first : null;
        final pageNum = firstBlock?.originalPageNumber ?? (index + 1);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: Text(
            chapter.title,
            style: TextStyle(
              color: activeTheme.textColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Text(
            'p. $pageNum',
            style: TextStyle(
              color: activeTheme.secondaryTextColor,
              fontSize: 13,
            ),
          ),
          onTap: () {
            Navigator.of(context).pop();
            widget.onNavigateToChapter(index, pageNum);
          },
        );
      },
    );
  }

  Widget _buildBookmarksList(
    AsyncValue<List<Bookmark>> bookmarksAsync,
    ReadingThemeType activeTheme,
  ) {
    return bookmarksAsync.when(
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bookmark_border,
                  size: 40,
                  color: activeTheme.secondaryTextColor.withAlpha(120),
                ),
                const SizedBox(height: 12),
                Text(
                  'No bookmarks added yet',
                  style: TextStyle(color: activeTheme.secondaryTextColor),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: bookmarks.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: activeTheme.isDark
                ? Colors.white.withAlpha(10)
                : Colors.black.withAlpha(10),
          ),
          itemBuilder: (context, index) {
            final bm = bookmarks[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: const Icon(
                Icons.bookmark,
                color: Color(0xFF007AFF),
                size: 20,
              ),
              title: Text(
                bm.label,
                style: TextStyle(
                  color: activeTheme.textColor,
                  fontSize: 15,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: activeTheme.secondaryTextColor,
                onPressed: () {
                  ref.read(databaseServiceProvider).deleteBookmark(bm.id);
                },
              ),
              onTap: () {
                Navigator.of(context).pop();
                widget.onNavigateToPosition(bm.position);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error loading bookmarks',
          style: TextStyle(color: activeTheme.secondaryTextColor),
        ),
      ),
    );
  }

  Widget _buildHighlightsList(
    AsyncValue<List<Highlight>> highlightsAsync,
    ReadingThemeType activeTheme,
  ) {
    return highlightsAsync.when(
      data: (highlights) {
        if (highlights.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.border_color,
                  size: 40,
                  color: activeTheme.secondaryTextColor.withAlpha(120),
                ),
                const SizedBox(height: 12),
                Text(
                  'No highlights or notes yet',
                  style: TextStyle(color: activeTheme.secondaryTextColor),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: highlights.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: activeTheme.isDark
                ? Colors.white.withAlpha(10)
                : Colors.black.withAlpha(10),
          ),
          itemBuilder: (context, index) {
            final hl = highlights[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              title: Text(
                hl.selectedText,
                style: TextStyle(
                  color: activeTheme.textColor,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: hl.note != null && hl.note!.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        hl.note!,
                        style: TextStyle(
                          color: activeTheme.secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: activeTheme.secondaryTextColor,
                onPressed: () {
                  ref.read(databaseServiceProvider).deleteHighlight(hl.id);
                },
              ),
              onTap: () {
                Navigator.of(context).pop();
                widget.onNavigateToPosition(hl.startPosition);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error loading notes',
          style: TextStyle(color: activeTheme.secondaryTextColor),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final ReadingThemeType activeTheme;
  final VoidCallback onTap;

  const _TabItem({
    required this.title,
    required this.isSelected,
    required this.activeTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (activeTheme.isDark
                    ? Colors.white.withAlpha(40)
                    : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected && !activeTheme.isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? activeTheme.textColor
                  : activeTheme.secondaryTextColor,
            ),
          ),
        ),
      ),
    );
  }
}
