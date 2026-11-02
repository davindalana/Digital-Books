// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:digital_books/features/reader/domain/services/book_search_indexer.dart';
import 'package:digital_books/features/processing/models/ocr_page_result.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Calculates Intersection over Union (IoU) of two 2D Rectangles.
double calculateIoU(Rect a, Rect b) {
  final intersectionLeft = math.max(a.left, b.left);
  final intersectionTop = math.max(a.top, b.top);
  final intersectionRight = math.min(a.right, b.right);
  final intersectionBottom = math.min(a.bottom, b.bottom);

  final intersectionWidth = math.max(0.0, intersectionRight - intersectionLeft);
  final intersectionHeight = math.max(0.0, intersectionBottom - intersectionTop);
  final intersectionArea = intersectionWidth * intersectionHeight;

  final areaA = a.width * a.height;
  final areaB = b.width * b.height;
  final unionArea = areaA + areaB - intersectionArea;

  if (unionArea <= 0.0) return 0.0;
  return intersectionArea / unionArea;
}

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 3.2.1 — Bounding Box & Token Geometry Accuracy Audit', () {
    test('1. Character-Weighted Proportional vs. Naive Uniform OCR Box IoU Benchmark', () {
      // Simulate an OCR text line: "Di kedalaman laut yang sunyi"
      // Line bounding box: left: 0.1, top: 0.2, width: 0.6, height: 0.04
      const lineBox = Rect.fromLTWH(0.1, 0.2, 0.6, 0.04);
      const text = 'Di kedalaman laut yang sunyi';
      final ocrLine = OcrLine(
        text: text,
        confidence: 0.98,
        box: lineBox,
      );

      // Suppose font metrics have monospace/proportional width around 0.0214 per char
      // Ground truth exact character positions (based on proportional font measurements):
      // "Di" (chars 0-2): left = 0.100, width = 2/28 * 0.6 = 0.0428
      // "kedalaman" (chars 3-12): left = 0.100 + (3/28 * 0.6) = 0.1643, width = 9/28 * 0.6 = 0.1928
      // "laut" (chars 13-17): left = 0.100 + (13/28 * 0.6) = 0.3786, width = 4/28 * 0.6 = 0.0857
      // "yang" (chars 18-22): left = 0.100 + (18/28 * 0.6) = 0.4857, width = 4/28 * 0.6 = 0.0857
      // "sunyi" (chars 23-28): left = 0.100 + (23/28 * 0.6) = 0.5928, width = 5/28 * 0.6 = 0.1071
      const totalChars = 28;
      Rect gtBox(int start, int len) => Rect.fromLTWH(
            0.1 + (start / totalChars) * 0.6,
            0.2,
            (len / totalChars) * 0.6,
            0.04,
          );

      final gtDi = gtBox(0, 2);
      final gtKedalaman = gtBox(3, 9);
      final gtLaut = gtBox(13, 4);

      // Method A: Naive Uniform Division (words.length = 5, each gets 1/5 = 0.20 width)
      final words = text.split(' ');
      expect(words.length, equals(5));
      final naiveBoxes = <String, Rect>{};
      for (int i = 0; i < words.length; i++) {
        naiveBoxes[words[i]] = Rect.fromLTWH(
          0.1 + (i / words.length) * 0.6,
          0.2,
          (1.0 / words.length) * 0.6,
          0.04,
        );
      }

      // Method B: Actual BookSearchIndexer Implementation
      final indexedData = BookSearchIndexer.processOcrLinesForTesting(
        [ocrLine],
        const Size(1000, 1400),
      );

      final charWeightedBoxes = <String, Rect>{};
      for (final t in indexedData.tokens) {
        charWeightedBoxes[t.text] = t.box;
      }

      // Benchmark Short Word: "Di" (2 chars)
      final naiveDiIoU = calculateIoU(naiveBoxes['Di']!, gtDi);
      final charDiIoU = calculateIoU(charWeightedBoxes['Di']!, gtDi);

      // Benchmark Long Word: "kedalaman" (9 chars)
      final naiveKedalamanIoU = calculateIoU(naiveBoxes['kedalaman']!, gtKedalaman);
      final charKedalamanIoU = calculateIoU(charWeightedBoxes['kedalaman']!, gtKedalaman);

      // Benchmark Medium Word: "laut" (4 chars)
      final naiveLautIoU = calculateIoU(naiveBoxes['laut']!, gtLaut);
      final charLautIoU = calculateIoU(charWeightedBoxes['laut']!, gtLaut);

      print('\n===============================================================');
      print('BOUNDING BOX IoU ACCURACY AUDIT: NAIVE VS CHAR-WEIGHTED');
      print('===============================================================');
      print('Token "Di" (short, 2 chars):');
      print('  - Naive Uniform IoU:        ${(naiveDiIoU * 100).toStringAsFixed(1)}%');
      print('  - Character-Weighted IoU:   ${(charDiIoU * 100).toStringAsFixed(1)}%');
      print('Token "kedalaman" (long, 9 chars):');
      print('  - Naive Uniform IoU:        ${(naiveKedalamanIoU * 100).toStringAsFixed(1)}%');
      print('  - Character-Weighted IoU:   ${(charKedalamanIoU * 100).toStringAsFixed(1)}%');
      print('Token "laut" (medium, 4 chars):');
      print('  - Naive Uniform IoU:        ${(naiveLautIoU * 100).toStringAsFixed(1)}%');
      print('  - Character-Weighted IoU:   ${(charLautIoU * 100).toStringAsFixed(1)}%');
      print('===============================================================\n');

      // Assertions
      // Naive uniform division severely distorts short words (stretches 3x, IoU < 40%)
      expect(naiveDiIoU, lessThan(0.40));
      // Character-weighted division achieves near-perfect proportional overlap
      expect(charDiIoU, greaterThan(0.95));
      expect(charKedalamanIoU, greaterThan(0.95));
      expect(charLautIoU, greaterThan(0.95));
    });

    test('2. Cross-Line Dehyphenation Bounding Box Resolution', () async {
      // Line 1 ends with "se-"
      // Line 2 begins with "buah"
      final line1 = OcrLine(
        text: 'menggiringku ke se-',
        confidence: 0.95,
        box: const Rect.fromLTWH(0.1, 0.40, 0.6, 0.04),
      );
      final line2 = OcrLine(
        text: 'buah tempat di tepi laut',
        confidence: 0.95,
        box: const Rect.fromLTWH(0.1, 0.45, 0.7, 0.04),
      );

      final indexData = BookSearchIndexer.processOcrLinesForTesting(
        [line1, line2],
        const Size(1000, 1400),
      );

      // Verify plainText contains dehyphenated word "sebuah"
      expect(indexData.plainText, contains('sebuah tempat'));

      // Insert into db and search
      const bookId = 'book_dehyphen_test';
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Dehyphenation Test'),
          author: const drift.Value('Author'),
          originalPdfPath: const drift.Value('/dummy/test.pdf'),
          totalPages: const drift.Value(1),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p0'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(0),
          plainText: drift.Value(indexData.plainText),
          rawText: drift.Value(indexData.rawText),
          geometryJson: drift.Value(
            jsonEncode(indexData.tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Search for "sebuah tempat"
      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: bookId,
        dbService: dbService,
        query: 'sebuah tempat',
      );

      expect(results.length, equals(1));
      final r = results.first;

      // Because "sebuah" spans across Line 1 ("se-") and Line 2 ("buah") and "tempat" is on Line 2:
      // The boundingBoxes list MUST contain fragments from BOTH lines!
      print('Bounding boxes returned for "sebuah tempat": ${r.boundingBoxes.length}');
      for (final box in r.boundingBoxes) {
        print('  - Rect: top=${box.top.toStringAsFixed(3)}, left=${box.left.toStringAsFixed(3)}, w=${box.width.toStringAsFixed(3)}, h=${box.height.toStringAsFixed(3)}');
      }

      expect(r.boundingBoxes.length, greaterThanOrEqualTo(2));
      // Check that at least one box is on Line 1 (top ~0.40) and one is on Line 2 (top ~0.45)
      final hasLine1Box = r.boundingBoxes.any((b) => (b.top - 0.40).abs() < 0.02);
      final hasLine2Box = r.boundingBoxes.any((b) => (b.top - 0.45).abs() < 0.02);

      expect(hasLine1Box, isTrue, reason: 'Must have bounding box on line 1 for prefix "se-"');
      expect(hasLine2Box, isTrue, reason: 'Must have bounding box on line 2 for suffix "buah"');
    });

    test('3. Multi-Line Multi-Token Phrase Bounding Box Coverage', () async {
      // Simulate multi-token search match across 3 tokens in a single line
      const bookId = 'book_phrase_test';
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Phrase Box Test'),
          author: const drift.Value('Author'),
          originalPdfPath: const drift.Value('/dummy/test.pdf'),
          totalPages: const drift.Value(1),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final tokens = [
        const SearchTokenGeometry(text: 'low,', start: 0, end: 4, box: Rect.fromLTWH(0.1, 0.5, 0.05, 0.03)),
        const SearchTokenGeometry(text: 'melancholy', start: 5, end: 15, box: Rect.fromLTWH(0.16, 0.5, 0.13, 0.03)),
        const SearchTokenGeometry(text: 'tune', start: 16, end: 20, box: Rect.fromLTWH(0.30, 0.5, 0.06, 0.03)),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p0'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('low, melancholy tune'),
          rawText: const drift.Value('low, melancholy tune'),
          geometryJson: drift.Value(jsonEncode(tokens.map((t) => t.toJson()).toList())),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: bookId,
        dbService: dbService,
        query: 'low, melancholy tune',
      );

      expect(results.length, equals(1));
      final r = results.first;

      // All 3 token boxes should be present in the result's boundingBoxes
      expect(r.boundingBoxes.length, equals(3));
      expect(r.boundingBoxes[0], equals(const Rect.fromLTWH(0.1, 0.5, 0.05, 0.03)));
      expect(r.boundingBoxes[1], equals(const Rect.fromLTWH(0.16, 0.5, 0.13, 0.03)));
      expect(r.boundingBoxes[2], equals(const Rect.fromLTWH(0.30, 0.5, 0.06, 0.03)));
    });
  });
}
