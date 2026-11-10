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

  setUp(() {
    testDoc = const ReaderDocument(
      bookId: 'book-anchor-1',
      title: 'Laut Bercerita — Edisi Pengujian Anchor',
      author: 'Leila S. Chudori',
      chapters: [
        ReaderChapter(
          id: 'ch-0',
          index: 0,
          title: 'Bab 1: Rumah Hantu Seyegan',
          nodes: [
            ContentNode(
              id: 'node-c0-n0',
              text: 'Malam itu angin berembus dingin di Seyegan.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 1,
            ),
            ContentNode(
              id: 'node-c0-n1',
              text:
                  'Kami berkumpul di meja makan kayu jati yang sudah reyot. Mas Biru mengetik catatan pergerakan.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 1,
            ),
            ContentNode(
              id: 'node-c0-n2',
              text:
                  'Laut memandang ke luar jendela. Laut memikirkan keluarganya di Solo.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 2,
            ),
          ],
        ),
        ReaderChapter(
          id: 'ch-1',
          index: 1,
          title: 'Bab 2: Terminal Tirtonadi',
          nodes: [
            ContentNode(
              id: 'node-c1-n0',
              text: 'Bus antarkota melaju kencang menyusuri jalan Solo-Yogya.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 3,
            ),
            ContentNode(
              id: 'node-c1-n1',
              text:
                  'Asin aroma laut tak ada di sini. Yang ada hanya asap knalpot dan keringat para penumpang.',
              type: ContentNodeType.paragraph,
              sourcePdfPage: 3,
            ),
          ],
        ),
      ],
    );
  });

  group('Phase 3.3 — Multi-Tier Anchor Resolution Engine Audit', () {
    test(
      'Tier 1: Exact Semantic Node and Offset Match succeeds immediately',
      () {
        final annotation = BookAnnotation(
          id: 'ann-tier1',
          bookId: 'book-anchor-1',
          type: AnnotationType.highlight,
          selectedText: 'meja makan kayu jati',
          chapterId: 'ch-0',
          anchorNodeId: 'node-c0-n1',
          startOffset: 18,
          endOffset: 38,
          createdAt: DateTime.now(),
        );

        final resolved = AnchorResolutionService.resolveInReflowableDocument(
          annotation: annotation,
          document: testDoc,
        );

        expect(resolved.anchorStatus, equals(AnchorStatus.resolved));
        expect(resolved.anchorNodeId, equals('node-c0-n1'));
        expect(resolved.startOffset, equals(18));
        expect(resolved.endOffset, equals(38));
      },
    );

    test(
      'Tier 2: Text + Prefix/Suffix Context Match survives text shifts in node',
      () {
        // Simulating a modified node where additional words were prepended, shifting the character offset
        const modifiedDoc = ReaderDocument(
          bookId: 'book-anchor-1',
          title: 'Laut Bercerita — Edisi Pengujian Anchor',
          author: 'Leila S. Chudori',
          chapters: [
            ReaderChapter(
              id: 'ch-0',
              index: 0,
              title: 'Bab 1: Rumah Hantu Seyegan',
              nodes: [
                ContentNode(
                  id: 'node-c0-n1',
                  // Prepending 'Pada pukul sepuluh, ' -> shifts original start from 19 to 38
                  text:
                      'Pada pukul sepuluh, kami berkumpul di meja makan kayu jati yang sudah reyot. Mas Biru mengetik catatan pergerakan.',
                  type: ContentNodeType.paragraph,
                  sourcePdfPage: 1,
                ),
              ],
            ),
          ],
        );

        final annotationWithContext = BookAnnotation(
          id: 'ann-tier2',
          bookId: 'book-anchor-1',
          type: AnnotationType.highlight,
          selectedText: 'meja makan kayu jati',
          prefixContext: 'kami berkumpul di ',
          suffixContext: ' yang sudah reyot',
          chapterId: '0',
          anchorNodeId: 'node-c0-n1',
          startOffset: 19, // Old offset before text was shifted!
          endOffset: 39,
          createdAt: DateTime.now(),
        );

        final resolved = AnchorResolutionService.resolveInReflowableDocument(
          annotation: annotationWithContext,
          document: modifiedDoc,
        );

        expect(resolved.anchorStatus, equals(AnchorStatus.resolved));
        expect(resolved.anchorNodeId, equals('node-c0-n1'));
        expect(
          resolved.startOffset,
          equals(38),
          reason:
              'Must re-anchor to new shifted offset using prefix/suffix context',
        );
        expect(resolved.endOffset, equals(58));
      },
    );

    test(
      'Tier 3: Unambiguous Single Text Match within Chapter re-aligns anchor',
      () {
        final annotationNoContext = BookAnnotation(
          id: 'ann-tier3',
          bookId: 'book-anchor-1',
          type: AnnotationType.highlight,
          selectedText: 'Mas Biru mengetik',
          chapterId: 'ch-0',
          anchorNodeId: 'corrupted-node-id', // Stale/invalid node ID
          startOffset: 999, // Stale offset
          endOffset: 1016,
          createdAt: DateTime.now(),
        );

        final resolved = AnchorResolutionService.resolveInReflowableDocument(
          annotation: annotationNoContext,
          document: testDoc,
        );

        expect(resolved.anchorStatus, equals(AnchorStatus.approximate));
        expect(
          resolved.anchorNodeId,
          equals('node-c0-n1'),
          reason:
              'Must resolve to the only node in chapter containing Mas Biru mengetik',
        );
        expect(resolved.startOffset, equals(57));
      },
    );

    test('Tier 4: Global Search resolves text moved to another Chapter', () {
      final annotationMovedChapter = BookAnnotation(
        id: 'ann-tier4',
        bookId: 'book-anchor-1',
        type: AnnotationType.note,
        selectedText: 'asap knalpot',
        chapterId: 'ch-0', // Incorrectly recorded as Chapter 0
        anchorNodeId: 'node-c0-n999',
        createdAt: DateTime.now(),
      );

      // 'asap knalpot' appears only in Chapter 1 node 1
      final resolved = AnchorResolutionService.resolveInReflowableDocument(
        annotation: annotationMovedChapter,
        document: testDoc,
      );

      expect(resolved.anchorStatus, equals(AnchorStatus.approximate));
      expect(
        resolved.chapterId,
        equals('ch-1'),
        reason: 'Global resolution must correctly locate Chapter 1',
      );
      expect(resolved.anchorNodeId, equals('node-c1-n1'));
    });

    test(
      'Tier 5: Strict Unresolved Fallback — Ambiguous duplicate text without context is NEVER falsely bound',
      () {
        // In node-c0-n2: 'Laut memandang ke luar jendela. Laut memikirkan keluarganya di Solo.'
        // The word 'Laut' appears twice in the same node and in title!
        // If no prefix/suffix is provided and offsets don't match, resolution must flag as unresolved, NOT arbitrarily guess!
        final ambiguousAnnotation = BookAnnotation(
          id: 'ann-tier5',
          bookId: 'book-anchor-1',
          type: AnnotationType.highlight,
          selectedText: 'Laut',
          chapterId: '0',
          anchorNodeId: 'node-c0-n2',
          startOffset: 999, // Stale offset
          endOffset: 1003,
          createdAt: DateTime.now(),
        );

        final resolved = AnchorResolutionService.resolveInReflowableDocument(
          annotation: ambiguousAnnotation,
          document: testDoc,
        );

        expect(
          resolved.anchorStatus,
          equals(AnchorStatus.unresolved),
          reason:
              'Ambiguous text with multiple occurrences and invalid offset must be flagged as unresolved rather than guessing',
        );
        expect(resolved.isUnresolved, isTrue);
      },
    );

    test(
      'Cross-Mode Geometry Resolution: resolveInOriginalPdf maps Reflowable anchor to exact PDF bounding boxes',
      () {
        // 'Kami berkumpul di meja makan kayu jati yang sudah reyot.'
        // Kami (0..4), berkumpul (5..14), di (15..17), meja (18..22), makan (23..28)
        final tokenGeometries = [
          const SearchTokenGeometry(
            text: 'Kami',
            start: 0,
            end: 4,
            box: Rect.fromLTWH(0.1, 0.2, 0.08, 0.03),
          ),
          const SearchTokenGeometry(
            text: 'berkumpul',
            start: 5,
            end: 14,
            box: Rect.fromLTWH(0.19, 0.2, 0.14, 0.03),
          ),
          const SearchTokenGeometry(
            text: 'di',
            start: 15,
            end: 17,
            box: Rect.fromLTWH(0.34, 0.2, 0.04, 0.03),
          ),
          const SearchTokenGeometry(
            text: 'meja',
            start: 18,
            end: 22,
            box: Rect.fromLTWH(0.39, 0.2, 0.07, 0.03),
          ),
          const SearchTokenGeometry(
            text: 'makan',
            start: 23,
            end: 28,
            box: Rect.fromLTWH(0.47, 0.2, 0.09, 0.03),
          ),
        ];

        final searchPageRow = BookSearchPage(
          id: 'book-anchor-1_p0',
          bookId: 'book-anchor-1',
          pageIndex: 0,
          plainText: 'Kami berkumpul di meja makan kayu jati yang sudah reyot.',
          rawText: 'Kami berkumpul di meja makan kayu jati yang sudah reyot.',
          geometryJson: jsonEncode(
            tokenGeometries.map((g) => g.toJson()).toList(),
          ),
          isOcr: false,
          indexVersion: 1,
          indexedAt: DateTime.now(),
        );

        final reflowableAnnotation = BookAnnotation(
          id: 'ann-crossmode',
          bookId: 'book-anchor-1',
          type: AnnotationType.highlight,
          selectedText: 'meja makan',
          pageIndex: 1,
          color: 'green',
          createdAt: DateTime.now(),
        );

        final pdfResolved = AnchorResolutionService.resolveInOriginalPdf(
          annotation: reflowableAnnotation,
          indexedPages: [searchPageRow],
        );

        expect(pdfResolved.anchorStatus, equals(AnchorStatus.resolved));
        expect(pdfResolved.pageIndex, equals(1));
        expect(pdfResolved.boundingBoxes.length, equals(2));

        // Verify bounding boxes encompass 'meja' and 'makan'
        final mejaBox = pdfResolved.boundingBoxes[0];
        final makanBox = pdfResolved.boundingBoxes[1];
        expect(mejaBox.left, closeTo(0.39, 0.01));
        expect(makanBox.left, closeTo(0.47, 0.01));
      },
    );
  });
}
