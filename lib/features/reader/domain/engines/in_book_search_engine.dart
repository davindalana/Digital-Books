import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_service.dart';
import '../models/reader_content.dart';
import '../models/search_geometry.dart';

class InBookSearchResult {
  final String id;
  final int chapterIndex;
  final String chapterId;
  final String chapterTitle;
  final String nodeId;
  final int sourcePdfPage; // 1-based page number
  final int startOffset;
  final int endOffset;
  final String matchedText;
  final String snippet;
  final String prefixContext;
  final String suffixContext;
  final List<Rect> boundingBoxes; // Normalized [0, 1] bounding boxes for PDF highlighting
  final bool isCrossPage; // True if match spans page boundary
  final bool isOcr; // True if from OCR extraction

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
    this.boundingBoxes = const [],
    this.isCrossPage = false,
    this.isOcr = false,
  });

  @override
  String toString() =>
      'InBookSearchResult(page: $sourcePdfPage, chapter: $chapterIndex, node: $nodeId, offset: $startOffset..$endOffset, text: "$matchedText", boxes: ${boundingBoxes.length})';
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
              boundingBoxes: const [],
              isCrossPage: false,
              isOcr: false,
            ),
          );

          searchCursor = matchEnd;
        }
      }
    }

    return results;
  }

  /// Searches indexed book pages stored in Drift database.
  ///
  /// - Case-insensitive substring and phrase matching.
  /// - Normalizes whitespace and query hyphens.
  /// - Dehyphenation aware: matches words split across line breaks.
  /// - Detects cross-page phrase boundaries.
  /// - Filters running headers/footers if [includeChrome] is false.
  /// - Maps matching offsets to normalized bounding boxes via [SearchTokenGeometry].
  /// - Maps to [ReaderDocument] chapters and nodes if [readerDocument] is supplied.
  /// - Ordered strictly by [sourcePdfPage] ascending and [startOffset] ascending.
  static Future<List<InBookSearchResult>> searchIndexedBook({
    required String bookId,
    required DatabaseService dbService,
    required String query,
    ReaderDocument? readerDocument,
    bool includeChrome = false,
    int maxResults = 250,
    bool Function()? isCancelled,
  }) async {
    final rawQuery = query.trim();
    if (rawQuery.isEmpty) return const [];

    // Normalize query whitespace: collapse multiple spaces/newlines into single space
    final normalizedQuery = rawQuery.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedQuery.isEmpty) return const [];
    final lowerQuery = normalizedQuery.toLowerCase();
    // Also prepare dehyphenated query variant (e.g. "men-jadi" -> "menjadi")
    final dehyphenatedQuery = lowerQuery.replaceAll('-', '');

    final pages = await dbService.getSearchPagesForBook(bookId);
    if (pages.isEmpty) {
      // If no indexed pages exist, fall back to in-memory search if readerDocument exists
      if (readerDocument != null) {
        return search(
          document: readerDocument,
          query: rawQuery,
          maxResults: maxResults,
          isCancelled: isCancelled,
        );
      }
      return const [];
    }

    final results = <InBookSearchResult>[];
    int matchIdCounter = 0;

    // Cache parsed tokens per page to avoid redundant JSON decoding
    final parsedTokensPerPage = <int, List<SearchTokenGeometry>>{};

    List<SearchTokenGeometry> getTokens(BookSearchPage page) {
      return parsedTokensPerPage.putIfAbsent(page.pageIndex, () {
        if (page.geometryJson.isEmpty) return const [];
        try {
          final list = jsonDecode(page.geometryJson) as List<dynamic>;
          return list
              .map((item) =>
                  SearchTokenGeometry.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (_) {
          return const [];
        }
      });
    }

    // Pass 1: Intra-page search
    for (int p = 0; p < pages.length; p++) {
      if (isCancelled?.call() == true) return const [];
      if (results.length >= maxResults) break;

      final page = pages[p];
      final plainText = page.plainText;
      if (plainText.isEmpty) continue;

      final lowerPageText = plainText.toLowerCase();
      final tokens = getTokens(page);

      int searchCursor = 0;
      while (searchCursor < lowerPageText.length) {
        if (isCancelled?.call() == true) return const [];
        if (results.length >= maxResults) break;

        // Try primary query first, or dehyphenated query if distinct
        int foundIndex = lowerPageText.indexOf(lowerQuery, searchCursor);
        int matchedLen = lowerQuery.length;

        if (foundIndex == -1 &&
            dehyphenatedQuery != lowerQuery &&
            dehyphenatedQuery.length >= 2) {
          foundIndex = lowerPageText.indexOf(dehyphenatedQuery, searchCursor);
          matchedLen = dehyphenatedQuery.length;
        }

        if (foundIndex == -1) break;

        final matchEnd = foundIndex + matchedLen;
        final actualMatchedText = plainText.substring(foundIndex, matchEnd);

        // Find intersecting tokens for bounding boxes
        final intersectingTokens = tokens.where((t) {
          // Token intersects [foundIndex, matchEnd]
          return t.start < matchEnd && t.end > foundIndex;
        }).toList();

        // Chrome filtering
        if (!includeChrome &&
            intersectingTokens.isNotEmpty &&
            intersectingTokens.every((t) => t.isChrome)) {
          searchCursor = matchEnd;
          continue;
        }

        final boxes = intersectingTokens.map((t) => t.box).toList();

        // Build context snippet
        const contextRadius = 40;
        final preStart = math.max(0, foundIndex - contextRadius);
        final postEnd = math.min(plainText.length, matchEnd + contextRadius);

        final prefix = plainText.substring(preStart, foundIndex);
        final suffix = plainText.substring(matchEnd, postEnd);

        final snippetLeading = preStart > 0 ? '…' : '';
        final snippetTrailing = postEnd < plainText.length ? '…' : '';
        final snippet =
            '$snippetLeading${prefix.replaceAll('\n', ' ')}$actualMatchedText${suffix.replaceAll('\n', ' ')}$snippetTrailing';

        final sourcePdfPage = page.pageIndex + 1; // 1-based page
        matchIdCounter++;

        // Map to ReaderDocument if available
        int chapterIdx = 0;
        String chapterId = '';
        String chapterTitle = 'Halaman $sourcePdfPage';
        String nodeId = 'p_$sourcePdfPage';
        int nodeStartOffset = foundIndex;
        int nodeEndOffset = matchEnd;

        if (readerDocument != null) {
          final mapped = _mapToReaderDocument(
            readerDocument: readerDocument,
            sourcePdfPage: sourcePdfPage,
            matchedText: actualMatchedText,
            prefix: prefix,
          );
          if (mapped != null) {
            chapterIdx = mapped.chapterIndex;
            chapterId = mapped.chapterId;
            chapterTitle = mapped.chapterTitle;
            nodeId = mapped.nodeId;
            nodeStartOffset = mapped.startOffset;
            nodeEndOffset = mapped.endOffset;
          }
        }

        results.add(
          InBookSearchResult(
            id: 'idx_${bookId}_p${sourcePdfPage}_$matchIdCounter',
            chapterIndex: chapterIdx,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            nodeId: nodeId,
            sourcePdfPage: sourcePdfPage,
            startOffset: nodeStartOffset,
            endOffset: nodeEndOffset,
            matchedText: actualMatchedText,
            snippet: snippet,
            prefixContext: prefix,
            suffixContext: suffix,
            boundingBoxes: boxes,
            isCrossPage: false,
            isOcr: page.isOcr,
          ),
        );

        searchCursor = matchEnd;
      }
    }

    // Pass 2: Cross-page phrase search (e.g. query with spaces spanning page N and page N+1)
    if (lowerQuery.contains(' ') && pages.length >= 2) {
      final queryWords = lowerQuery.split(' ');
      for (int p = 0; p < pages.length - 1; p++) {
        if (isCancelled?.call() == true) return const [];
        if (results.length >= maxResults) break;

        final pageA = pages[p];
        final pageB = pages[p + 1];
        if (pageA.plainText.isEmpty || pageB.plainText.isEmpty) continue;

        // Check if query is split across pageA tail and pageB head
        for (int splitIdx = 1; splitIdx < queryWords.length; splitIdx++) {
          final prefixWords = queryWords.sublist(0, splitIdx).join(' ');
          final suffixWords = queryWords.sublist(splitIdx).join(' ');

          final lowerA = pageA.plainText.toLowerCase();
          final lowerB = pageB.plainText.toLowerCase();

          if (lowerA.endsWith(prefixWords) && lowerB.startsWith(suffixWords)) {
            final startOffsetA = lowerA.length - prefixWords.length;
            final endOffsetB = suffixWords.length;

            final matchedTextA = pageA.plainText.substring(startOffsetA);
            final matchedTextB = pageB.plainText.substring(0, endOffsetB);
            final combinedMatch = '$matchedTextA $matchedTextB';

            final tokensA = getTokens(pageA);
            final tokensB = getTokens(pageB);

            final boxesA = tokensA
                .where((t) => t.start < lowerA.length && t.end > startOffsetA)
                .map((t) => t.box)
                .toList();
            final boxesB = tokensB
                .where((t) => t.start < endOffsetB && t.end > 0)
                .map((t) => t.box)
                .toList();

            final preContextStart = math.max(0, startOffsetA - 30);
            final postContextEnd = math.min(lowerB.length, endOffsetB + 30);

            final prefixContext =
                pageA.plainText.substring(preContextStart, startOffsetA);
            final suffixContext =
                pageB.plainText.substring(endOffsetB, postContextEnd);
            final snippet = '…$prefixContext$combinedMatch$suffixContext…';

            final sourcePdfPage = pageA.pageIndex + 1;
            matchIdCounter++;

            results.add(
              InBookSearchResult(
                id: 'crosspage_${bookId}_p${sourcePdfPage}_$matchIdCounter',
                chapterIndex: 0,
                chapterId: '',
                chapterTitle: 'Halaman $sourcePdfPage–${sourcePdfPage + 1}',
                nodeId: 'p_$sourcePdfPage',
                sourcePdfPage: sourcePdfPage,
                startOffset: startOffsetA,
                endOffset: lowerA.length,
                matchedText: combinedMatch,
                snippet: snippet,
                prefixContext: prefixContext,
                suffixContext: suffixContext,
                boundingBoxes: [...boxesA, ...boxesB],
                isCrossPage: true,
                isOcr: pageA.isOcr || pageB.isOcr,
              ),
            );
          }
        }
      }
    }

    // Sort results logically by page ascending, then startOffset ascending
    results.sort((a, b) {
      final pageComp = a.sourcePdfPage.compareTo(b.sourcePdfPage);
      if (pageComp != 0) return pageComp;
      return a.startOffset.compareTo(b.startOffset);
    });

    return results;
  }

  static ({
    int chapterIndex,
    String chapterId,
    String chapterTitle,
    String nodeId,
    int startOffset,
    int endOffset,
  })? _mapToReaderDocument({
    required ReaderDocument readerDocument,
    required int sourcePdfPage,
    required String matchedText,
    required String prefix,
  }) {
    final lowerMatched = matchedText.toLowerCase();

    for (int chIdx = 0; chIdx < readerDocument.chapters.length; chIdx++) {
      final ch = readerDocument.chapters[chIdx];
      for (final node in ch.nodes) {
        if (node.sourcePdfPage != sourcePdfPage) continue;
        if (node.type == ContentNodeType.image || node.text.isEmpty) continue;

        final nodeLower = node.text.toLowerCase();
        final found = nodeLower.indexOf(lowerMatched);
        if (found != -1) {
          return (
            chapterIndex: chIdx,
            chapterId: ch.id,
            chapterTitle: ch.title,
            nodeId: node.id,
            startOffset: found,
            endOffset: found + lowerMatched.length,
          );
        }
      }
    }
    return null;
  }
}
