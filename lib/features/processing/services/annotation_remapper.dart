import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../reader/domain/models/book_document.dart';

/// Result of relocating user annotations from an old processed document to a
/// newly reconstructed one.
class AnnotationRemapResult {
  final List<BookmarksCompanion> bookmarkUpdates;
  final List<HighlightsCompanion> highlightUpdates;
  final ReadingProgressesCompanion? progressUpdate;
  final int relocatedBookmarks;
  final int relocatedHighlights;
  final int unresolvedHighlights;
  final int unresolvedBookmarks;
  final bool progressMapped;

  const AnnotationRemapResult({
    required this.bookmarkUpdates,
    required this.highlightUpdates,
    required this.progressUpdate,
    required this.relocatedBookmarks,
    required this.relocatedHighlights,
    required this.unresolvedHighlights,
    required this.unresolvedBookmarks,
    required this.progressMapped,
  });
}

/// Relocates bookmarks, highlights, and reading progress by content, never by
/// regenerated UUIDs alone.
///
/// The reconstruction pipeline creates fresh block/chapter IDs on every run.
/// Deleting or orphaning annotations because of that would be data loss, so the
/// remapper searches the new document by selected text, prefix/suffix context,
/// source page, and chapter title. Unresolved annotations are kept and marked
/// `unresolved` instead of being removed.
class AnnotationRemapper {
  static AnnotationRemapResult remap({
    required BookDocument oldDocument,
    required BookDocument newDocument,
    required List<Bookmark> bookmarks,
    required List<Highlight> highlights,
    ReadingProgress? progress,
  }) {
    final oldIndex = _DocumentIndex(oldDocument);
    final newIndex = _DocumentIndex(newDocument);

    final bookmarkUpdates = <BookmarksCompanion>[];
    var relocatedBookmarks = 0;
    var unresolvedBookmarks = 0;

    for (final bookmark in bookmarks) {
      final match = _findBookmarkAnchor(
        bookmark: bookmark,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      if (match == null) {
        unresolvedBookmarks++;
        bookmarkUpdates.add(
          BookmarksCompanion(
            id: Value(bookmark.id),
            pageIndex: Value(bookmark.pageIndex),
          ),
        );
        continue;
      }

      relocatedBookmarks++;
      bookmarkUpdates.add(
        BookmarksCompanion(
          id: Value(bookmark.id),
          chapterId: Value(match.chapterId),
          anchorNodeId: Value(match.block.id),
          characterOffset: Value(match.offset),
          pageIndex: Value(match.block.pageNumber),
        ),
      );
    }

    final highlightUpdates = <HighlightsCompanion>[];
    var relocatedHighlights = 0;
    var unresolvedHighlights = 0;

    for (final highlight in highlights) {
      final match = _findHighlightAnchor(
        highlight: highlight,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      if (match == null) {
        unresolvedHighlights++;
        highlightUpdates.add(
          HighlightsCompanion(
            id: Value(highlight.id),
            anchorStatus: const Value('unresolved'),
          ),
        );
        continue;
      }

      relocatedHighlights++;
      highlightUpdates.add(
        HighlightsCompanion(
          id: Value(highlight.id),
          chapterId: Value(match.chapterId),
          anchorNodeId: Value(match.block.id),
          startOffset: Value(match.offset),
          endOffset: Value(match.offset + match.length),
          pageIndex: Value(match.block.pageNumber),
          anchorStatus: const Value('resolved'),
        ),
      );
    }

    final progressUpdate = progress == null
        ? null
        : _remapProgress(
            progress: progress,
            oldDocument: oldDocument,
            newDocument: newDocument,
          );

    return AnnotationRemapResult(
      bookmarkUpdates: bookmarkUpdates,
      highlightUpdates: highlightUpdates,
      progressUpdate: progressUpdate,
      relocatedBookmarks: relocatedBookmarks,
      relocatedHighlights: relocatedHighlights,
      unresolvedHighlights: unresolvedHighlights,
      unresolvedBookmarks: unresolvedBookmarks,
      progressMapped: progressUpdate != null,
    );
  }

  static _AnchorMatch? _findBookmarkAnchor({
    required Bookmark bookmark,
    required _DocumentIndex oldIndex,
    required _DocumentIndex newIndex,
  }) {
    if (bookmark.anchorNodeId != null) {
      final exact = newIndex.byId[bookmark.anchorNodeId!];
      if (exact != null) {
        return _AnchorMatch(
          block: exact,
          chapterId: exact.chapterId,
          offset: bookmark.characterOffset.clamp(0, exact.text.length),
          length: 0,
        );
      }
    }

    final oldBlock = bookmark.anchorNodeId == null
        ? null
        : oldIndex.byId[bookmark.anchorNodeId!];
    if (oldBlock != null) {
      final sameText = newIndex.findByText(
        oldBlock.text,
        preferredPage: oldBlock.block.originalPageNumber,
        preferredChapterTitle: oldBlock.chapterTitle,
      );
      if (sameText != null) {
        return _AnchorMatch(
          block: sameText,
          chapterId: sameText.chapterId,
          offset: bookmark.characterOffset.clamp(0, sameText.text.length),
          length: 0,
        );
      }
    }

    // Last resort: the first readable block on the recorded source page.
    final page = bookmark.pageIndex;
    if (page != null) {
      final onPage = newIndex.blocks
          .where((b) => b.block.originalPageNumber == page && b.hasText)
          .toList();
      if (onPage.isNotEmpty) {
        return _AnchorMatch(
          block: onPage.first,
          chapterId: onPage.first.chapterId,
          offset: 0,
          length: 0,
        );
      }
    }
    return null;
  }

  static _AnchorMatch? _findHighlightAnchor({
    required Highlight highlight,
    required _DocumentIndex oldIndex,
    required _DocumentIndex newIndex,
  }) {
    if (highlight.anchorNodeId != null) {
      final exact = newIndex.byId[highlight.anchorNodeId!];
      if (exact != null) {
        final start = highlight.startOffset.clamp(0, exact.text.length);
        final end = highlight.endOffset.clamp(start, exact.text.length);
        return _AnchorMatch(
          block: exact,
          chapterId: exact.chapterId,
          offset: start,
          length: end - start,
        );
      }
    }

    final oldBlock = highlight.anchorNodeId == null
        ? null
        : oldIndex.byId[highlight.anchorNodeId!];
    final preferredPage =
        highlight.pageIndex ?? oldBlock?.block.originalPageNumber;
    final preferredChapter = oldBlock?.chapterTitle;

    final selected = highlight.selectedText;
    if (selected.isNotEmpty) {
      final direct = newIndex.findByText(
        selected,
        preferredPage: preferredPage,
        preferredChapterTitle: preferredChapter,
      );
      if (direct != null) {
        final offset = direct.text.indexOf(selected);
        if (offset >= 0) {
          return _AnchorMatch(
            block: direct,
            chapterId: direct.chapterId,
            offset: offset,
            length: selected.length,
          );
        }
      }

      final contextual = _findByContext(highlight, newIndex);
      if (contextual != null) return contextual;

      final normalized = newIndex.findByNormalizedText(
        selected,
        preferredPage: preferredPage,
        preferredChapterTitle: preferredChapter,
      );
      if (normalized != null) {
        return _AnchorMatch(
          block: normalized.block,
          chapterId: normalized.block.chapterId,
          offset: normalized.offset,
          length: normalized.length,
        );
      }
    }

    return null;
  }

  static _AnchorMatch? _findByContext(
    Highlight highlight,
    _DocumentIndex newIndex,
  ) {
    final prefix = highlight.prefixContext;
    final suffix = highlight.suffixContext;
    final selected = highlight.selectedText;
    if (selected.isEmpty || (prefix == null && suffix == null)) return null;

    for (final block in newIndex.blocks) {
      if (!block.hasText) continue;
      final index = block.text.indexOf(selected);
      if (index < 0) continue;
      final before = index == 0 ? '' : block.text.substring(0, index);
      final after = block.text.substring(index + selected.length);
      final prefixOk =
          prefix == null || prefix.isEmpty || before.endsWith(prefix);
      final suffixOk =
          suffix == null || suffix.isEmpty || after.startsWith(suffix);
      if (prefixOk && suffixOk) {
        return _AnchorMatch(
          block: block,
          chapterId: block.chapterId,
          offset: index,
          length: selected.length,
        );
      }
    }
    return null;
  }

  static ReadingProgressesCompanion? _remapProgress({
    required ReadingProgress progress,
    required BookDocument oldDocument,
    required BookDocument newDocument,
  }) {
    if (newDocument.chapters.isEmpty) return null;

    int? newChapterIndex;
    if (oldDocument.chapters.isNotEmpty) {
      final oldIndex = progress.currentChapter.clamp(
        0,
        oldDocument.chapters.length - 1,
      );
      final oldTitle = _normalizeTitle(oldDocument.chapters[oldIndex].title);
      newChapterIndex = newDocument.chapters.indexWhere(
        (c) => _normalizeTitle(c.title) == oldTitle,
      );
      if (newChapterIndex < 0 && oldIndex < newDocument.chapters.length) {
        newChapterIndex = oldIndex;
      }
    }
    newChapterIndex ??= 0;

    final oldChapter = oldDocument.chapters.isNotEmpty
        ? oldDocument.chapters[progress.currentChapter.clamp(
            0,
            oldDocument.chapters.length - 1,
          )]
        : null;
    final newChapter = newDocument.chapters[newChapterIndex];
    var newPosition = progress.currentPosition;

    if (oldChapter != null && oldChapter.blocks.isNotEmpty) {
      final oldBlockIndex = progress.currentPosition.clamp(
        0,
        oldChapter.blocks.length - 1,
      );
      final anchorText = oldChapter.blocks[oldBlockIndex].text.trim();
      if (anchorText.isNotEmpty) {
        final located = newChapter.blocks.indexWhere(
          (b) => b.text.trim() == anchorText,
        );
        if (located >= 0) {
          newPosition = located;
        } else {
          newPosition =
              (oldBlockIndex /
                      oldChapter.blocks.length *
                      newChapter.blocks.length)
                  .round();
        }
      }
    }
    newPosition = newPosition.clamp(
      0,
      newChapter.blocks.isEmpty ? 0 : newChapter.blocks.length - 1,
    );

    return ReadingProgressesCompanion(
      id: Value(progress.id),
      bookId: Value(progress.bookId),
      currentChapter: Value(newChapterIndex),
      currentPosition: Value(newPosition),
      progressPercentage: Value(progress.progressPercentage),
      lastReadingMode: Value(progress.lastReadingMode),
      lastReadAt: Value(progress.lastReadAt),
    );
  }
}

class _DocumentIndex {
  final List<_BlockRef> blocks;
  final Map<String, _BlockRef> byId;

  _DocumentIndex(BookDocument document)
    : blocks = _flatten(document),
      byId = {for (final ref in _flatten(document)) ref.block.id: ref};

  static List<_BlockRef> _flatten(BookDocument document) {
    final refs = <_BlockRef>[];
    for (final chapter in document.chapters) {
      for (var i = 0; i < chapter.blocks.length; i++) {
        refs.add(
          _BlockRef(
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            block: chapter.blocks[i],
            indexInChapter: i,
          ),
        );
      }
    }
    return refs;
  }

  _BlockRef? findByText(
    String text, {
    int? preferredPage,
    String? preferredChapterTitle,
  }) {
    final needle = text.trim();
    if (needle.isEmpty) return null;
    return _bestMatch(
      (block) => block.text.trim() == needle,
      preferredPage: preferredPage,
      preferredChapterTitle: preferredChapterTitle,
    );
  }

  _NormalizedMatch? findByNormalizedText(
    String text, {
    int? preferredPage,
    String? preferredChapterTitle,
  }) {
    final needle = _normalizeText(text);
    if (needle.isEmpty) return null;

    final candidates = blocks.where((b) {
      final normalized = _normalizeText(b.text);
      return normalized.contains(needle);
    }).toList();
    if (candidates.isEmpty) return null;

    candidates.sort(
      (a, b) => _score(
        b,
        preferredPage,
        preferredChapterTitle,
      ).compareTo(_score(a, preferredPage, preferredChapterTitle)),
    );
    final best = candidates.first;
    final normalizedBlock = _normalizeText(best.text);
    final offset = normalizedBlock.indexOf(needle);
    return _NormalizedMatch(
      block: best,
      offset: offset < 0 ? 0 : offset,
      length: needle.length,
    );
  }

  _BlockRef? _bestMatch(
    bool Function(_BlockRef) predicate, {
    int? preferredPage,
    String? preferredChapterTitle,
  }) {
    final candidates = blocks.where(predicate).toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => _score(
        b,
        preferredPage,
        preferredChapterTitle,
      ).compareTo(_score(a, preferredPage, preferredChapterTitle)),
    );
    return candidates.first;
  }

  int _score(_BlockRef block, int? page, String? chapterTitle) {
    var score = 0;
    if (page != null && block.block.originalPageNumber == page) score += 4;
    if (chapterTitle != null &&
        _normalizeTitle(block.chapterTitle) == _normalizeTitle(chapterTitle)) {
      score += 2;
    }
    return score;
  }
}

class _BlockRef {
  final String chapterId;
  final String chapterTitle;
  final BookBlock block;
  final int indexInChapter;

  const _BlockRef({
    required this.chapterId,
    required this.chapterTitle,
    required this.block,
    required this.indexInChapter,
  });

  String get text => block.text;
  String get id => block.id;
  int get pageNumber => block.originalPageNumber;
  bool get hasText => block.text.trim().isNotEmpty;
}

class _AnchorMatch {
  final _BlockRef block;
  final String chapterId;
  final int offset;
  final int length;

  const _AnchorMatch({
    required this.block,
    required this.chapterId,
    required this.offset,
    required this.length,
  });
}

class _NormalizedMatch {
  final _BlockRef block;
  final int offset;
  final int length;

  const _NormalizedMatch({
    required this.block,
    required this.offset,
    required this.length,
  });
}

String _normalizeText(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

String _normalizeTitle(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ').trim();
