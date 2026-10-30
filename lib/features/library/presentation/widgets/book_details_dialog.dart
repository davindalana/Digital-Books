import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/utils/file_storage_service.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/providers/reader_settings_provider.dart';

class BookDetailsDialog extends ConsumerWidget {
  final Book book;

  const BookDetailsDialog({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(bookProgressStreamProvider(book.id));
    final dateFormat = DateFormat.yMMMd();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E1E22).withAlpha(240)
                  : const Color(0xFFF9F9FB).withAlpha(245),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Cover + Info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover Preview
                    Container(
                      width: 100,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(40),
                            blurRadius: 10,
                            offset: const Offset(2, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: (book.coverPath != null &&
                                File(book.coverPath!).existsSync())
                            ? Image.file(
                                File(book.coverPath!),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: const Color(0xFF2C2C2E),
                                child: const Icon(Icons.book, size: 40),
                              ),
                      ),
                    ),
                    const SizedBox(width: 18),

                    // Info Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            book.author,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Pages',
                            value: '${book.totalPages} pages',
                          ),
                          _DetailRow(
                            label: 'Format',
                            value: book.isScanned
                                ? 'Scanned PDF'
                                : 'Digital Text PDF',
                          ),
                          _DetailRow(
                            label: 'Added',
                            value: dateFormat.format(book.createdAt),
                          ),
                          progressAsync.when(
                            data: (p) => _DetailRow(
                              label: 'Progress',
                              value: p != null
                                  ? '${(p.progressPercentage * 100).toInt()}% (Page ${p.currentPosition})'
                                  : 'Not started',
                            ),
                            loading: () => const SizedBox(),
                            error: (e, stack) => const SizedBox(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Description if available
                if (book.description != null && book.description!.isNotEmpty) ...[
                  Text(
                    'About this book',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    book.description!,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                ],

                // Action Buttons
                Row(
                  children: [
                    // Delete Button
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Delete Book',
                      onPressed: () => _confirmDelete(context, ref),
                    ),
                    const Spacer(),

                    // Read in PDF Mode Button
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        ref
                            .read(activeReadingModeProvider(book.id).notifier)
                            .state = ReadingMode.originalPdf;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReadingScreen(book: book),
                          ),
                        );
                      },
                      child: const Text('Original PDF'),
                    ),
                    const SizedBox(width: 10),

                    // Read in Reflowable Book Mode Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        ref
                            .read(activeReadingModeProvider(book.id).notifier)
                            .state = ReadingMode.reflowable;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReadingScreen(book: book),
                          ),
                        );
                      },
                      child: const Text('Read Book'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Book?'),
        content: Text('Are you sure you want to remove "${book.title}" from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();

              await FileStorageService.deleteBookFiles(
                originalPdfPath: book.originalPdfPath,
                processedBookPath: book.processedBookPath,
                coverPath: book.coverPath,
              );
              await ref.read(databaseServiceProvider).deleteBook(book.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
