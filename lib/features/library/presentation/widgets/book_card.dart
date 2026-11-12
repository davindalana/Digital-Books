import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/reading_progress_calculator.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/providers/reader_settings_provider.dart';
import 'book_details_dialog.dart';
import 'manage_collections_dialog.dart';

class BookCard extends ConsumerStatefulWidget {
  final Book book;
  final double? progressPercentage;
  final VoidCallback? onDetails;

  const BookCard({
    super.key,
    required this.book,
    this.progressPercentage,
    this.onDetails,
  });

  @override
  ConsumerState<BookCard> createState() => _BookCardState();
}

class _BookCardState extends ConsumerState<BookCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final progressPercentage = widget.progressPercentage;
    final hasProgress = progressPercentage != null && progressPercentage > 0.0;
    final activeMode = ref.watch(activeReadingModeProvider(book.id));
    final defaultMode = book.isScanned ? ReadingMode.originalPdf : activeMode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ReadingScreen(book: book, initialMode: defaultMode),
              ),
            );
          },
          onSecondaryTapUp: (details) {
            _showContextMenu(context, ref, details.globalPosition);
          },
          onLongPress: () => _openInfo(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book 3D Cover with Apple Books Spine Effect (2:3 Aspect Ratio)
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      children: [
                        // Book Shadow
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: AppThemeTokens.br10,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(
                                    isDark ? 80 : 35,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Cover Image with subtle border so white covers don't bleed into background
                        ClipRRect(
                          borderRadius: AppThemeTokens.br10,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2E),
                              borderRadius: AppThemeTokens.br10,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withAlpha(20)
                                    : Colors.black12,
                                width: 0.5,
                              ),
                            ),
                            child:
                                (book.coverPath != null &&
                                    File(book.coverPath!).existsSync())
                                ? Image.file(
                                    File(book.coverPath!),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    width: double.infinity,
                                    height: double.infinity,
                                  )
                                : _buildFallbackCover(),
                          ),
                        ),

                        // 3D Spine Crease / Highlight Effect
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: 0,
                          width: 14,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(10),
                              ),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withAlpha(70),
                                  Colors.black.withAlpha(15),
                                  Colors.white.withAlpha(35),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.4, 0.7, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Scanned PDF badge in bottom-left corner of cover
                        if (book.isScanned)
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Tooltip(
                              message: book.processedBookPath != null
                                  ? AppStrings.badgePindaiOcrTooltip
                                  : AppStrings.badgePindaiNeedsOcrTooltip,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(200),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(60),
                                    width: 0.5,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.document_scanner_outlined,
                                      size: 11,
                                      color: Colors.amberAccent,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      AppStrings.badgePindai,
                                      style: TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Reading Progress Bar Overlay at bottom of cover
                        if (hasProgress)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(10),
                              ),
                              child: LinearProgressIndicator(
                                value: progressPercentage.clamp(0.0, 1.0),
                                backgroundColor: Colors.black.withAlpha(100),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppThemeTokens.goldAccent,
                                ),
                                minHeight: 3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Title & 3-Dots Button Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height:
                              32, // Fixed height for 2 lines so rows align across cards
                          child: Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          book.author.trim().isEmpty
                              ? AppStrings.unknownAuthor
                              : book.author,
                          style: TextStyle(
                            fontSize: 11,
                            color: book.author.trim().isEmpty
                                ? (isDark
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400)
                                : Colors.grey.shade500,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasProgress) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${ReadingProgressCalculator.formatPercentage(progressPercentage)}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppThemeTokens.goldAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Visibility(
                    visible: _isHovered || _isFocused,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: _buildMoreButton(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        tooltip: 'Book options',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade400),
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
            ManageBookCollectionsDialog.show(context, widget.book);
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
                Text(
                  'Book Details',
                  style: TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'collections',
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.folder_special_outlined,
                  size: 17,
                  color: Colors.white70,
                ),
                SizedBox(width: 10),
                Text(
                  'Manage Collections',
                  style: TextStyle(fontSize: 13, color: Colors.white),
                ),
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
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
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
              Text(
                'Book Details',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'collections',
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.folder_special_outlined,
                size: 17,
                color: Colors.white70,
              ),
              SizedBox(width: 10),
              Text(
                'Manage Collections',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
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
      ManageBookCollectionsDialog.show(context, widget.book);
    } else if (selected == 'delete') {
      _confirmDelete(context, ref);
    }
  }

  void _openInfo(BuildContext context) async {
    if (widget.onDetails != null) {
      widget.onDetails!();
    } else {
      final req = await showDialog<BookLaunchRequest>(
        context: context,
        builder: (_) => BookDetailsDialog(book: widget.book),
      );
      if (req != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ReadingScreen(book: req.book, initialMode: req.mode),
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final book = widget.book;
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
              AppStrings.deleteBookTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Text(
          AppStrings.deleteBookMessage(book.title),
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              AppStrings.actionBatal,
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(databaseServiceProvider).safeDeleteBook(book.id);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('“${book.title}” was deleted.'),
                  backgroundColor: const Color(0xFF2C2C2E),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: const Text(
              AppStrings.deleteBookConfirm,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.book, size: 36, color: Colors.white70),
            const SizedBox(height: 8),
            Text(
              widget.book.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
