import 'reader_content.dart';

class TocItem {
  final String id;
  final String title;
  final int level;
  final int chapterIndex;
  final String chapterId;
  final String anchorNodeId;
  final int sourcePdfPage;
  final List<TocItem> children;

  const TocItem({
    required this.id,
    required this.title,
    this.level = 1,
    required this.chapterIndex,
    required this.chapterId,
    required this.anchorNodeId,
    this.sourcePdfPage = 1,
    this.children = const [],
  });

  bool get hasChildren => children.isNotEmpty;

  TocItem copyWith({
    String? id,
    String? title,
    int? level,
    int? chapterIndex,
    String? chapterId,
    String? anchorNodeId,
    int? sourcePdfPage,
    List<TocItem>? children,
  }) {
    return TocItem(
      id: id ?? this.id,
      title: title ?? this.title,
      level: level ?? this.level,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterId: chapterId ?? this.chapterId,
      anchorNodeId: anchorNodeId ?? this.anchorNodeId,
      sourcePdfPage: sourcePdfPage ?? this.sourcePdfPage,
      children: children ?? this.children,
    );
  }
}

class TocHierarchyBuilder {
  /// Builds a hierarchical list of TocItem from a ReaderDocument.
  /// Preserves chapter structure and nests subsequent headings (H2, H3) cleanly.
  static List<TocItem> buildFromDocument(ReaderDocument document) {
    if (document.chapters.isEmpty) return const [];

    final result = <TocItem>[];

    for (int chIdx = 0; chIdx < document.chapters.length; chIdx++) {
      final ch = document.chapters[chIdx];
      final firstNodeId = ch.nodes.isNotEmpty ? ch.nodes.first.id : ch.id;
      final firstPage = ch.nodes.isNotEmpty
          ? ch.nodes.first.sourcePdfPage
          : (chIdx + 1);

      // Collect headings inside this chapter
      final subItems = <TocItem>[];
      bool isFirstNode = true;

      for (int nIdx = 0; nIdx < ch.nodes.length; nIdx++) {
        final node = ch.nodes[nIdx];
        if (node.type == ContentNodeType.heading) {
          final trimmedText = node.text.trim();
          // If the first heading exactly equals the chapter title, skip duplicating as child
          if (isFirstNode &&
              trimmedText.toLowerCase() == ch.title.trim().toLowerCase()) {
            isFirstNode = false;
            continue;
          }
          isFirstNode = false;

          subItems.add(
            TocItem(
              id: node.id,
              title: trimmedText.isNotEmpty
                  ? trimmedText
                  : 'Bagian ${subItems.length + 1}',
              level: node.level > 1 ? node.level : 2,
              chapterIndex: chIdx,
              chapterId: ch.id,
              anchorNodeId: node.id,
              sourcePdfPage: node.sourcePdfPage,
            ),
          );
        } else {
          isFirstNode = false;
        }
      }

      result.add(
        TocItem(
          id: ch.id,
          title: ch.title.trim().isNotEmpty
              ? ch.title.trim()
              : 'Bab ${chIdx + 1}',
          level: 1,
          chapterIndex: chIdx,
          chapterId: ch.id,
          anchorNodeId: firstNodeId,
          sourcePdfPage: firstPage,
          children: subItems,
        ),
      );
    }

    return result;
  }

  /// Finds the TocItem matching the given anchorNodeId, or closest preceding item.
  static TocItem? findActiveItem({
    required List<TocItem> items,
    required int currentChapterIndex,
    String? currentAnchorNodeId,
  }) {
    if (items.isEmpty) return null;

    // Search in current chapter first
    final currentChItem = items.firstWhere(
      (item) => item.chapterIndex == currentChapterIndex,
      orElse: () => items[currentChapterIndex.clamp(0, items.length - 1)],
    );

    if (currentAnchorNodeId == null || currentAnchorNodeId.isEmpty) {
      return currentChItem;
    }

    // Check children first (more specific heading)
    for (final child in currentChItem.children) {
      if (child.anchorNodeId == currentAnchorNodeId) {
        return child;
      }
    }

    if (currentChItem.anchorNodeId == currentAnchorNodeId) {
      return currentChItem;
    }

    // Fallback to chapter level
    return currentChItem;
  }
}
