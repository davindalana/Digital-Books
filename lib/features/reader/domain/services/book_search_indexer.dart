import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect, Size;
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/utils/file_storage_service.dart';
import '../../../processing/models/ocr_page_result.dart';
import '../models/search_geometry.dart';

/// Service responsible for extracting, normalizing, and indexing searchable text
/// and bounding-box geometry for both OCR scanned pages and digital PDF pages.
class BookSearchIndexer {
  static const int currentVersion = 1;

  final DatabaseService dbService;

  const BookSearchIndexer({required this.dbService});

  /// Indexes a single book into [BookSearchPages] table.
  ///
  /// - Automatically verifies PDF SHA-256 freshness and invalidates stale indexes.
  /// - Skips already indexed pages (resumable).
  /// - Prefers completed OCR text if available; otherwise uses digital text layer if available.
  /// - Dehyphenates word breaks across lines while mapping geometry to both fragments.
  /// - Filters running headers and page numbers to eliminate search noise.
  Future<int> indexBook({
    required String bookId,
    required String pdfPath,
    int? startPage,
    int? endPage,
    void Function(int current, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final file = File(pdfPath);
    if (!file.existsSync()) return 0;

    final currentHash = await FileStorageService.computeFileSha256(file);
    final book = await dbService.getBookById(bookId);

    // Staleness check: Invalidate index if PDF file has been replaced/modified
    if (book != null && book.fileHash != null && book.fileHash != currentHash) {
      await dbService.deleteSearchPagesForBook(bookId);
      await dbService.insertBook(
        book
            .toCompanion(true)
            .copyWith(
              fileHash: drift.Value(currentHash),
              updatedAt: drift.Value(DateTime.now()),
            ),
      );
    }

    final bytes = await file.readAsBytes();
    final sfDoc = sf.PdfDocument(inputBytes: bytes);
    final totalBookPages = sfDoc.pages.count;
    final sfExtractor = sf.PdfTextExtractor(sfDoc);

    final effectiveStart = (startPage ?? 0).clamp(0, totalBookPages - 1);
    final effectiveEnd = (endPage ?? (totalBookPages - 1)).clamp(
      effectiveStart,
      totalBookPages - 1,
    );
    final targetCount = effectiveEnd - effectiveStart + 1;

    // Check existing indexed pages
    final existingPages = await dbService.getSearchPagesForBook(bookId);
    final indexedSet = existingPages
        .where(
          (p) => p.fileHash == currentHash && p.indexVersion == currentVersion,
        )
        .map((p) => p.pageIndex)
        .toSet();

    // Check existing OCR completed pages
    final ocrPages = await dbService.getOcrPagesForBook(bookId);
    final ocrMap = {
      for (final p in ocrPages)
        if (p.status == 'completed') p.pageIndex: p,
    };

    int newlyIndexed = 0;

    for (int pIdx = effectiveStart; pIdx <= effectiveEnd; pIdx++) {
      if (isCancelled?.call() == true) break;

      onProgress?.call(pIdx - effectiveStart + 1, targetCount);

      if (indexedSet.contains(pIdx)) {
        continue;
      }

      final sfPage = sfDoc.pages[pIdx];
      final pageSize = Size(sfPage.size.width, sfPage.size.height);

      if (ocrMap.containsKey(pIdx)) {
        // Source A: Scanned page with completed Apple Vision OCR
        final ocrPage = ocrMap[pIdx]!;
        final lines = (jsonDecode(ocrPage.linesJson) as List<dynamic>)
            .map((item) => OcrLine.fromJson(item as Map<String, dynamic>))
            .toList();

        final pageIndexData = _processOcrLines(lines, pageSize);
        final companion = BookSearchPagesCompanion(
          id: drift.Value('${bookId}_p$pIdx'),
          bookId: drift.Value(bookId),
          pageIndex: drift.Value(pIdx),
          plainText: drift.Value(pageIndexData.plainText),
          rawText: drift.Value(pageIndexData.rawText),
          geometryJson: drift.Value(
            jsonEncode(pageIndexData.tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(true),
          fileHash: drift.Value(currentHash),
          indexVersion: const drift.Value(currentVersion),
          indexedAt: drift.Value(DateTime.now()),
        );
        await dbService.insertSearchPage(companion);
        newlyIndexed++;
      } else {
        // Source B: Check digital selectable text layer
        final rawLines = sfExtractor.extractTextLines(
          startPageIndex: pIdx,
          endPageIndex: pIdx,
        );

        if (rawLines.isNotEmpty) {
          final pageIndexData = _processDigitalLines(rawLines, pageSize);
          final companion = BookSearchPagesCompanion(
            id: drift.Value('${bookId}_p$pIdx'),
            bookId: drift.Value(bookId),
            pageIndex: drift.Value(pIdx),
            plainText: drift.Value(pageIndexData.plainText),
            rawText: drift.Value(pageIndexData.rawText),
            geometryJson: drift.Value(
              jsonEncode(pageIndexData.tokens.map((t) => t.toJson()).toList()),
            ),
            isOcr: const drift.Value(false),
            fileHash: drift.Value(currentHash),
            indexVersion: const drift.Value(currentVersion),
            indexedAt: drift.Value(DateTime.now()),
          );
          await dbService.insertSearchPage(companion);
          newlyIndexed++;
        }
      }

      // Cooperative yield
      await Future<void>.delayed(Duration.zero);
    }

    sfDoc.dispose();
    return newlyIndexed;
  }

  /// Visible for testing OCR lines bounding-box processing and token geometry alignment.
  @visibleForTesting
  static ({String plainText, String rawText, List<SearchTokenGeometry> tokens})
  processOcrLinesForTesting(List<OcrLine> lines, Size pageSize) {
    return _processOcrLines(lines, pageSize);
  }

  /// Processes Apple Vision OCR lines into normalized dehyphenated plainText and token geometries.
  static ({String plainText, String rawText, List<SearchTokenGeometry> tokens})
  _processOcrLines(List<OcrLine> lines, Size pageSize) {
    final rawBuffer = StringBuffer();
    final plainBuffer = StringBuffer();
    final tokens = <SearchTokenGeometry>[];

    String? pendingHyphenPrefix;
    Rect? pendingHyphenBox;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineText = line.text.trim();
      if (lineText.isEmpty) continue;

      rawBuffer.writeln(lineText);

      // Chrome detection (isolated digits or top/bottom header margin)
      final isDigitOnly = RegExp(r'^\d+$').hasMatch(lineText);
      final isTopMargin = line.box.top < 0.055;
      final isBottomMargin = line.box.top > 0.945;
      final isChrome =
          (isDigitOnly && (isTopMargin || isBottomMargin)) ||
          (isTopMargin && lineText.length < 50);

      // Split words inside line
      final words = lineText
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isEmpty) continue;

      final totalLineLen = lineText.isNotEmpty ? lineText.length : 1;
      int charCursor = 0;

      for (int wIdx = 0; wIdx < words.length; wIdx++) {
        var word = words[wIdx];
        final isLastWordInLine = (wIdx == words.length - 1);
        final isFirstWordInLine = (wIdx == 0);

        // Calculate character-weighted horizontal bounds for proportional accuracy
        final wordCharStart = lineText.indexOf(word, charCursor);
        final effectiveStart = wordCharStart != -1 ? wordCharStart : charCursor;
        charCursor = effectiveStart + word.length;

        final wordFractionStart = effectiveStart / totalLineLen;
        final wordFractionWidth = word.length / totalLineLen;

        final wordBox = Rect.fromLTWH(
          (line.box.left + (wordFractionStart * line.box.width)).clamp(
            0.0,
            1.0,
          ),
          line.box.top.clamp(0.0, 1.0),
          (wordFractionWidth * line.box.width).clamp(0.0, 1.0),
          line.box.height.clamp(0.0, 1.0),
        );

        if (isFirstWordInLine && pendingHyphenPrefix != null) {
          // Dehyphenate! Merge with previous line's hyphenated prefix
          final mergedWord = '$pendingHyphenPrefix$word';
          final startPos = plainBuffer.length;
          plainBuffer.write(mergedWord);
          final endPos = plainBuffer.length;
          plainBuffer.write(' ');

          final prefixLen = pendingHyphenPrefix.length;
          // First token fragment (on previous line)
          tokens.add(
            SearchTokenGeometry(
              text: pendingHyphenPrefix,
              start: startPos,
              end: startPos + prefixLen,
              box: pendingHyphenBox ?? wordBox,
              isChrome: isChrome,
            ),
          );
          // Second token fragment (on current line)
          tokens.add(
            SearchTokenGeometry(
              text: word,
              start: startPos + prefixLen,
              end: endPos,
              box: wordBox,
              isChrome: isChrome,
            ),
          );

          pendingHyphenPrefix = null;
          pendingHyphenBox = null;
          continue;
        }

        if (isLastWordInLine &&
            word.endsWith('-') &&
            word.length > 2 &&
            i < lines.length - 1) {
          // Store pending hyphenation
          pendingHyphenPrefix = word.substring(0, word.length - 1);
          pendingHyphenBox = wordBox;
          continue;
        }

        final startPos = plainBuffer.length;
        plainBuffer.write(word);
        final endPos = plainBuffer.length;
        plainBuffer.write(' ');

        tokens.add(
          SearchTokenGeometry(
            text: word,
            start: startPos,
            end: endPos,
            box: wordBox,
            isChrome: isChrome,
          ),
        );
      }
    }

    return (
      plainText: plainBuffer.toString().trimRight(),
      rawText: rawBuffer.toString().trimRight(),
      tokens: tokens,
    );
  }

  /// Processes Syncfusion digital PDF lines into normalized dehyphenated plainText and token geometries.
  static ({String plainText, String rawText, List<SearchTokenGeometry> tokens})
  _processDigitalLines(List<sf.TextLine> lines, Size pageSize) {
    final rawBuffer = StringBuffer();
    final plainBuffer = StringBuffer();
    final tokens = <SearchTokenGeometry>[];

    final pageW = pageSize.width > 0 ? pageSize.width : 1.0;
    final pageH = pageSize.height > 0 ? pageSize.height : 1.0;

    String? pendingHyphenPrefix;
    Rect? pendingHyphenBox;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineText = line.text.trim();
      if (lineText.isEmpty) continue;

      rawBuffer.writeln(lineText);

      final normLineBox = Rect.fromLTWH(
        (line.bounds.left / pageW).clamp(0.0, 1.0),
        (line.bounds.top / pageH).clamp(0.0, 1.0),
        (line.bounds.width / pageW).clamp(0.0, 1.0),
        (line.bounds.height / pageH).clamp(0.0, 1.0),
      );

      final isDigitOnly = RegExp(r'^\d+$').hasMatch(lineText);
      final isTopMargin = normLineBox.top < 0.055;
      final isBottomMargin = normLineBox.top > 0.945;
      final isChrome =
          (isDigitOnly && (isTopMargin || isBottomMargin)) ||
          (isTopMargin && lineText.length < 50);

      final words = line.wordCollection.toList();
      if (words.isEmpty) continue;

      for (int wIdx = 0; wIdx < words.length; wIdx++) {
        final w = words[wIdx];
        final wordText = w.text.trim();
        if (wordText.isEmpty) continue;

        final wordBox = Rect.fromLTWH(
          (w.bounds.left / pageW).clamp(0.0, 1.0),
          (w.bounds.top / pageH).clamp(0.0, 1.0),
          (w.bounds.width / pageW).clamp(0.0, 1.0),
          (w.bounds.height / pageH).clamp(0.0, 1.0),
        );

        final isFirstWord = (wIdx == 0);
        final isLastWord = (wIdx == words.length - 1);

        if (isFirstWord && pendingHyphenPrefix != null) {
          final mergedWord = '$pendingHyphenPrefix$wordText';
          final startPos = plainBuffer.length;
          plainBuffer.write(mergedWord);
          final endPos = plainBuffer.length;
          plainBuffer.write(' ');

          final prefixLen = pendingHyphenPrefix.length;
          tokens.add(
            SearchTokenGeometry(
              text: pendingHyphenPrefix,
              start: startPos,
              end: startPos + prefixLen,
              box: pendingHyphenBox ?? wordBox,
              isChrome: isChrome,
            ),
          );
          tokens.add(
            SearchTokenGeometry(
              text: wordText,
              start: startPos + prefixLen,
              end: endPos,
              box: wordBox,
              isChrome: isChrome,
            ),
          );

          pendingHyphenPrefix = null;
          pendingHyphenBox = null;
          continue;
        }

        if (isLastWord &&
            wordText.endsWith('-') &&
            wordText.length > 2 &&
            i < lines.length - 1) {
          pendingHyphenPrefix = wordText.substring(0, wordText.length - 1);
          pendingHyphenBox = wordBox;
          continue;
        }

        final startPos = plainBuffer.length;
        plainBuffer.write(wordText);
        final endPos = plainBuffer.length;
        plainBuffer.write(' ');

        tokens.add(
          SearchTokenGeometry(
            text: wordText,
            start: startPos,
            end: endPos,
            box: wordBox,
            isChrome: isChrome,
          ),
        );
      }
    }

    return (
      plainText: plainBuffer.toString().trimRight(),
      rawText: rawBuffer.toString().trimRight(),
      tokens: tokens,
    );
  }
}
