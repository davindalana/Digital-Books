import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:drift/drift.dart' as drift;
import '../../../../core/database/app_database.dart';

enum AnnotationType {
  highlight,
  note,
  bookmark,
}

enum AnchorStatus {
  resolved,
  unresolved,
  approximate,
}

/// Unified domain model for book annotations: highlights, notes, and bookmarks.
/// Supports cross-mode anchor references across Original PDF and Reflowable reader.
class BookAnnotation {
  final String id;
  final String bookId;
  final AnnotationType type;
  final String selectedText;
  final String? prefixContext;
  final String? suffixContext;
  final String? chapterId;
  final String? anchorNodeId;
  final int startOffset;
  final int endOffset;
  final int? pageIndex; // 1-based page index for PDF / page position
  final List<Rect> boundingBoxes; // Relative coordinates [0.0 .. 1.0]
  final String color; // 'yellow', 'green', 'blue', 'pink', 'purple', 'gold'
  final String? note;
  final AnchorStatus anchorStatus;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BookAnnotation({
    required this.id,
    required this.bookId,
    required this.type,
    required this.selectedText,
    this.prefixContext,
    this.suffixContext,
    this.chapterId,
    this.anchorNodeId,
    this.startOffset = 0,
    this.endOffset = 0,
    this.pageIndex,
    this.boundingBoxes = const [],
    this.color = 'yellow',
    this.note,
    this.anchorStatus = AnchorStatus.resolved,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isBookmark => type == AnnotationType.bookmark;
  bool get isHighlight =>
      type == AnnotationType.highlight || type == AnnotationType.note;
  bool get hasNote => note != null && note!.trim().isNotEmpty;
  bool get isResolved => anchorStatus == AnchorStatus.resolved;
  bool get isUnresolved => anchorStatus == AnchorStatus.unresolved;

  BookAnnotation copyWith({
    String? id,
    String? bookId,
    AnnotationType? type,
    String? selectedText,
    String? prefixContext,
    String? suffixContext,
    String? chapterId,
    String? anchorNodeId,
    int? startOffset,
    int? endOffset,
    int? pageIndex,
    List<Rect>? boundingBoxes,
    String? color,
    String? note,
    AnchorStatus? anchorStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BookAnnotation(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      type: type ?? this.type,
      selectedText: selectedText ?? this.selectedText,
      prefixContext: prefixContext ?? this.prefixContext,
      suffixContext: suffixContext ?? this.suffixContext,
      chapterId: chapterId ?? this.chapterId,
      anchorNodeId: anchorNodeId ?? this.anchorNodeId,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      pageIndex: pageIndex ?? this.pageIndex,
      boundingBoxes: boundingBoxes ?? this.boundingBoxes,
      color: color ?? this.color,
      note: note ?? this.note,
      anchorStatus: anchorStatus ?? this.anchorStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Construct from Drift [Highlight] row
  factory BookAnnotation.fromHighlight(Highlight h) {
    List<Rect> boxes = const [];
    if (h.boundingBoxesJson != null && h.boundingBoxesJson!.isNotEmpty) {
      try {
        final list = jsonDecode(h.boundingBoxesJson!) as List<dynamic>;
        boxes = list.map((item) {
          final m = item as Map<String, dynamic>;
          return Rect.fromLTWH(
            (m['left'] as num).toDouble(),
            (m['top'] as num).toDouble(),
            (m['width'] as num).toDouble(),
            (m['height'] as num).toDouble(),
          );
        }).toList();
      } catch (_) {}
    }

    AnchorStatus status = AnchorStatus.resolved;
    if (h.anchorStatus == 'unresolved') {
      status = AnchorStatus.unresolved;
    } else if (h.anchorStatus == 'approximate') {
      status = AnchorStatus.approximate;
    }

    final hasContentNote = h.note != null && h.note!.trim().isNotEmpty;

    return BookAnnotation(
      id: h.id,
      bookId: h.bookId,
      type: hasContentNote ? AnnotationType.note : AnnotationType.highlight,
      selectedText: h.selectedText,
      prefixContext: h.prefixContext,
      suffixContext: h.suffixContext,
      chapterId: h.chapterId,
      anchorNodeId: h.anchorNodeId,
      startOffset: h.startOffset,
      endOffset: h.endOffset,
      pageIndex: h.pageIndex ?? h.startPosition,
      boundingBoxes: boxes,
      color: h.color,
      note: h.note,
      anchorStatus: status,
      createdAt: h.createdAt,
      updatedAt: h.updatedAt,
    );
  }

  /// Construct from Drift [Bookmark] row
  factory BookAnnotation.fromBookmark(Bookmark b) {
    return BookAnnotation(
      id: b.id,
      bookId: b.bookId,
      type: AnnotationType.bookmark,
      selectedText: b.label,
      chapterId: b.chapterId,
      anchorNodeId: b.anchorNodeId,
      startOffset: b.characterOffset,
      endOffset: b.characterOffset,
      pageIndex: b.pageIndex ?? b.position,
      boundingBoxes: const [],
      color: 'gold',
      note: null,
      anchorStatus: AnchorStatus.resolved,
      createdAt: b.createdAt,
      updatedAt: b.updatedAt,
    );
  }

  /// Convert to [HighlightsCompanion] for Drift insertion/update
  HighlightsCompanion toHighlightCompanion() {
    final boxesJson = boundingBoxes.isNotEmpty
        ? jsonEncode(
            boundingBoxes
                .map((r) => {
                      'left': r.left,
                      'top': r.top,
                      'width': r.width,
                      'height': r.height,
                    })
                .toList(),
          )
        : null;

    final statusString = anchorStatus.name;

    return HighlightsCompanion(
      id: drift.Value(id),
      bookId: drift.Value(bookId),
      chapterId: drift.Value(chapterId),
      selectedText: drift.Value(selectedText),
      startPosition: drift.Value(pageIndex ?? 1),
      endPosition: drift.Value(pageIndex ?? 1),
      color: drift.Value(color),
      note: drift.Value(note),
      anchorNodeId: drift.Value(anchorNodeId),
      startOffset: drift.Value(startOffset),
      endOffset: drift.Value(endOffset),
      prefixContext: drift.Value(prefixContext),
      suffixContext: drift.Value(suffixContext),
      anchorVersion: const drift.Value(2),
      pageIndex: drift.Value(pageIndex),
      boundingBoxesJson: drift.Value(boxesJson),
      anchorStatus: drift.Value(statusString),
      createdAt: drift.Value(createdAt),
      updatedAt: drift.Value(updatedAt ?? DateTime.now()),
    );
  }

  /// Convert to [BookmarksCompanion] for Drift insertion/update
  BookmarksCompanion toBookmarkCompanion() {
    return BookmarksCompanion(
      id: drift.Value(id),
      bookId: drift.Value(bookId),
      chapterId: drift.Value(chapterId),
      position: drift.Value(pageIndex ?? 1),
      label: drift.Value(selectedText),
      anchorNodeId: drift.Value(anchorNodeId),
      characterOffset: drift.Value(startOffset),
      progressPercentage: const drift.Value(0.0),
      pageIndex: drift.Value(pageIndex),
      createdAt: drift.Value(createdAt),
      updatedAt: drift.Value(updatedAt ?? DateTime.now()),
    );
  }

  /// Convert to Drift [Highlight] data class
  Highlight toHighlight() {
    final boxesJson = boundingBoxes.isNotEmpty
        ? jsonEncode(
            boundingBoxes
                .map((r) => {
                      'left': r.left,
                      'top': r.top,
                      'width': r.width,
                      'height': r.height,
                    })
                .toList(),
          )
        : null;

    return Highlight(
      id: id,
      bookId: bookId,
      chapterId: chapterId,
      selectedText: selectedText,
      startPosition: pageIndex ?? 1,
      endPosition: pageIndex ?? 1,
      color: color,
      note: note,
      anchorNodeId: anchorNodeId,
      startOffset: startOffset,
      endOffset: endOffset,
      prefixContext: prefixContext,
      suffixContext: suffixContext,
      anchorVersion: 2,
      pageIndex: pageIndex,
      boundingBoxesJson: boxesJson,
      anchorStatus: anchorStatus.name,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Convert to Drift [Bookmark] data class
  Bookmark toBookmark() {
    return Bookmark(
      id: id,
      bookId: bookId,
      chapterId: chapterId,
      position: pageIndex ?? 1,
      label: selectedText,
      anchorNodeId: anchorNodeId,
      characterOffset: startOffset,
      progressPercentage: 0.0,
      createdAt: createdAt,
      pageIndex: pageIndex,
      updatedAt: updatedAt,
    );
  }
}
