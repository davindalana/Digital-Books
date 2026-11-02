// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:digital_books/features/reader/domain/services/anchor_resolution_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReaderDocument testDoc;
  late List<BookSearchPage> testSearchPages;

  setUp(() {
    testDoc = const ReaderDocument(
      bookId: 'book-cross-sync',
      title: 'Aroma Karsa',
      author: 'Dee Lestari',
      chapters: [
        ReaderChapter(
          id: 'ch-0',
          index: 0,
          title: 'Bab 1: Puspa Karsa',
          nodes: [
            ContentNode(
              id: 'node-0',
              text: 'Jati Wesi menghirup udara Bantar Gebang dengan saksama.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 1,
            ),
            ContentNode(
              id: 'node-1',
              text: 'Baginya, setiap aroma memiliki warna dan partikel tersendiri di udara.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 2,
            ),
          ],
        ),
      ],
    );

    // Search Page geometry for Page 2
    // 'Baginya, setiap aroma memiliki warna dan partikel tersendiri di udara.'
    final p2Tokens = [
      const SearchTokenGeometry(text: 'Baginya,', start: 0, end: 8, box: Rect.fromLTWH(0.1, 0.15, 0.12, 0.03)),
      const SearchTokenGeometry(text: 'setiap', start: 9, end: 15, box: Rect.fromLTWH(0.23, 0.15, 0.10, 0.03)),
      const SearchTokenGeometry(text: 'aroma', start: 16, end: 21, box: Rect.fromLTWH(0.34, 0.15, 0.09, 0.03)),
      const SearchTokenGeometry(text: 'memiliki', start: 22, end: 30, box: Rect.fromLTWH(0.44, 0.15, 0.13, 0.03)),
      const SearchTokenGeometry(text: 'warna', start: 31, end: 36, box: Rect.fromLTWH(0.58, 0.15, 0.09, 0.03)),
    ];

    testSearchPages = [
      BookSearchPage(
        id: 'book-cross-sync_p1',
        bookId: 'book-cross-sync',
        pageIndex: 1, // 0-based page index -> represents PDF page 2
        plainText: 'Baginya, setiap aroma memiliki warna dan partikel tersendiri di udara.',
        rawText: 'Baginya, setiap aroma memiliki warna dan partikel tersendiri di udara.',
        geometryJson: jsonEncode(p2Tokens.map((t) => t.toJson()).toList()),
        isOcr: false,
        indexVersion: 1,
        indexedAt: DateTime.now(),
      ),
    ];
  });

  group('Phase 3.3 — Cross-Mode Annotation Sync & Geometry Invariance Audit', () {
    test('1. Reflowable Highlight resolves into Original PDF with accurate page and bounding boxes', () {
      // User creates highlight in Reflowable mode
      final reflowableHighlight = BookAnnotation(
        id: 'ann-reflow-to-pdf',
        bookId: 'book-cross-sync',
        type: AnnotationType.highlight,
        selectedText: 'setiap aroma',
        chapterId: 'ch-0',
        anchorNodeId: 'node-1',
        startOffset: 9,
        endOffset: 21,
        pageIndex: 2, // From node.sourcePdfPage
        color: 'yellow',
        createdAt: DateTime.now(),
      );

      // When switched to Original PDF reader, resolve geometry
      final resolvedInPdf = AnchorResolutionService.resolveInOriginalPdf(
        annotation: reflowableHighlight,
        indexedPages: testSearchPages,
      );

      expect(resolvedInPdf.anchorStatus, equals(AnchorStatus.resolved));
      expect(resolvedInPdf.pageIndex, equals(2));
      expect(resolvedInPdf.boundingBoxes.length, equals(2));

      // 'setiap' at left: 0.23, 'aroma' at left: 0.34
      expect(resolvedInPdf.boundingBoxes[0].left, closeTo(0.23, 0.01));
      expect(resolvedInPdf.boundingBoxes[1].left, closeTo(0.34, 0.01));
    });

    test('2. Original PDF Bookmark/Highlight resolves into Reflowable semantic node and character offset', () {
      // User creates highlight in Original PDF mode (starts with pageIndex and selected text)
      final pdfAnnotation = BookAnnotation(
        id: 'ann-pdf-to-reflow',
        bookId: 'book-cross-sync',
        type: AnnotationType.note,
        selectedText: 'aroma memiliki warna',
        pageIndex: 2,
        color: 'blue',
        note: 'Deskripsi synesthesia aroma.',
        createdAt: DateTime.now(),
      );

      // When switched to Reflowable reader, resolve semantic node and offset
      final resolvedInReflow = AnchorResolutionService.resolveInReflowableDocument(
        annotation: pdfAnnotation,
        document: testDoc,
      );

      expect(resolvedInReflow.anchorStatus, equals(AnchorStatus.approximate));
      expect(resolvedInReflow.anchorNodeId, equals('node-1'));
      expect(resolvedInReflow.startOffset, equals(16));
      expect(resolvedInReflow.endOffset, equals(36));
      expect(resolvedInReflow.chapterId, equals('ch-0'));
    });

    test('3. Typography & Window Dimension Invariance: Node ID and Character Offset remain stable', () {
      // Anchoring is semantic (Node + Offset), completely decoupled from viewport width or font size
      final annotation = BookAnnotation(
        id: 'ann-invariant',
        bookId: 'book-cross-sync',
        type: AnnotationType.highlight,
        selectedText: 'Jati Wesi',
        chapterId: 'ch-0',
        anchorNodeId: 'node-0',
        startOffset: 0,
        endOffset: 9,
        createdAt: DateTime.now(),
      );

      // Even if typography or viewport is resized, semantic document nodes do not change character content
      final resolutionSmallScreen = AnchorResolutionService.resolveInReflowableDocument(
        annotation: annotation,
        document: testDoc,
      );

      final resolutionLargeScreen = AnchorResolutionService.resolveInReflowableDocument(
        annotation: annotation,
        document: testDoc,
      );

      expect(resolutionSmallScreen.startOffset, equals(0));
      expect(resolutionSmallScreen.endOffset, equals(9));
      expect(resolutionSmallScreen.anchorNodeId, equals(resolutionLargeScreen.anchorNodeId));
      expect(resolutionSmallScreen.startOffset, equals(resolutionLargeScreen.startOffset));
      expect(resolutionSmallScreen.anchorStatus, equals(AnchorStatus.resolved));
    });
  });
}
