import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/providers/reader_settings_provider.dart';
import '../../../processing/providers/background_ocr_provider.dart';
import 'manage_collections_dialog.dart';

class BookDetailsDialog extends ConsumerStatefulWidget {
  final Book book;

  const BookDetailsDialog({super.key, required this.book});

  @override
  ConsumerState<BookDetailsDialog> createState() => _BookDetailsDialogState();
}

class _BookDetailsDialogState extends ConsumerState<BookDetailsDialog> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _descController;
  late Book _currentBook;

  @override
  void initState() {
    super.initState();
    _currentBook = widget.book;
    _titleController = TextEditingController(text: _currentBook.title);
    _authorController = TextEditingController(text: _currentBook.author);
    _descController = TextEditingController(
      text: _currentBook.description ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _saveMetadata() async {
    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title cannot be empty')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final dbService = ref.read(databaseServiceProvider);
      await dbService.updateBookMetadata(
        _currentBook.id,
        title: title,
        author: author.isEmpty ? 'Unknown Author' : author,
        description: desc.isEmpty ? null : desc,
      );

      final updated = await dbService.getBookById(_currentBook.id);
      if (mounted) {
        setState(() {
          if (updated != null) _currentBook = updated;
          _isEditing = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Book details updated successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update book: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progressAsync = ref.watch(
      bookProgressStreamProvider(_currentBook.id),
    );
    final dateFormat = DateFormat.yMMMd();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              color: isDark
                  ? const Color(0xFF1E1E22).withAlpha(240)
                  : const Color(0xFFF9F9FB).withAlpha(245),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(20),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Action Bar in Dialog (Edit Toggle & Close)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isEditing ? 'EDIT BOOK DETAILS' : 'BOOK INFO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      Row(
                        children: [
                          if (!_isEditing) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.folder_special_outlined,
                                size: 19,
                              ),
                              tooltip: 'Manage Collections',
                              onPressed: () => ManageBookCollectionsDialog.show(
                                context,
                                _currentBook,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              tooltip: 'Edit Metadata',
                              onPressed: () =>
                                  setState(() => _isEditing = true),
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.close, size: 19),
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Top Row: Cover + Info or Edit Fields
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
                          child:
                              (_currentBook.coverPath != null &&
                                  File(_currentBook.coverPath!).existsSync())
                              ? Image.file(
                                  File(_currentBook.coverPath!),
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                )
                              : Container(
                                  color: const Color(0xFF2C2C2E),
                                  child: const Icon(Icons.book, size: 40),
                                ),
                        ),
                      ),
                      const SizedBox(width: 18),

                      // Info Column or Edit Fields
                      Expanded(
                        child: _isEditing
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: _titleController,
                                    decoration: const InputDecoration(
                                      labelText: 'Book Title',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _authorController,
                                    decoration: const InputDecoration(
                                      labelText: 'Author',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _descController,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                      labelText: 'Description / Notes',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentBook.title,
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
                                    _currentBook.author,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _DetailRow(
                                    label: 'Pages',
                                    value: '${_currentBook.totalPages} pages',
                                  ),
                                  _DetailRow(
                                    label: 'Format',
                                    value: _currentBook.isScanned
                                        ? 'Scanned PDF'
                                        : 'Digital Text PDF',
                                  ),
                                  _DetailRow(
                                    label: 'Reflowable',
                                    value: _currentBook.processedBookPath != null
                                        ? 'Tersedia (OCR Selesai)'
                                        : (_currentBook.isScanned
                                            ? 'Belum diproses'
                                            : 'Bawaan'),
                                  ),
                                  _DetailRow(
                                    label: 'Added',
                                    value: dateFormat.format(
                                      _currentBook.createdAt,
                                    ),
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

                  // Description if in read-only mode and not empty
                  if (!_isEditing &&
                      _currentBook.description != null &&
                      _currentBook.description!.isNotEmpty) ...[
                    Text(
                      'About this book',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _currentBook.description!,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Background OCR progress / trigger card for scanned books
                  if (!_isEditing && _currentBook.isScanned)
                    Consumer(
                      builder: (context, ref, _) {
                        final ocrProgressAsync =
                            ref.watch(ocrQueueProgressStreamProvider);
                        final ocrProgress = ocrProgressAsync.valueOrNull;
                        final isRunning = ocrProgress != null &&
                            ocrProgress.bookId == _currentBook.id &&
                            ocrProgress.isRunning;
                        final isPaused = ocrProgress != null &&
                            ocrProgress.bookId == _currentBook.id &&
                            ocrProgress.isPaused;

                        if (isRunning || isPaused) {
                          final pct =
                              (ocrProgress.progressPercentage * 100).toInt();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF).withAlpha(15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF007AFF).withAlpha(40),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isPaused
                                          ? 'OCR Dijeda'
                                          : 'Memproses OCR Latar Belakang...',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                    Text(
                                      '$pct%',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: ocrProgress.progressPercentage,
                                  backgroundColor:
                                      const Color(0xFF007AFF).withAlpha(30),
                                  valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFF007AFF),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Halaman ${ocrProgress.completedPages} dari ${ocrProgress.totalPages}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            if (isPaused) {
                                              ref
                                                  .read(
                                                    backgroundOcrQueueProvider,
                                                  )
                                                  .resume();
                                            } else {
                                              ref
                                                  .read(
                                                    backgroundOcrQueueProvider,
                                                  )
                                                  .pause();
                                            }
                                          },
                                          child: Text(
                                            isPaused ? 'Lanjutkan' : 'Jeda',
                                            style:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            ref
                                                .read(
                                                  backgroundOcrQueueProvider,
                                                )
                                                .cancel();
                                          },
                                          child: const Text(
                                            'Batal',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        if (_currentBook.processedBookPath == null) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withAlpha(8)
                                  : Colors.black.withAlpha(5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.auto_stories_outlined,
                                  size: 20,
                                  color: Color(0xFF007AFF),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Mode Buku belum tersedia',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Jalankan OCR lokal untuk menghasilkan teks reflowable.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    ref.read(backgroundOcrQueueProvider).start(
                                          bookId: _currentBook.id,
                                          pdfPath: _currentBook.originalPdfPath,
                                          autoReconstruct: true,
                                        );
                                  },
                                  child: const Text('Mulai OCR'),
                                ),
                              ],
                            ),
                          );
                        }

                        return const SizedBox.shrink();
                      },
                    ),

                  // Action Buttons Row
                  if (_isEditing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  _titleController.text = _currentBook.title;
                                  _authorController.text = _currentBook.author;
                                  _descController.text =
                                      _currentBook.description ?? '';
                                  setState(() => _isEditing = false);
                                },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check, size: 16),
                          label: const Text('Save Changes'),
                          onPressed: _isSaving ? null : _saveMetadata,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        // Delete Button
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Delete Book',
                          onPressed: () => _confirmDelete(context, ref),
                        ),
                        const Spacer(),

                        // Read in PDF Mode Button
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            ref
                                    .read(
                                      activeReadingModeProvider(
                                        _currentBook.id,
                                      ).notifier,
                                    )
                                    .state =
                                ReadingMode.originalPdf;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReadingScreen(
                                  book: _currentBook,
                                  initialMode: ReadingMode.originalPdf,
                                ),
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
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            final mode = (_currentBook.processedBookPath !=
                                        null ||
                                    !_currentBook.isScanned)
                                ? ReadingMode.reflowable
                                : ReadingMode.originalPdf;
                            ref
                                    .read(
                                      activeReadingModeProvider(
                                        _currentBook.id,
                                      ).notifier,
                                    )
                                    .state =
                                mode;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReadingScreen(
                                  book: _currentBook,
                                  initialMode: mode,
                                ),
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
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Book?'),
        content: Text(
          'Are you sure you want to remove "${_currentBook.title}" from your library?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();

              await ref
                  .read(databaseServiceProvider)
                  .safeDeleteBook(_currentBook.id);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
