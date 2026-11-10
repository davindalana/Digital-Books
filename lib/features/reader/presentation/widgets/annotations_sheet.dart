import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../domain/models/book_annotation.dart';
import '../../domain/models/highlight_palette.dart';

class AnnotationsSheet extends StatefulWidget {
  final String bookTitle;
  final List<BookAnnotation> annotations;
  final ReadingThemeType theme;
  final void Function(BookAnnotation annotation) onNavigateToAnnotation;
  final void Function(BookAnnotation annotation)? onEditAnnotation;
  final void Function(BookAnnotation annotation)? onDeleteAnnotation;

  const AnnotationsSheet({
    super.key,
    required this.bookTitle,
    required this.annotations,
    required this.theme,
    required this.onNavigateToAnnotation,
    this.onEditAnnotation,
    this.onDeleteAnnotation,
  });

  static Future<void> show({
    required BuildContext context,
    required String bookTitle,
    required List<BookAnnotation> annotations,
    required ReadingThemeType theme,
    required void Function(BookAnnotation annotation) onNavigateToAnnotation,
    void Function(BookAnnotation annotation)? onEditAnnotation,
    void Function(BookAnnotation annotation)? onDeleteAnnotation,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnnotationsSheet(
        bookTitle: bookTitle,
        annotations: annotations,
        theme: theme,
        onNavigateToAnnotation: (a) {
          Navigator.of(ctx).pop();
          onNavigateToAnnotation(a);
        },
        onEditAnnotation: onEditAnnotation,
        onDeleteAnnotation: onDeleteAnnotation,
      ),
    );
  }

  @override
  State<AnnotationsSheet> createState() => _AnnotationsSheetState();
}

class _AnnotationsSheetState extends State<AnnotationsSheet> {
  String _searchFilter = '';
  AnnotationType? _selectedTypeFilter; // null = Semua

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.isDark;
    final bgColor = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = isDark ? Colors.white60 : Colors.black54;

    final filtered = widget.annotations.where((a) {
      if (_selectedTypeFilter != null) {
        if (_selectedTypeFilter == AnnotationType.note) {
          if (!a.hasNote) return false;
        } else if (_selectedTypeFilter == AnnotationType.highlight) {
          if (a.isBookmark || a.hasNote) return false;
        } else if (_selectedTypeFilter == AnnotationType.bookmark) {
          if (!a.isBookmark) return false;
        }
      }

      if (_searchFilter.trim().isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        final textMatch = a.selectedText.toLowerCase().contains(q);
        final noteMatch = (a.note ?? '').toLowerCase().contains(q);
        if (!textMatch && !noteMatch) return false;
      }
      return true;
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.collections_bookmark_rounded,
                      size: 20,
                      color: const Color(0xFFFF9500),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Anotasi & Penanda Buku',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          Text(
                            widget.bookTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: secondaryColor),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Search Filter Field
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: TextField(
                  key: const ValueKey('annotations_search_field'),
                  decoration: InputDecoration(
                    hintText: 'Cari dalam catatan atau teks sorotan...',
                    hintStyle: TextStyle(fontSize: 13, color: secondaryColor),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: secondaryColor,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: secondaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  style: TextStyle(fontSize: 13, color: textColor),
                  onChanged: (val) {
                    setState(() {
                      _searchFilter = val;
                    });
                  },
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        'Semua (${widget.annotations.length})',
                        null,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Sorotan (${widget.annotations.where((a) => !a.isBookmark && !a.hasNote).length})',
                        AnnotationType.highlight,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Catatan (${widget.annotations.where((a) => a.hasNote).length})',
                        AnnotationType.note,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Penanda (${widget.annotations.where((a) => a.isBookmark).length})',
                        AnnotationType.bookmark,
                        isDark,
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 16),

              // Annotations List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border_rounded,
                              size: 48,
                              color: secondaryColor.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Belum ada anotasi atau penanda',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final a = filtered[idx];
                          return _buildAnnotationTile(
                            a,
                            isDark,
                            textColor,
                            secondaryColor,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, AnnotationType? type, bool isDark) {
    final isSelected = _selectedTypeFilter == type;
    final activeColor = const Color(0xFFFF9500);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _selectedTypeFilter = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.22)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? activeColor
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnotationTile(
    BookAnnotation a,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final colorType = HighlightColorType.fromKey(a.color);
    final cardBg = isDark ? const Color(0xFF28282D) : const Color(0xFFF7F7FA);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onNavigateToAnnotation(a),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Type Badge, Page Number, Date, Actions
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: a.isBookmark
                          ? const Color(0xFFFF9500)
                          : colorType.primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    a.isBookmark
                        ? 'Penanda Buku'
                        : (a.hasNote ? 'Catatan' : 'Sorotan'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: a.isBookmark
                          ? const Color(0xFFFF9500)
                          : colorType.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (a.pageIndex != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Hal. ${a.pageIndex}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: secondaryColor,
                        ),
                      ),
                    ),
                  if (a.isUnresolved) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Lokasi berubah',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.onEditAnnotation != null && !a.isBookmark)
                    IconButton(
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      icon: Icon(Icons.edit_outlined, color: secondaryColor),
                      onPressed: () => widget.onEditAnnotation!(a),
                    ),
                  if (widget.onDeleteAnnotation != null)
                    IconButton(
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: secondaryColor,
                      ),
                      onPressed: () => widget.onDeleteAnnotation!(a),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Selected Text
              Text(
                a.selectedText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: textColor,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // Note Content if present
              if (a.hasNote) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.edit_note_rounded,
                        size: 16,
                        color: Color(0xFFFF9500),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          a.note!,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: textColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
