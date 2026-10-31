import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../domain/models/reader_content.dart';
import '../../domain/models/toc_item.dart';
import '../../models/book_document.dart';
import '../../providers/reader_settings_provider.dart';

class TocDialog extends ConsumerStatefulWidget {
  final String bookId;
  final BookDocument? bookDocument;
  final ReaderDocument? readerDocument;
  final int currentChapterIndex;
  final String? currentAnchorNodeId;
  final Function(int chapterIndex, int pageNumber, String? anchorNodeId)?
  onNavigateToTocItem;
  final Function(int chapterIndex, int pageNumber) onNavigateToChapter;
  final Function(int position) onNavigateToPosition;
  final Function(String anchorNodeId, int charOffset)? onNavigateToAnchor;

  const TocDialog({
    super.key,
    required this.bookId,
    this.bookDocument,
    this.readerDocument,
    this.currentChapterIndex = 0,
    this.currentAnchorNodeId,
    this.onNavigateToTocItem,
    required this.onNavigateToChapter,
    required this.onNavigateToPosition,
    this.onNavigateToAnchor,
  });

  @override
  ConsumerState<TocDialog> createState() => _TocDialogState();
}

class _TocDialogState extends ConsumerState<TocDialog> {
  int _selectedTab = 0; // 0: Contents, 1: Bookmarks, 2: Highlights
  final Set<String> _expandedChapterIds = {};

  @override
  void initState() {
    super.initState();
    // Auto-expand current reading chapter
    if (widget.readerDocument != null &&
        widget.readerDocument!.chapters.isNotEmpty) {
      final safeIdx = widget.currentChapterIndex.clamp(
        0,
        widget.readerDocument!.chapters.length - 1,
      );
      _expandedChapterIds.add(widget.readerDocument!.chapters[safeIdx].id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final bookmarksAsync = ref.watch(
      bookBookmarksStreamProvider(widget.bookId),
    );
    final highlightsAsync = ref.watch(
      bookHighlightsStreamProvider(widget.bookId),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: 560,
            height: 620,
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(activeTheme.isDark ? 90 : 30),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
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
                                title: 'Daftar Isi',
                                isSelected: _selectedTab == 0,
                                activeTheme: activeTheme,
                                onTap: () => setState(() => _selectedTab = 0),
                              ),
                              _TabItem(
                                title: 'Penanda',
                                isSelected: _selectedTab == 1,
                                activeTheme: activeTheme,
                                onTap: () => setState(() => _selectedTab = 1),
                              ),
                              _TabItem(
                                title: 'Catatan',
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
                      ? _buildContentsList(activeTheme)
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

  Widget _buildContentsList(ReadingThemeType activeTheme) {
    List<TocItem> tocItems = const [];

    if (widget.readerDocument != null) {
      tocItems = TocHierarchyBuilder.buildFromDocument(widget.readerDocument!);
    } else if (widget.bookDocument != null) {
      // Legacy fallback
      final chs = widget.bookDocument!.chapters;
      tocItems = chs.asMap().entries.map((e) {
        final firstBlock = e.value.blocks.isNotEmpty
            ? e.value.blocks.first
            : null;
        return TocItem(
          id: e.value.id,
          title: e.value.title,
          level: 1,
          chapterIndex: e.key,
          chapterId: e.value.id,
          anchorNodeId: firstBlock?.id ?? e.value.id,
          sourcePdfPage: firstBlock?.originalPageNumber ?? (e.key + 1),
        );
      }).toList();
    }

    if (tocItems.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada daftar isi terdeteksi',
          style: TextStyle(color: activeTheme.secondaryTextColor),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tocItems.length,
      itemBuilder: (context, index) {
        final item = tocItems[index];
        return _buildChapterTocTile(item, activeTheme);
      },
    );
  }

  Widget _buildChapterTocTile(TocItem item, ReadingThemeType activeTheme) {
    final isCurrentChapter = item.chapterIndex == widget.currentChapterIndex;
    final isExpanded = _expandedChapterIds.contains(item.id);
    final hasChildren = item.hasChildren;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            Navigator.of(context).pop();
            if (widget.onNavigateToTocItem != null) {
              widget.onNavigateToTocItem!(
                item.chapterIndex,
                item.sourcePdfPage,
                item.anchorNodeId,
              );
            } else {
              widget.onNavigateToChapter(item.chapterIndex, item.sourcePdfPage);
            }
          },
          child: Container(
            color: isCurrentChapter
                ? (activeTheme.isDark
                      ? Colors.white.withAlpha(15)
                      : const Color(0xFF007AFF).withAlpha(15))
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (hasChildren)
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    icon: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: activeTheme.secondaryTextColor,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedChapterIds.remove(item.id);
                        } else {
                          _expandedChapterIds.add(item.id);
                        }
                      });
                    },
                  )
                else
                  const SizedBox(width: 24),
                const SizedBox(width: 4),
                // Chapter Title
                Expanded(
                  child: Row(
                    children: [
                      if (isCurrentChapter)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF007AFF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            color: isCurrentChapter
                                ? (activeTheme.isDark
                                      ? const Color(0xFF64B5F6)
                                      : const Color(0xFF007AFF))
                                : activeTheme.textColor,
                            fontSize: 14.5,
                            fontWeight: isCurrentChapter
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'hal. ${item.sourcePdfPage}',
                  style: TextStyle(
                    color: activeTheme.secondaryTextColor.withAlpha(180),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Nested Subheadings (H2, H3)
        if (hasChildren && isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              children: item.children.map((subItem) {
                final isCurrentNode =
                    subItem.anchorNodeId == widget.currentAnchorNodeId;
                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    if (widget.onNavigateToTocItem != null) {
                      widget.onNavigateToTocItem!(
                        subItem.chapterIndex,
                        subItem.sourcePdfPage,
                        subItem.anchorNodeId,
                      );
                    } else if (widget.onNavigateToAnchor != null) {
                      widget.onNavigateToAnchor!(subItem.anchorNodeId, 0);
                    } else {
                      widget.onNavigateToChapter(
                        subItem.chapterIndex,
                        subItem.sourcePdfPage,
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    color: isCurrentNode
                        ? (activeTheme.isDark
                              ? Colors.white.withAlpha(12)
                              : const Color(0xFF007AFF).withAlpha(12))
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 14,
                          color: activeTheme.secondaryTextColor.withAlpha(140),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subItem.title,
                            style: TextStyle(
                              color: isCurrentNode
                                  ? (activeTheme.isDark
                                        ? const Color(0xFF64B5F6)
                                        : const Color(0xFF007AFF))
                                  : activeTheme.textColor.withAlpha(220),
                              fontSize: 13,
                              fontWeight: isCurrentNode
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'hal. ${subItem.sourcePdfPage}',
                          style: TextStyle(
                            color: activeTheme.secondaryTextColor.withAlpha(
                              140,
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: activeTheme.isDark
              ? Colors.white.withAlpha(8)
              : Colors.black.withAlpha(8),
        ),
      ],
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
                  'Belum ada penanda halaman',
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              leading: const Icon(
                Icons.bookmark_rounded,
                color: Color(0xFFFF9500),
                size: 20,
              ),
              title: Text(
                bm.label,
                style: TextStyle(
                  color: activeTheme.textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
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
                if (bm.anchorNodeId != null &&
                    widget.onNavigateToAnchor != null) {
                  widget.onNavigateToAnchor!(
                    bm.anchorNodeId!,
                    bm.characterOffset,
                  );
                } else {
                  widget.onNavigateToPosition(bm.position);
                }
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Gagal memuat penanda',
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
                  'Belum ada sorotan atau catatan',
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              title: Text(
                hl.selectedText,
                style: TextStyle(
                  color: activeTheme.textColor,
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: hl.note != null && hl.note!.trim().isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        hl.note!,
                        style: TextStyle(
                          color: activeTheme.secondaryTextColor,
                          fontSize: 12.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                if (hl.anchorNodeId != null &&
                    widget.onNavigateToAnchor != null) {
                  widget.onNavigateToAnchor!(hl.anchorNodeId!, hl.startOffset);
                } else {
                  widget.onNavigateToPosition(hl.startPosition);
                }
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Gagal memuat catatan',
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? (activeTheme.isDark ? const Color(0xFF2C2C2E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(
                        activeTheme.isDark ? 40 : 15,
                      ),
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
