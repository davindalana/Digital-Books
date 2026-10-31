import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/models/highlight_palette.dart';

class HighlightSpanSegment {
  final Highlight highlight;
  final int localStart;
  final int localEnd;

  const HighlightSpanSegment({
    required this.highlight,
    required this.localStart,
    required this.localEnd,
  });
}

class ReflowableHighlightSpanBuilder {
  /// Builds a rich TextSpan with highlighted background colors, note indicators,
  /// and tap gesture recognizers for a given text slice or node.
  static TextSpan buildRichSpan({
    required String text,
    required int sliceStartOffset,
    required int sliceEndOffset,
    required List<Highlight> highlightsForNode,
    required TextStyle baseStyle,
    required ReadingThemeType theme,
    void Function(Highlight highlight)? onHighlightTap,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    if (highlightsForNode.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    // 1. Calculate intersecting segments within the local text range [0, text.length]
    final segments = <HighlightSpanSegment>[];

    for (final hl in highlightsForNode) {
      final start = hl.startOffset;
      final end = hl.endOffset;

      if (end <= sliceStartOffset || start >= sliceEndOffset) {
        continue; // No overlap
      }

      final localStart = math.max(0, start - sliceStartOffset).clamp(0, text.length);
      final localEnd = math.min(text.length, end - sliceStartOffset).clamp(0, text.length);

      if (localEnd > localStart) {
        segments.add(
          HighlightSpanSegment(
            highlight: hl,
            localStart: localStart,
            localEnd: localEnd,
          ),
        );
      }
    }

    if (segments.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    // Sort by local start offset
    segments.sort((a, b) => a.localStart.compareTo(b.localStart));

    // 2. Build non-overlapping span sequence
    final children = <InlineSpan>[];
    int cursor = 0;

    for (final seg in segments) {
      if (seg.localStart > cursor) {
        // Plain text before highlight
        children.add(
          TextSpan(
            text: text.substring(cursor, seg.localStart),
            style: baseStyle,
          ),
        );
        cursor = seg.localStart;
      }

      if (seg.localEnd > cursor) {
        final hl = seg.highlight;
        final colorType = HighlightColorType.fromKey(hl.color);
        final bg = colorType.getBackgroundColor(theme);
        final hasNote = hl.note != null && hl.note!.trim().isNotEmpty;

        final hlStyle = baseStyle.copyWith(
          backgroundColor: bg,
          decoration: hasNote ? TextDecoration.underline : TextDecoration.none,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: colorType.primaryColor,
        );

        final spanText = text.substring(cursor, seg.localEnd);

        children.add(
          TextSpan(
            text: spanText,
            style: hlStyle,
            recognizer: onHighlightTap != null
                ? (TapGestureRecognizer()..onTap = () => onHighlightTap(hl))
                : null,
            children: [
              if (hasNote && seg.localEnd == (hl.endOffset - sliceStartOffset))
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
            ],
          ),
        );

        cursor = seg.localEnd;
      }
    }

    // Append any trailing text after the last highlight
    if (cursor < text.length) {
      children.add(
        TextSpan(
          text: text.substring(cursor),
          style: baseStyle,
        ),
      );
    }

    return TextSpan(children: children);
  }
}
