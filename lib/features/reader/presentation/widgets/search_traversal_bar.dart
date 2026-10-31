import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';

class SearchTraversalBar extends StatelessWidget {
  final String query;
  final int currentIndex;
  final int totalCount;
  final ReadingThemeType theme;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const SearchTraversalBar({
    super.key,
    required this.query,
    required this.currentIndex,
    required this.totalCount,
    required this.theme,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.isDark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1E22).withAlpha(230)
                : Colors.white.withAlpha(240),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(25)
                  : Colors.black.withAlpha(15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 80 : 25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Query Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withAlpha(isDark ? 45 : 30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search,
                      size: 14,
                      color: Color(0xFFFF9500),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        query,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF9500),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Match Count Indicator
              Text(
                totalCount > 0
                    ? '${currentIndex + 1} dari $totalCount'
                    : '0 hasil',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.textColor,
                ),
              ),
              const SizedBox(width: 6),

              // Previous Match
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: totalCount > 1
                      ? theme.textColor
                      : theme.secondaryTextColor.withAlpha(100),
                ),
                tooltip: 'Hasil Sebelumnya (Shift+Enter)',
                onPressed: totalCount > 1 ? onPrevious : null,
              ),

              // Next Match
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: totalCount > 1
                      ? theme.textColor
                      : theme.secondaryTextColor.withAlpha(100),
                ),
                tooltip: 'Hasil Berikutnya (Enter)',
                onPressed: totalCount > 1 ? onNext : null,
              ),

              const SizedBox(width: 4),
              Container(
                width: 1,
                height: 16,
                color: theme.secondaryTextColor.withAlpha(40),
              ),
              const SizedBox(width: 4),

              // Close Traversal
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.secondaryTextColor,
                ),
                tooltip: 'Selesai Pencarian (Esc)',
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
