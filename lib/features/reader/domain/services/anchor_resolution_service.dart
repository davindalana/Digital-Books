import 'dart:convert';
import 'dart:math' as math;
import '../../../../core/database/app_database.dart';
import '../models/book_annotation.dart';
import '../models/reader_content.dart';
import '../models/search_geometry.dart';

/// Pure domain service responsible for resolving and synchronizing annotation anchors
/// across reading modes (Reflowable Paginated/Scrolling vs. Original PDF).
///
/// ARCHITECTURAL NOTE: This service resides in `domain/services/` because it operates
/// purely on in-memory domain models without performing disk, database, or network I/O.
/// Services performing disk/file I/O reside in `features/reader/services/`.
///
/// Follows a strict multi-tier fallback strategy:
/// 1. Exact semantic node & character offset match.
/// 2. Text + Prefix/Suffix context pattern matching within the chapter.
/// 3. Unambiguous exact text match within the chapter.
/// 4. Whole-document context matching.
/// 5. Unresolved fallback: flags explicitly as unresolved rather than shifting to incorrect text.
class AnchorResolutionService {
  /// Resolves an annotation's location within a [ReaderDocument].
  static BookAnnotation resolveInReflowableDocument({
    required BookAnnotation annotation,
    required ReaderDocument document,
  }) {
    if (annotation.isBookmark) {
      // Bookmarks resolve primarily by anchorNodeId or chapterId
      if (annotation.anchorNodeId != null &&
          annotation.anchorNodeId!.isNotEmpty) {
        final nodeExists = document.chapters.any(
          (ch) => ch.nodes.any((n) => n.id == annotation.anchorNodeId),
        );
        if (nodeExists) {
          return annotation.copyWith(anchorStatus: AnchorStatus.resolved);
        }
      }
      return annotation;
    }

    final queryText = annotation.selectedText.trim();
    if (queryText.isEmpty) {
      return annotation.copyWith(anchorStatus: AnchorStatus.unresolved);
    }

    // Tier 1: Exact Semantic Anchor Check
    if (annotation.anchorNodeId != null &&
        annotation.anchorNodeId!.isNotEmpty) {
      for (final ch in document.chapters) {
        for (final node in ch.nodes) {
          if (node.id == annotation.anchorNodeId) {
            final nodeText = node.text;
            if (annotation.startOffset >= 0 &&
                annotation.endOffset <= nodeText.length &&
                annotation.startOffset < annotation.endOffset) {
              final slice = nodeText.substring(
                annotation.startOffset,
                annotation.endOffset,
              );
              if (slice.trim() == queryText) {
                return annotation.copyWith(
                  chapterId: ch.id,
                  pageIndex: node.sourcePdfPage > 0
                      ? node.sourcePdfPage
                      : annotation.pageIndex,
                  anchorStatus: AnchorStatus.resolved,
                );
              }
            }

            // Offset shifted inside the same node?
            final firstOccur = nodeText.indexOf(queryText);
            if (firstOccur != -1) {
              final secondOccur = nodeText.indexOf(
                queryText,
                firstOccur + queryText.length,
              );
              // Only auto-resolve in Tier 1 if there is strictly ONE unambiguous occurrence in this node
              if (secondOccur == -1) {
                return annotation.copyWith(
                  chapterId: ch.id,
                  startOffset: firstOccur,
                  endOffset: firstOccur + queryText.length,
                  pageIndex: node.sourcePdfPage > 0
                      ? node.sourcePdfPage
                      : annotation.pageIndex,
                  anchorStatus: AnchorStatus.resolved,
                );
              }
            }
          }
        }
      }
    }

    // Tier 2: Text + Prefix/Suffix Context Matching within Chapter
    final targetChapterId = annotation.chapterId;
    final candidateChapters = targetChapterId != null
        ? document.chapters.where((c) => c.id == targetChapterId).toList()
        : document.chapters;

    final prefix = (annotation.prefixContext ?? '').trim();
    final suffix = (annotation.suffixContext ?? '').trim();

    if (prefix.isNotEmpty || suffix.isNotEmpty) {
      for (final ch in candidateChapters) {
        for (final node in ch.nodes) {
          final text = node.text;
          int cursor = 0;
          while (cursor < text.length) {
            final matchIdx = text.indexOf(queryText, cursor);
            if (matchIdx == -1) break;

            final preStart = math.max(0, matchIdx - prefix.length - 15);
            final localPrefix = text.substring(preStart, matchIdx);
            final matchEnd = matchIdx + queryText.length;
            final postEnd = math.min(
              text.length,
              matchEnd + suffix.length + 15,
            );
            final localSuffix = text.substring(matchEnd, postEnd);

            final prefixMatches =
                prefix.isEmpty || localPrefix.contains(prefix);
            final suffixMatches =
                suffix.isEmpty || localSuffix.contains(suffix);

            if (prefixMatches && suffixMatches) {
              return annotation.copyWith(
                chapterId: ch.id,
                anchorNodeId: node.id,
                startOffset: matchIdx,
                endOffset: matchEnd,
                pageIndex: node.sourcePdfPage > 0
                    ? node.sourcePdfPage
                    : annotation.pageIndex,
                anchorStatus: AnchorStatus.resolved,
              );
            }
            cursor = matchEnd;
          }
        }
      }
    }

    // Tier 3: Unambiguous Exact Text Match within Candidate Chapter
    for (final ch in candidateChapters) {
      final matches = <({ContentNode node, int start, int end})>[];
      for (final node in ch.nodes) {
        int cursor = 0;
        while (cursor < node.text.length) {
          final idx = node.text.indexOf(queryText, cursor);
          if (idx == -1) break;
          matches.add((node: node, start: idx, end: idx + queryText.length));
          cursor = idx + queryText.length;
        }
      }

      if (matches.length == 1) {
        final m = matches.first;
        return annotation.copyWith(
          chapterId: ch.id,
          anchorNodeId: m.node.id,
          startOffset: m.start,
          endOffset: m.end,
          pageIndex: m.node.sourcePdfPage > 0
              ? m.node.sourcePdfPage
              : annotation.pageIndex,
          anchorStatus: AnchorStatus.approximate,
        );
      }
    }

    // Tier 4: Global Search across entire Document
    final globalMatches =
        <({ReaderChapter ch, ContentNode node, int start, int end})>[];
    for (final ch in document.chapters) {
      for (final node in ch.nodes) {
        int cursor = 0;
        while (cursor < node.text.length) {
          final idx = node.text.indexOf(queryText, cursor);
          if (idx == -1) break;
          globalMatches.add((
            ch: ch,
            node: node,
            start: idx,
            end: idx + queryText.length,
          ));
          cursor = idx + queryText.length;
        }
      }
    }

    if (globalMatches.length == 1) {
      final m = globalMatches.first;
      return annotation.copyWith(
        chapterId: m.ch.id,
        anchorNodeId: m.node.id,
        startOffset: m.start,
        endOffset: m.end,
        pageIndex: m.node.sourcePdfPage > 0
            ? m.node.sourcePdfPage
            : annotation.pageIndex,
        anchorStatus: AnchorStatus.approximate,
      );
    }

    // Tier 5: Strictly Unresolved (Do NOT guess or place on random text)
    return annotation.copyWith(anchorStatus: AnchorStatus.unresolved);
  }

  /// Resolves an annotation's Original PDF page index and bounding boxes
  /// using stored [BookSearchPage] geometry.
  static BookAnnotation resolveInOriginalPdf({
    required BookAnnotation annotation,
    required List<BookSearchPage> indexedPages,
  }) {
    if (annotation.boundingBoxes.isNotEmpty && annotation.pageIndex != null) {
      // Already has valid bounding boxes
      return annotation.copyWith(anchorStatus: AnchorStatus.resolved);
    }

    final queryText = annotation.selectedText.trim();
    if (queryText.isEmpty) return annotation;

    final lowerQuery = queryText.toLowerCase();

    // Prioritize search on annotation.pageIndex if present
    final pagesToSearch = annotation.pageIndex != null
        ? indexedPages
              .where((p) => p.pageIndex == (annotation.pageIndex! - 1))
              .toList()
        : indexedPages;

    final effectivePages = pagesToSearch.isNotEmpty
        ? pagesToSearch
        : indexedPages;

    for (final page in effectivePages) {
      final lowerText = page.plainText.toLowerCase();
      final foundIdx = lowerText.indexOf(lowerQuery);
      if (foundIdx != -1) {
        final matchEnd = foundIdx + queryText.length;

        // Parse token geometry from page
        final tokens = <SearchTokenGeometry>[];
        if (page.geometryJson.isNotEmpty) {
          try {
            final raw = jsonDecode(page.geometryJson) as List<dynamic>;
            tokens.addAll(
              raw.map(
                (j) => SearchTokenGeometry.fromJson(j as Map<String, dynamic>),
              ),
            );
          } catch (_) {}
        }

        final intersectingBoxes = tokens
            .where((t) => t.start < matchEnd && t.end > foundIdx)
            .map((t) => t.box)
            .toList();

        final pageNumber = page.pageIndex + 1; // 1-based page index
        return annotation.copyWith(
          pageIndex: pageNumber,
          boundingBoxes: intersectingBoxes,
          anchorStatus: intersectingBoxes.isNotEmpty
              ? AnchorStatus.resolved
              : AnchorStatus.approximate,
        );
      }
    }

    // If no bounding boxes could be found, preserve whatever coordinates exist
    return annotation;
  }
}
