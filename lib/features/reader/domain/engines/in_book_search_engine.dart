import 'dart:math' as math;
import '../models/reader_content.dart';

class InBookSearchResult {
  final String id;
  final int chapterIndex;
  final String chapterId;
  final String chapterTitle;
  final String nodeId;
  final int sourcePdfPage;
  final int startOffset;
  final int endOffset;
  final String matchedText;
  final String snippet;
  final String prefixContext;
  final String suffixContext;

  const InBookSearchResult({
    required this.id,
    required this.chapterIndex,
    required this.chapterId,
    required this.chapterTitle,
    required this.nodeId,
    required this.sourcePdfPage,
    required this.startOffset,
    required this.endOffset,
    required this.matchedText,
    required this.snippet,
    required this.prefixContext,
    required this.suffixContext,
  });

  @override
  String toString() =>
      'InBookSearchResult(chapter: $chapterIndex, node: $nodeId, offset: $startOffset..$endOffset, text: "$matchedText")';
}

class InBookSearchEngine {
  // In-memory cache of normalized searchable text per document:
  // bookId -> Map of (nodeId -> normalized lowercased text)
  static final Map<String, Map<String, String>> _documentCache = {};

  /// Clears search cache for a document or all documents
  static void clearCache([String? bookId]) {
    if (bookId != null) {
      _documentCache.remove(bookId);
    } else {
      _documentCache.clear();
    }
  }

  /// Searches all chapters in a ReaderDocument for the given query.
  /// Operates on normalized content models rather than rendered widgets.
  /// Checks [isCancelled] periodically to support cooperative cancellation of stale queries.
  static Future<List<InBookSearchResult>> search({
    required ReaderDocument document,
    required String query,
    int maxResults = 250,
    bool Function()? isCancelled,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final lowerQuery = cleanQuery.toLowerCase();
    final results = <InBookSearchResult>[];

    // Get or build cache
    final nodeCache = _documentCache.putIfAbsent(document.bookId, () {
      final cache = <String, String>{};
      for (final ch in document.chapters) {
        for (final node in ch.nodes) {
          if (node.type == ContentNodeType.image || node.text.isEmpty) continue;
          cache[node.id] = node.text.toLowerCase();
        }
      }
      return cache;
    });

    int matchIdCounter = 0;

    for (int chIdx = 0; chIdx < document.chapters.length; chIdx++) {
      if (isCancelled?.call() == true) return const [];

      final ch = document.chapters[chIdx];
      for (final node in ch.nodes) {
        if (node.type == ContentNodeType.image || node.text.isEmpty) continue;

        final rawText = node.text;
        final lowerText = nodeCache[node.id] ?? rawText.toLowerCase();

        int searchCursor = 0;
        while (searchCursor < lowerText.length) {
          if (isCancelled?.call() == true) return const [];
          if (results.length >= maxResults) return results;

          final foundIndex = lowerText.indexOf(lowerQuery, searchCursor);
          if (foundIndex == -1) break;

          final matchEnd = foundIndex + cleanQuery.length;
          final actualMatchedText = rawText.substring(foundIndex, matchEnd);

          // Build context & snippet
          const contextRadius = 40;
          final preStart = math.max(0, foundIndex - contextRadius);
          final postEnd = math.min(rawText.length, matchEnd + contextRadius);

          final prefix = rawText.substring(preStart, foundIndex);
          final suffix = rawText.substring(matchEnd, postEnd);

          final snippetLeading = preStart > 0 ? '…' : '';
          final snippetTrailing = postEnd < rawText.length ? '…' : '';
          final snippet =
              '$snippetLeading${prefix.replaceAll('\n', ' ')}$actualMatchedText${suffix.replaceAll('\n', ' ')}$snippetTrailing';

          matchIdCounter++;
          results.add(
            InBookSearchResult(
              id: 'sr_${ch.id}_${node.id}_$matchIdCounter',
              chapterIndex: chIdx,
              chapterId: ch.id,
              chapterTitle: ch.title,
              nodeId: node.id,
              sourcePdfPage: node.sourcePdfPage,
              startOffset: foundIndex,
              endOffset: matchEnd,
              matchedText: actualMatchedText,
              snippet: snippet,
              prefixContext: prefix,
              suffixContext: suffix,
            ),
          );

          searchCursor = matchEnd;
        }
      }
    }

    return results;
  }
}
