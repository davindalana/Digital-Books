import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/models/highlight_palette.dart';

class ActiveSearchMatch {
  final String nodeId;
  final int startOffset;
  final int endOffset;
  final bool isActive;

  const ActiveSearchMatch({
    required this.nodeId,
    required this.startOffset,
    required this.endOffset,
    this.isActive = true,
  });
}

class ReflowableHighlightSpanBuilder {
  /// Builds a rich TextSpan with highlighted background colors, note indicators,
  /// search match highlighting, and tap gesture recognizers for a given text slice or node.
  static TextSpan buildRichSpan({
    required String text,
    required int sliceStartOffset,
    required int sliceEndOffset,
    required List<Highlight> highlightsForNode,
    List<ActiveSearchMatch> searchMatchesForNode = const [],
    required TextStyle baseStyle,
    required ReadingThemeType theme,
    void Function(Highlight highlight)? onHighlightTap,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    if (highlightsForNode.isEmpty && searchMatchesForNode.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    // 1. Collect all local cut-points (boundary offsets in range [0, text.length])
    final cutPoints = <int>{0, text.length};

    // User highlights
    final localHighlights = <({Highlight hl, int start, int end})>[];
    for (final hl in highlightsForNode) {
      if (hl.endOffset <= sliceStartOffset ||
          hl.startOffset >= sliceEndOffset) {
        continue;
      }
      final localStart = math
          .max(0, hl.startOffset - sliceStartOffset)
          .clamp(0, text.length);
      final localEnd = math
          .min(text.length, hl.endOffset - sliceStartOffset)
          .clamp(0, text.length);
      if (localEnd > localStart) {
        localHighlights.add((hl: hl, start: localStart, end: localEnd));
        cutPoints.add(localStart);
        cutPoints.add(localEnd);
      }
    }

    // Search matches
    final localSearchMatches =
        <({ActiveSearchMatch match, int start, int end})>[];
    for (final sm in searchMatchesForNode) {
      if (sm.endOffset <= sliceStartOffset ||
          sm.startOffset >= sliceEndOffset) {
        continue;
      }
      final localStart = math
          .max(0, sm.startOffset - sliceStartOffset)
          .clamp(0, text.length);
      final localEnd = math
          .min(text.length, sm.endOffset - sliceStartOffset)
          .clamp(0, text.length);
      if (localEnd > localStart) {
        localSearchMatches.add((match: sm, start: localStart, end: localEnd));
        cutPoints.add(localStart);
        cutPoints.add(localEnd);
      }
    }

    final sortedPoints = cutPoints.toList()..sort();
    final children = <InlineSpan>[];

    // 2. Iterate each segment between consecutive cut points
    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final segStart = sortedPoints[i];
      final segEnd = sortedPoints[i + 1];
      if (segStart >= segEnd) continue;

      final segText = text.substring(segStart, segEnd);

      // Check user highlight coverage
      Highlight? matchingHl;
      for (final h in localHighlights) {
        if (segStart >= h.start && segEnd <= h.end) {
          matchingHl = h.hl;
          break;
        }
      }

      // Check search match coverage
      ActiveSearchMatch? matchingSearch;
      for (final sm in localSearchMatches) {
        if (segStart >= sm.start && segEnd <= sm.end) {
          matchingSearch = sm.match;
          break;
        }
      }

      TextStyle segStyle = baseStyle;
      final spanChildren = <InlineSpan>[];

      if (matchingSearch != null) {
        // High visibility active search highlight: vivid amber/orange
        final searchBg = matchingSearch.isActive
            ? const Color(0xFFFF9500).withValues(alpha: 0.55)
            : const Color(0xFFFFD54F).withValues(alpha: 0.40);

        segStyle = segStyle.copyWith(
          backgroundColor: searchBg,
          fontWeight: matchingSearch.isActive
              ? FontWeight.bold
              : segStyle.fontWeight,
          decoration: matchingSearch.isActive
              ? TextDecoration.underline
              : TextDecoration.none,
          decorationColor: const Color(0xFFFF9500),
          decorationThickness: 2.0,
        );
      } else if (matchingHl != null) {
        final colorType = HighlightColorType.fromKey(matchingHl.color);
        final bg = colorType.getBackgroundColor(theme);
        final hasNote =
            matchingHl.note != null && matchingHl.note!.trim().isNotEmpty;

        segStyle = segStyle.copyWith(
          backgroundColor: bg,
          decoration: hasNote ? TextDecoration.underline : TextDecoration.none,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: colorType.primaryColor,
        );
      }

      // Add note indicator icon if this segment ends a note-bearing highlight
      if (matchingHl != null) {
        final hasNote =
            matchingHl.note != null && matchingHl.note!.trim().isNotEmpty;
        final noteEndInSlice = matchingHl.endOffset - sliceStartOffset;
        if (hasNote && segEnd == noteEndInSlice) {
          final colorType = HighlightColorType.fromKey(matchingHl.color);
          spanChildren.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 3, right: 1),
                child: Icon(
                  Icons.note_alt_rounded,
                  size: (baseStyle.fontSize ?? 16) * 0.75,
                  color: colorType.primaryColor,
                ),
              ),
            ),
          );
        }
      }

      final hlToTap = matchingHl;
      children.add(
        TextSpan(
          text: segText,
          style: segStyle,
          recognizer: (hlToTap != null && onHighlightTap != null)
              ? (TapGestureRecognizer()..onTap = () => onHighlightTap(hlToTap))
              : null,
          children: spanChildren.isNotEmpty ? spanChildren : null,
        ),
      );
    }

    return TextSpan(children: children);
  }
}
