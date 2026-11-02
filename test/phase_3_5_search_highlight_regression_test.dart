// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:digital_books/features/reader/domain/services/anchor_resolution_service.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;

  const digitalBookId = 'test_digital_book_corpus';
  const ocrBookId = 'test_ocr_book_corpus';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);

    // 1. Seed Digital Book Record
    await dbService.insertBook(
      BooksCompanion(
        id: const drift.Value(digitalBookId),
        title: const drift.Value('The Let Them Theory'),
        author: const drift.Value('Mel Robbins'),
        originalPdfPath: const drift.Value('/path/to/let_them.pdf'),
        fileHash: const drift.Value('digital_hash_123'),
        totalPages: const drift.Value(20),
        isScanned: const drift.Value(false),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // 2. Seed OCR Book Record
    await dbService.insertBook(
      BooksCompanion(
        id: const drift.Value(ocrBookId),
        title: const drift.Value('Bicara Itu Ada Seninya'),
        author: const drift.Value('Oh Su Hyang'),
        originalPdfPath: const drift.Value('/path/to/bicara_seninya.pdf'),
        fileHash: const drift.Value('ocr_hash_456'),
        totalPages: const drift.Value(50),
        isScanned: const drift.Value(true),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Seed Digital Book Search Page with native geometry
    final digitalTokens = [
      const SearchTokenGeometry(text: 'The', start: 0, end: 3, box: Rect.fromLTWH(0.1, 0.2, 0.08, 0.04)),
      const SearchTokenGeometry(text: 'Let', start: 4, end: 7, box: Rect.fromLTWH(0.2, 0.2, 0.08, 0.04)),
      const SearchTokenGeometry(text: 'Them', start: 8, end: 12, box: Rect.fromLTWH(0.3, 0.2, 0.10, 0.04)),
      const SearchTokenGeometry(text: 'Theory', start: 13, end: 19, box: Rect.fromLTWH(0.42, 0.2, 0.14, 0.04)),
      const SearchTokenGeometry(text: 'is', start: 20, end: 22, box: Rect.fromLTWH(0.58, 0.2, 0.05, 0.04)),
      const SearchTokenGeometry(text: 'life-changing.', start: 23, end: 37, box: Rect.fromLTWH(0.65, 0.2, 0.25, 0.04)),
    ];

    await dbService.insertSearchPage(
      BookSearchPagesCompanion(
        id: const drift.Value('${digitalBookId}_p11'),
        bookId: const drift.Value(digitalBookId),
        pageIndex: const drift.Value(11), // 1-based PDF page 12
        plainText: const drift.Value('The Let Them Theory is life-changing.'),
        rawText: const drift.Value('The Let Them Theory is life-changing.'),
        geometryJson: drift.Value(jsonEncode(digitalTokens.map((t) => t.toJson()).toList())),
        isOcr: const drift.Value(false),
        indexVersion: const drift.Value(1),
        indexedAt: drift.Value(DateTime.now()),
      ),
    );

    // Seed OCR Book Search Page with hyphenated & Indonesian text
    // "Bicara itu ada seninya untuk mem- pertahankan hubungan baik siang- malam."
    // Plain text is dehyphenated: "Bicara itu ada seninya untuk mempertahankan hubungan baik siang-malam."
    final ocrTokens = [
      const SearchTokenGeometry(text: 'Bicara', start: 0, end: 6, box: Rect.fromLTWH(0.1, 0.3, 0.12, 0.03)),
      const SearchTokenGeometry(text: 'itu', start: 7, end: 10, box: Rect.fromLTWH(0.23, 0.3, 0.06, 0.03)),
      const SearchTokenGeometry(text: 'ada', start: 11, end: 14, box: Rect.fromLTWH(0.30, 0.3, 0.07, 0.03)),
      const SearchTokenGeometry(text: 'seninya', start: 15, end: 22, box: Rect.fromLTWH(0.38, 0.3, 0.14, 0.03)),
      const SearchTokenGeometry(text: 'untuk', start: 23, end: 28, box: Rect.fromLTWH(0.53, 0.3, 0.10, 0.03)),
      const SearchTokenGeometry(text: 'mempertahankan', start: 29, end: 43, box: Rect.fromLTWH(0.1, 0.35, 0.28, 0.03)),
      const SearchTokenGeometry(text: 'hubungan', start: 44, end: 52, box: Rect.fromLTWH(0.40, 0.35, 0.16, 0.03)),
      const SearchTokenGeometry(text: 'baik', start: 53, end: 57, box: Rect.fromLTWH(0.58, 0.35, 0.08, 0.03)),
      const SearchTokenGeometry(text: 'siang-malam.', start: 58, end: 70, box: Rect.fromLTWH(0.68, 0.35, 0.22, 0.03)),
    ];

    await dbService.insertSearchPage(
      BookSearchPagesCompanion(
        id: const drift.Value('${ocrBookId}_p32'),
        bookId: const drift.Value(ocrBookId),
        pageIndex: const drift.Value(32), // 1-based PDF page 33
        plainText: const drift.Value('Bicara itu ada seninya untuk mempertahankan hubungan baik siang-malam.'),
        rawText: const drift.Value('Bicara itu ada seninya untuk mem- pertahankan hubungan baik siang- malam.'),
        geometryJson: drift.Value(jsonEncode(ocrTokens.map((t) => t.toJson()).toList())),
        isOcr: const drift.Value(true),
        indexVersion: const drift.Value(1),
        indexedAt: drift.Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    try {
      await db.close().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
  });

  group('Phase 3.5 — Search, Highlight & Cross-Mode Synchronization Regression', () {
    test('1. Multi-Corpus Search: Digital PDF & Scanned OCR Matching', () async {
      // Search Digital PDF for "theory"
      final digitalResults = await InBookSearchEngine.searchIndexedBook(
        bookId: digitalBookId,
        dbService: dbService,
        query: 'theory',
      );
      expect(digitalResults, isNotEmpty);
      expect(digitalResults.first.sourcePdfPage, equals(12)); // 1-based page index
      expect(digitalResults.first.snippet.toLowerCase(), contains('theory'));
      expect(digitalResults.first.boundingBoxes, isNotEmpty);
      expect(digitalResults.first.boundingBoxes.first.width, greaterThan(0));

      // Search OCR PDF for "seninya"
      final ocrResults = await InBookSearchEngine.searchIndexedBook(
        bookId: ocrBookId,
        dbService: dbService,
        query: 'seninya',
      );
      expect(ocrResults, isNotEmpty);
      expect(ocrResults.first.sourcePdfPage, equals(33));
      expect(ocrResults.first.snippet.toLowerCase(), contains('seninya'));
      expect(ocrResults.first.boundingBoxes, isNotEmpty);
    });

    test('2. Dehyphenation & Indonesian Compound Word Search Matching', () async {
      // Search for split word that was dehyphenated in plainText: "mempertahankan"
      final dehyphenResult = await InBookSearchEngine.searchIndexedBook(
        bookId: ocrBookId,
        dbService: dbService,
        query: 'mempertahankan',
      );
      expect(dehyphenResult, isNotEmpty, reason: 'Dehyphenated query must find the target word in OCR page');
      expect(dehyphenResult.first.sourcePdfPage, equals(33));
      expect(dehyphenResult.first.boundingBoxes, isNotEmpty);

      // Search for Indonesian compound word: "siang-malam"
      final compoundResult = await InBookSearchEngine.searchIndexedBook(
        bookId: ocrBookId,
        dbService: dbService,
        query: 'siang-malam',
      );
      expect(compoundResult, isNotEmpty, reason: 'Indonesian compound word with preserved hyphen must match query');
      expect(compoundResult.first.snippet, contains('siang-malam'));
    });

    testWidgets('3. Original PDF Search Highlight Painter Verification', (tester) async {
      const highlightRects = [
        Rect.fromLTWH(0.1, 0.2, 0.3, 0.05),
        Rect.fromLTWH(0.5, 0.6, 0.2, 0.04),
      ];

      final painterLight = PdfSearchHighlightPainter(
        normalizedBoxes: highlightRects,
        isDark: false,
      );

      final painterDark = PdfSearchHighlightPainter(
        normalizedBoxes: highlightRects,
        isDark: true,
      );

      expect(painterLight.shouldRepaint(painterDark), isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 1000,
              child: CustomPaint(
                painter: painterLight,
              ),
            ),
          ),
        ),
      );

      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PdfSearchHighlightPainter), findsOneWidget);
    });

    test('4. Reflowable Search Highlight Span Builder Traversal & Active Match Indexing', () {
      const fullText = 'Bicara itu ada seninya untuk mempertahankan hubungan baik. Seninya ada dalam mendengarkan.';

      // Search for "seninya" (appears twice: index 15 and index 59)
      final match0 = const ActiveSearchMatch(
        nodeId: 'node_1',
        startOffset: 15,
        endOffset: 22,
        isActive: true,
      );
      final match1 = const ActiveSearchMatch(
        nodeId: 'node_1',
        startOffset: 59,
        endOffset: 66,
        isActive: false,
      );

      // Build rich span for match0 as active
      final richSpan0 = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: fullText,
        sliceStartOffset: 0,
        sliceEndOffset: fullText.length,
        highlightsForNode: const [],
        searchMatchesForNode: [match0, match1],
        baseStyle: const TextStyle(fontSize: 16, color: Colors.black),
        theme: ReadingThemeType.white,
      );

      expect(richSpan0.children, isNotNull);
      expect(richSpan0.children!.length, greaterThanOrEqualTo(3));

      // Build rich span for match1 as active
      final match0Inactive = const ActiveSearchMatch(
        nodeId: 'node_1',
        startOffset: 15,
        endOffset: 22,
        isActive: false,
      );
      final match1Active = const ActiveSearchMatch(
        nodeId: 'node_1',
        startOffset: 59,
        endOffset: 66,
        isActive: true,
      );

      final richSpan1 = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: fullText,
        sliceStartOffset: 0,
        sliceEndOffset: fullText.length,
        highlightsForNode: const [],
        searchMatchesForNode: [match0Inactive, match1Active],
        baseStyle: const TextStyle(fontSize: 16, color: Colors.black),
        theme: ReadingThemeType.white,
      );

      expect(richSpan1.children, isNotNull);
      expect(richSpan1.children!.length, greaterThanOrEqualTo(3));
    });

    test('5. Cross-Mode Reading Position & Anchor Synchronization (PDF <-> Reflowable)', () async {
      const reflowableDoc = ReaderDocument(
        bookId: 'sync_test_book',
        title: 'Bicara Itu Ada Seninya',
        author: 'Oh Su Hyang',
        totalPages: 100,
        chapters: [
          ReaderChapter(
            id: 'ch_0',
            index: 0,
            title: 'Bab 1: Perjumpaan Awal',
            nodes: [
              ContentNode(
                id: 'node_p1',
                type: ContentNodeType.paragraph,
                text: 'Halaman pertama buku pengantar komunikasi.',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'node_p2',
                type: ContentNodeType.paragraph,
                text: 'Halaman kedua membahas seni berbicara secara persuasif.',
                sourcePdfPage: 2,
              ),
              ContentNode(
                id: 'node_p33',
                type: ContentNodeType.paragraph,
                text: 'Bicara itu ada seninya untuk mempertahankan hubungan baik siang-malam.',
                sourcePdfPage: 33,
              ),
            ],
          ),
        ],
      );

      // Scenario A: Annotation created in Reflowable mode on node_p33
      final reflowableAnnotation = BookAnnotation(
        id: 'annot_1',
        bookId: 'sync_test_book',
        chapterId: 'ch_0',
        anchorNodeId: 'node_p33',
        selectedText: 'mempertahankan hubungan baik',
        startOffset: 29,
        endOffset: 57,
        prefixContext: 'seninya untuk ',
        suffixContext: ' siang-malam.',
        type: AnnotationType.highlight,
        color: 'yellow',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Resolve in Reflowable
      final resolvedReflowable = AnchorResolutionService.resolveInReflowableDocument(
        annotation: reflowableAnnotation,
        document: reflowableDoc,
      );
      expect(resolvedReflowable.anchorStatus, equals(AnchorStatus.resolved));
      expect(resolvedReflowable.pageIndex, equals(33));

      // Scenario B: User switches to Original PDF mode.
      // Search page indexed for Page 33
      final searchPages = await dbService.getSearchPagesForBook(ocrBookId);
      final resolvedPdf = AnchorResolutionService.resolveInOriginalPdf(
        annotation: resolvedReflowable,
        indexedPages: searchPages,
      );

      expect(resolvedPdf.anchorStatus, equals(AnchorStatus.resolved));
      expect(resolvedPdf.pageIndex, equals(33));
      expect(resolvedPdf.boundingBoxes, isNotEmpty);
      expect(resolvedPdf.boundingBoxes.first.top, greaterThan(0));

      // Scenario C: Bookmark on page 33 preserved across modes
      final bookmark = BookAnnotation(
        id: 'bm_1',
        bookId: 'sync_test_book',
        chapterId: 'ch_0',
        anchorNodeId: 'node_p33',
        pageIndex: 33,
        selectedText: '',
        type: AnnotationType.bookmark,
        color: 'yellow',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final resolvedBookmark = AnchorResolutionService.resolveInReflowableDocument(
        annotation: bookmark,
        document: reflowableDoc,
      );
      expect(resolvedBookmark.anchorStatus, equals(AnchorStatus.resolved));
      expect(resolvedBookmark.pageIndex, equals(33));
    });
  });
}
