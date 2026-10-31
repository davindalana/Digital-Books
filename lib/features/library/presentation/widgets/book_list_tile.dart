import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/providers/reader_settings_provider.dart';
import 'book_details_dialog.dart';
import 'manage_collections_dialog.dart';

class BookListTile extends ConsumerWidget {
  final Book book;
  final double? progressPercentage;
  final VoidCallback? onDetails;

  const BookListTile({
    super.key,
    required this.book,
    this.progressPercentage,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(bookProgressStreamProvider(book.id));
    final activeMode = ref.watch(activeReadingModeProvider(book.id));
    final defaultMode = book.isScanned ? ReadingMode.originalPdf : activeMode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat.yMMMd();

    final coverFile =
        book.coverPath != null ? File(book.coverPath!) : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(12),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReadingScreen(
                  book: book,
                  initialMode: defaultMode,
                ),
              ),
            );
          },
          onSecondaryTapUp: (details) {
            _showContextMenu(context, ref, details.globalPosition);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Cover Thumbnail
                Container(
                  width: 44,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 80 : 30),
                        blurRadius: 6,
                        offset: const Offset(1, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: (coverFile != null && coverFile.existsSync())
                        ? Image.file(coverFile, fit: BoxFit.cover)
                        : Container(
                            color: const Color(0xFF2C2C2E),
                            child: const Icon(Icons.book,
                                size: 22, color: Colors.white70),
                          ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title, Author, Format Badge
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: book.isScanned
                                  ? Colors.amber.withAlpha(30)
                                  : const Color(0xFF007AFF).withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              book.isScanned ? 'SCAN' : 'PDF',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: book.isScanned
                                  ? (isDark ? Colors.amberAccent : Colors.orange.shade800)
                                  : const Color(0xFF007AFF),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Progress Bar & Info
                Expanded(
                  flex: 2,
                  child: progressAsync.when(
                    data: (progress) {
                      final pct = progressPercentage ??
                          progress?.progressPercentage ??
                          0.0;
                      if (pct <= 0.0) {
                        return Text(
                          '${book.totalPages} pages',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              backgroundColor: isDark
                                  ? Colors.white.withAlpha(20)
                                  : Colors.black.withAlpha(15),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF007AFF),
                              ),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(pct * 100).toInt()}% • Page ${progress?.currentPosition ?? 1} of ${book.totalPages}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (e, stack) => const SizedBox.shrink(),
                  ),
                ),

                const SizedBox(width: 16),

                // Date Added
                Text(
                  dateFormat.format(book.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  ),
                ),

                const SizedBox(width: 8),

                // 3-Dots Popup
                _buildMoreButton(context, ref),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        tooltip: 'Book options',
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_horiz,
          size: 18,
          color: Colors.grey.shade400,
        ),
        color: const Color(0xFF222226),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withAlpha(25)),
        ),
        onSelected: (value) {
          if (value == 'info') {
            _openInfo(context);
          } else if (value == 'collections') {
            ManageBookCollectionsDialog.show(context, book);
          } else if (value == 'delete') {
            _confirmDelete(context, ref);
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem<String>(
            value: 'info',
            height: 38,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 17, color: Colors.white70),
                SizedBox(width: 10),
                Text('Info About Book',
                    style: TextStyle(fontSize: 13, color: Colors.white)),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'collections',
            height: 38,
            child: Row(
              children: [
                Icon(Icons.folder_special_outlined,
                    size: 17, color: Colors.white70),
                SizedBox(width: 10),
                Text('Manage Collections',
                    style: TextStyle(fontSize: 13, color: Colors.white)),
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: 'delete',
            height: 38,
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                SizedBox(width: 10),
                Text(
                  'Delete Book',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, WidgetRef ref, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: const Color(0xFF222226),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withAlpha(25)),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'info',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 17, color: Colors.white70),
              SizedBox(width: 10),
              Text('Info About Book',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'collections',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.folder_special_outlined,
                  size: 17, color: Colors.white70),
              SizedBox(width: 10),
              Text('Manage Collections',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'delete',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
              SizedBox(width: 10),
              Text(
                'Delete Book',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;

    if (selected == 'info') {
      _openInfo(context);
    } else if (selected == 'collections') {
      ManageBookCollectionsDialog.show(context, book);
    } else if (selected == 'delete') {
      _confirmDelete(context, ref);
    }
  }

  void _openInfo(BuildContext context) {
    if (onDetails != null) {
      onDetails!();
    } else {
      showDialog(
        context: context,
        builder: (_) => BookDetailsDialog(book: book),
      );
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withAlpha(25)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Hapus Buku?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${book.title}"?\n\nBuku, file PDF, cover, dan progres membaca akan dihapus secara permanen.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(databaseServiceProvider).safeDeleteBook(book.id);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Buku "${book.title}" berhasil dihapus.'),
                  backgroundColor: const Color(0xFF2C2C2E),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: const Text('Hapus Buku',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
