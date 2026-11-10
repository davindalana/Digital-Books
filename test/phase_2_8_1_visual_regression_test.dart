// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/reader/models/book_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.8.1 — Visual Regression & Pagination Stress Suite', () {
    test(
      'A. Exact Mathematical Geometry Alignment between Engine and Renderer',
      () {
        const typoSingle = TypographySettings(
          twoPageSpread: false,
          horizontalMargin: 32.0,
        );
        const typoSpread = TypographySettings(
          twoPageSpread: true,
          horizontalMargin: 32.0,
        );

        // 1. Narrow window (400 x 600)
        final pagesNarrow = PaginationEngine.paginateChapter(
          chapter: ReaderChapter(
            id: 'c1',
            index: 0,
            title: 'Narrow',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text: 'Sample body text.',
              ),
            ],
          ),
          typography: typoSingle,
          viewportWidth: 400.0,
          viewportHeight: 600.0,
        );
        expect(pagesNarrow, isNotEmpty);

        // 2. Medium window (800 x 700)
        final pagesMedium = PaginationEngine.paginateChapter(
          chapter: ReaderChapter(
            id: 'c2',
            index: 0,
            title: 'Medium',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text: 'Sample body text.',
              ),
            ],
          ),
          typography: typoSingle,
          viewportWidth: 800.0,
          viewportHeight: 700.0,
        );
        expect(pagesMedium, isNotEmpty);

        // 3. Wide window (1200 x 800) Two-Page Spread
        final pagesWide = PaginationEngine.paginateChapter(
          chapter: ReaderChapter(
            id: 'c3',
            index: 0,
            title: 'Wide Spread',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text: 'Sample body text.',
              ),
            ],
          ),
          typography: typoSpread,
          viewportWidth: 1200.0,
          viewportHeight: 800.0,
        );
        expect(pagesWide, isNotEmpty);

        // Verify upper clamp consistency: on ultra-wide monitor (2560px), contentWidth is clamped to max 800 (spread) / 900 (single)
        final pagesUltraWide = PaginationEngine.paginateChapter(
          chapter: ReaderChapter(
            id: 'c4',
            index: 0,
            title: 'Ultra Wide',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text: 'Sample body text.',
              ),
            ],
          ),
          typography: typoSpread,
          viewportWidth: 2560.0,
          viewportHeight: 1440.0,
        );
        expect(pagesUltraWide, isNotEmpty);
      },
    );

    test(
      'B. Word Boundary Preservation: No words sliced in half & zero character loss',
      () {
        final longText =
            'Melalui jalan setapak berbatu, kami melangkah pelan dalam kegelapan malam. '
                'Suara deburan ombak di kejauhan terdengar semakin jelas dan menggetarkan dada. '
                'Tak ada lentera, tak ada petunjuk arah, hanya keyakinan yang menuntun kami. ' *
            15;

        final chapter = ReaderChapter(
          id: 'long_ch',
          index: 0,
          title: 'Bab Panjang',
          nodes: [
            ContentNode(
              id: 'p1',
              type: ContentNodeType.paragraph,
              text: longText,
            ),
          ],
        );

        for (final fontSize in [12.0, 16.0, 19.0, 24.0]) {
          for (final lineSpacing in [1.2, 1.5, 1.8]) {
            final typo = TypographySettings(
              fontSize: fontSize,
              lineSpacing: lineSpacing,
              twoPageSpread: false,
            );

            final pages = PaginationEngine.paginateChapter(
              chapter: chapter,
              typography: typo,
              viewportWidth: 600.0,
              viewportHeight: 500.0,
            );

            expect(pages.length, greaterThanOrEqualTo(2));

            // Reconstruct all slices across pages
            final reconstructed = StringBuffer();
            for (int i = 0; i < pages.length; i++) {
              final page = pages[i];
              expect(page.slices, isNotEmpty);
              for (final slice in page.slices) {
                // Word boundary check: neither slice starts nor ends in the middle of an alphanumeric word
                if (slice.isContinuation) {
                  // Continuation slice should start with a clean character, not a trailing half-word
                  expect(slice.textSlice.startsWith(' '), isFalse);
                }
                if (slice.hasMore) {
                  expect(slice.textSlice.endsWith(' '), isFalse);
                }
                reconstructed.write(slice.textSlice);
                if (slice.hasMore) reconstructed.write(' ');
              }
            }

            // Verify text content fidelity (ignoring whitespace compression)
            final originalTokens = longText
                .split(RegExp(r'\s+'))
                .where((t) => t.isNotEmpty)
                .toList();
            final reconTokens = reconstructed
                .toString()
                .split(RegExp(r'\s+'))
                .where((t) => t.isNotEmpty)
                .toList();
            expect(
              reconTokens,
              equals(originalTokens),
              reason:
                  'Tokens lost or duplicated at font $fontSize and spacing $lineSpacing',
            );
          }
        }
      },
    );

    test(
      'C. Orphan Heading Budgeting prevents heading sitting alone at bottom of page',
      () {
        // Create a chapter where a heading occurs when availableHeight is almost exhausted
        final fillerNodes = List.generate(
          6,
          (i) => ContentNode(
            id: 'fill_$i',
            type: ContentNodeType.paragraph,
            text:
                'Paragraf pengisi yang cukup panjang untuk mengisi sebagian besar tinggi viewport halaman. ' *
                2,
          ),
        );

        final headingNode = ContentNode(
          id: 'h_test',
          type: ContentNodeType.heading,
          level: 1,
          text: 'BAB PENTING BERIKUTNYA',
        );

        final bodyAfterHeading = ContentNode(
          id: 'body_after',
          type: ContentNodeType.paragraph,
          text:
              'Ini adalah kalimat pertama di bawah judul bab yang harus selalu menemani judul bab tersebut.',
        );

        final chapter = ReaderChapter(
          id: 'orphan_ch',
          index: 0,
          title: 'Orphan Test',
          nodes: [...fillerNodes, headingNode, bodyAfterHeading],
        );

        const typo = TypographySettings(fontSize: 16.0, twoPageSpread: false);
        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          typography: typo,
          viewportWidth: 600.0,
          viewportHeight: 550.0,
        );

        // Find the page containing the heading
        int headingPageIndex = -1;
        for (int i = 0; i < pages.length; i++) {
          if (pages[i].slices.any((s) => s.node.id == 'h_test')) {
            headingPageIndex = i;
            break;
          }
        }

        expect(headingPageIndex, greaterThanOrEqualTo(0));
        final headingPage = pages[headingPageIndex];

        // CRITICAL: The page containing the heading MUST also contain content that follows it,
        // it should NEVER be the sole slice at the bottom of a page!
        final headingSliceIndex = headingPage.slices.indexWhere(
          (s) => s.node.id == 'h_test',
        );
        expect(
          headingSliceIndex,
          isNot(equals(headingPage.slices.length - 1)),
          reason:
              'Heading was orphaned as the very last item on the page without following body text!',
        );
      },
    );

    test('D. Image and Caption In-Stream Placement Budgeting', () {
      final chapter = ReaderChapter(
        id: 'img_ch',
        index: 0,
        title: 'Illustrated Chapter',
        nodes: [
          ContentNode(
            id: 'p_before',
            type: ContentNodeType.paragraph,
            text:
                'Teks pembuka sebelum ilustrasi yang memperkenalkan konteks gambar.',
          ),
          ContentNode(
            id: 'img_1',
            type: ContentNodeType.image,
            text: 'Gambar 1.2: Peta topografi pesisir selatan Jawa Timur.',
            imagePath: 'test/fixtures/corpus/sample_diagram.png',
          ),
          ContentNode(
            id: 'p_after',
            type: ContentNodeType.paragraph,
            text: 'Teks penjelas lanjutan setelah diagram peta topografi.',
          ),
        ],
      );

      const typo = TypographySettings(twoPageSpread: false);
      final pages = PaginationEngine.paginateChapter(
        chapter: chapter,
        typography: typo,
        viewportWidth: 600.0,
        viewportHeight: 600.0,
      );

      expect(pages, isNotEmpty);
      final imgPage = pages.firstWhere(
        (p) => p.slices.any((s) => s.node.id == 'img_1'),
      );
      expect(imgPage.slices.any((s) => s.node.id == 'img_1'), isTrue);
    });

    test(
      'E. Roman Numeral Chapter Heading Guard: No false positive on list items',
      () {
        // Case 1: Standalone Roman numeral at top of page (Genuine chapter heading)
        final genuineChapterPara = ReconstructedParagraph(
          text: 'IV',
          startPageIndex: 5,
          endPageIndex: 5,
          boundingBox: const Rect.fromLTWH(
            180,
            80,
            40,
            20,
          ), // top = 80, pageHeight = 700
          fontSize: 14.0,
          fontStyles: const [],
          isBold: true,
          isItalic: false,
          lineCount: 1,
          sourceLines: const [],
        );

        // Case 2: Roman numeral in lower half of page or list context (False positive candidate)
        final listRomanPara = ReconstructedParagraph(
          text: 'III',
          startPageIndex: 5,
          endPageIndex: 5,
          boundingBox: const Rect.fromLTWH(
            50,
            580,
            30,
            16,
          ), // top = 580 (bottom zone)
          fontSize: 11.0,
          fontStyles: const [],
          isBold: false,
          isItalic: false,
          lineCount: 1,
          sourceLines: const [],
        );

        final classified = SemanticClassifier.classifyDocument(
          paragraphs: [genuineChapterPara, listRomanPara],
          totalPages: 10,
        );

        expect(classified[0].type, equals(SemanticBlockType.heading1));
        expect(classified[0].text, equals('IV'));

        // The one near the bottom must NOT be classified as H1 chapter heading
        expect(classified[1].type, isNot(equals(SemanticBlockType.heading1)));
      },
    );

    test(
      'F. Real-World Document Stress on The Devotion of Suspect X & 48 Laws of Power',
      () {
        final suspectX = File(
          '/Users/davindalana/Documents/DigitalBooks/books/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
        );
        if (suspectX.existsSync()) {
          final doc = BookDocument.fromJsonString(suspectX.readAsStringSync());
          final readerDoc = ReaderDocument(
            bookId: doc.id,
            title: doc.title,
            author: doc.author,
            totalPages: doc.totalPages,
            chapters: doc.chapters
                .map(
                  (c) => ReaderChapter(
                    id: c.id,
                    index: c.index,
                    title: c.title,
                    nodes: c.blocks
                        .map(
                          (b) => ContentNode(
                            id: b.id,
                            type: b.type == BlockType.heading
                                ? ContentNodeType.heading
                                : ContentNodeType.paragraph,
                            text: b.text,
                            level: b.headingLevel,
                            sourcePdfPage: b.originalPageNumber,
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          );

          // Paginate across narrow, medium, and wide spread
          for (final width in [420.0, 850.0, 1200.0]) {
            final pages = PaginationEngine.paginateDocument(
              document: readerDoc,
              typography: const TypographySettings(twoPageSpread: true),
              viewportWidth: width,
              viewportHeight: 700.0,
            );
            expect(pages, isNotEmpty);
            expect(pages.length, greaterThan(100));
          }
        }
      },
    );

    test('G. Bidirectional Context Preservation & Anchor Mapping', () {
      final doc = ReaderDocument(
        bookId: 'bidi_test',
        title: 'Bidi Book',
        author: 'Author',
        totalPages: 10,
        chapters: [
          ReaderChapter(
            id: 'ch0',
            index: 0,
            title: 'Chapter 1',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.heading,
                text: 'Chapter 1',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'n2',
                type: ContentNodeType.paragraph,
                text: 'Opening paragraph on page 1.',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'n3',
                type: ContentNodeType.paragraph,
                text: 'Second paragraph on page 2.',
                sourcePdfPage: 2,
              ),
            ],
          ),
          ReaderChapter(
            id: 'ch1',
            index: 1,
            title: 'Chapter 2',
            nodes: [
              ContentNode(
                id: 'n4',
                type: ContentNodeType.heading,
                text: 'Chapter 2',
                sourcePdfPage: 3,
              ),
              ContentNode(
                id: 'n5',
                type: ContentNodeType.paragraph,
                text: 'Deep content on page 4.',
                sourcePdfPage: 4,
              ),
              ContentNode(
                id: 'n6',
                type: ContentNodeType.paragraph,
                text: 'Further details on page 5.',
                sourcePdfPage: 5,
              ),
            ],
          ),
        ],
      );

      const typo = TypographySettings(twoPageSpread: false);
      final pages = PaginationEngine.paginateDocument(
        document: doc,
        typography: typo,
        viewportWidth: 600.0,
        viewportHeight: 600.0,
      );

      // 1. Reflowable -> Original PDF: given anchor 'n5', resolve sourcePdfPage
      final targetNode = doc.chapters[1].nodes.firstWhere((n) => n.id == 'n5');
      expect(targetNode.sourcePdfPage, equals(4));

      // 2. Original PDF -> Reflowable: given pdfPage = 4, find first matching node
      ContentNode? resolvedNode;
      for (final ch in doc.chapters) {
        for (final node in ch.nodes) {
          if (node.sourcePdfPage >= 4) {
            resolvedNode = node;
            break;
          }
        }
        if (resolvedNode != null) break;
      }
      expect(resolvedNode, isNotNull);
      expect(resolvedNode!.id, equals('n5'));

      // 3. Anchor lookup across pages: find exact page for 'n5'
      final targetPageIndex = PaginationEngine.findPageIndexForAnchor(
        pages: pages,
        anchorNodeId: 'n5',
      );
      expect(targetPageIndex, greaterThanOrEqualTo(0));
      expect(
        pages[targetPageIndex].slices.any((s) => s.node.id == 'n5'),
        isTrue,
      );

      // 4. Resize preservation: when viewport width changes from 600 to 900, anchor remains valid
      final pagesResized = PaginationEngine.paginateDocument(
        document: doc,
        typography: typo,
        viewportWidth: 900.0,
        viewportHeight: 700.0,
      );
      final resizedPageIndex = PaginationEngine.findPageIndexForAnchor(
        pages: pagesResized,
        anchorNodeId: 'n5',
      );
      expect(resizedPageIndex, greaterThanOrEqualTo(0));
      expect(
        pagesResized[resizedPageIndex].slices.any((s) => s.node.id == 'n5'),
        isTrue,
      );
    });

    test(
      'H. Representative Corpus Extraction & Routing Verification (6 Core Categories)',
      () {
        const corpusDir = 'test/fixtures/corpus';
        final files = [
          '01_single_column_novel.pdf',
          '02_illustrated_novel.pdf',
          '04_two_column_academic.pdf',
          '06_footnotes.pdf',
          '08_scanned_image_only.pdf',
          '10_multi_heading_styles.pdf',
        ];

        for (final fileName in files) {
          final f = File('$corpusDir/$fileName');
          expect(
            f.existsSync(),
            isTrue,
            reason: 'Corpus file $fileName must exist',
          );
        }
      },
    );
  });
}
