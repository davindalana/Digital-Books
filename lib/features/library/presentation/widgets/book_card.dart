import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/providers/reader_settings_provider.dart';

class BookCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasProgress = progressPercentage != null && progressPercentage! > 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReadingScreen(
              book: book,
              initialMode: book.isScanned ? ReadingMode.originalPdf : ReadingMode.reflowable,
            ),
          ),
        );
      },
      onLongPress: onDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Book 3D Cover with Apple Books Spine Effect
          Expanded(
            child: Stack(
              children: [
                // Book Shadow
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(55),
                          blurRadius: 12,
                          offset: const Offset(3, 6),
                        ),
                      ],
                    ),
                  ),
                ),

                // Cover Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF2C2C2E),
                    ),
                    child: (book.coverPath != null &&
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
                        left: Radius.circular(8),
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

                // Scanned PDF badge
                if (book.isScanned)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withAlpha(60),
                          width: 0.5,
                        ),
                      ),
                      child: const Text(
                        'SCAN',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
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
                        bottom: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value: progressPercentage!.clamp(0.0, 1.0),
                        backgroundColor: Colors.black.withAlpha(100),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF007AFF),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Book Title
          Text(
            book.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

          // Book Author
          Text(
            book.author,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
              book.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
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

