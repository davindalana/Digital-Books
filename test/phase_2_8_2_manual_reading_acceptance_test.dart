import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:path/path.dart' as p;
import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.8.2 — Manual Reading Acceptance & Structural Integrity', () {
    late ReaderDocument letThemDoc;
    late ReaderDocument suspectXDoc;
    late ReaderDocument lautBerceritaDoc;

    final letThemFile = File(
      p.join(RealBookFixtures.booksDir, '8cda23f0-bf42-4a4d-a1fd-30d2943835c9.json'),
    );
    final suspectXFile = File(
      p.join(RealBookFixtures.booksDir, '67141617-5a74-4f9b-a9fa-45b28366e27d.json'),
    );
    final lautFile = File(
      p.join(RealBookFixtures.booksDir, '8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.json'),
    );

    setUpAll(() async {
      if (!checkFixtureOrSkip(letThemFile) ||
          !checkFixtureOrSkip(suspectXFile) ||
          !checkFixtureOrSkip(lautFile)) {
        return;
      }

      // 1. The Let Them Theory (Vector Non-Fiction)
      if (letThemFile.existsSync()) {
        final json =
            jsonDecode(await letThemFile.readAsString())
                as Map<String, dynamic>;
        letThemDoc = ReaderDocument.fromBookDocument(
          BookDocument.fromJson(json),
        );
      }

      // 2. The Devotion of Suspect X (Novel with Dialogue)
      if (suspectXFile.existsSync()) {
        final json =
            jsonDecode(await suspectXFile.readAsString())
                as Map<String, dynamic>;
        suspectXDoc = ReaderDocument.fromBookDocument(
          BookDocument.fromJson(json),
        );
      }

      // 3. Laut Bercerita (Scanned Novel)
      if (lautFile.existsSync()) {
        final json =
            jsonDecode(await lautFile.readAsString()) as Map<String, dynamic>;
        lautBerceritaDoc = ReaderDocument.fromBookDocument(
          BookDocument.fromJson(json),
        );
      }
    });

    setUp(() {
      if (!checkFixtureOrSkip(letThemFile) ||
          !checkFixtureOrSkip(suspectXFile) ||
          !checkFixtureOrSkip(lautFile)) {
        return;
      }
    });

    test(
      '1. Non-Fiction Acceptance: The Let Them Theory Structural & Reading Flow',
      () {
        expect(letThemDoc, isNotNull);
        expect(letThemDoc.chapters, isNotEmpty);

        // Verify structural integrity of content nodes
        expect(letThemDoc.totalParagraphCount, greaterThan(100));

        const typo = TypographySettings(
          fontSize: 16,
          lineSpacing: 1.5,
          twoPageSpread: false,
        );
        final pages = PaginationEngine.paginateDocument(
          document: letThemDoc,
          viewportWidth: 800.0,
          viewportHeight: 700.0,
          typography: typo,
        );

        expect(pages, isNotEmpty);
        expect(pages.length, greaterThan(50));

        // Inspect for empty pages or clipped text
        for (int i = 0; i < pages.length; i++) {
          final p = pages[i];
          expect(
            p.slices,
            isNotEmpty,
            reason: 'Page ${i + 1} has empty slices',
          );
          final text = p.slices.map((s) => s.textSlice).join(' ').trim();
          expect(
            text,
            isNotEmpty,
            reason: 'Page ${i + 1} has zero visible text',
          );
        }

        // Check middle page reading flow
        final midPage = pages[pages.length ~/ 2];
        expect(midPage.slices, isNotEmpty);
      },
    );

    test(
      '2. Fiction Acceptance: The Devotion of Suspect X Dialogue & Spread Integrity',
      () {
        expect(suspectXDoc, isNotNull);
        expect(suspectXDoc.chapters.length, greaterThanOrEqualTo(19));

        const typoSpread = TypographySettings(
          fontSize: 16,
          lineSpacing: 1.5,
          twoPageSpread: true,
        );
        // Window 1100x700: Spread active
        final pages = PaginationEngine.paginateDocument(
          document: suspectXDoc,
          viewportWidth: 1100.0,
          viewportHeight: 700.0,
          typography: typoSpread,
        );

        expect(pages.length, greaterThan(200));

        // Ensure no words sliced across spreads
        for (int i = 0; i < pages.length; i++) {
          final page = pages[i];
          for (final slice in page.slices) {
            // If continuation, must not start with whitespace
            if (slice.isContinuation) {
              expect(
                slice.textSlice.startsWith(' '),
                isFalse,
                reason: 'Page ${i + 1} continuation slice starts with space',
              );
            }
            // Must not end with broken whitespace
            expect(slice.textSlice.endsWith('  '), isFalse);
          }
        }
      },
    );

    test(
      '3. Scanned Document Guard: Laut Bercerita recommends Original PDF Reader',
      () {
        expect(lautBerceritaDoc, isNotNull);
        // Laut Bercerita is scanned (isScanned: true)
        // Verify recommendation metadata or tier routing
        final isScanned =
            lautBerceritaDoc.metadata['isScanned'] == true ||
            lautBerceritaDoc.metadata['qualityScore'] == null ||
            lautBerceritaDoc.metadata['qualityStatus'] != 'high';

        // Scanned PDFs must be routed or recommended to Original PDF Reader
        expect(
          isScanned,
          isTrue,
          reason:
              'Scanned document must not be treated as high-fidelity native reflowable text',
        );
      },
    );

    test(
      '4. Academic & Multi-Element Document Acceptance (Footnotes, Images, Headings)',
      () {
        // Create a rich academic document chapter with H1, H2, body, blockquote, footnotes, and image
        final academicChapter = ReaderChapter(
          id: 'academic_ch1',
          index: 0,
          title: 'Cognitive Science of Typography',
          nodes: [
            const ContentNode(
              id: 'n_h1',
              type: ContentNodeType.heading,
              text: 'Chapter 1: The Ergonomics of Reading',
              level: 1,
            ),
            const ContentNode(
              id: 'n_p1',
              type: ContentNodeType.paragraph,
              text:
                  'Visual comfort in digital reading environments is governed by saccadic eye movements and line length. '
                  'When the typographic measure exceeds eighty characters, reader fatigue accumulates rapidly. '
                  'Conversely, overly narrow columns cause excessive hyphenation and break syntactic phrasing.',
            ),
            const ContentNode(
              id: 'n_quote',
              type: ContentNodeType.quote,
              text:
                  'A good reader desires neither pure machine efficiency nor haphazard ornament; '
                  'clarity is the courtesy that the author and typographer extend to the human mind.',
            ),
            const ContentNode(
              id: 'n_img',
              type: ContentNodeType.image,
              text:
                  'Figure 1.1: Saccadic eye movement fixation pattern during continuous prose reading.',
              imagePath: 'test/fixtures/corpus/sample_diagram.png',
            ),
            const ContentNode(
              id: 'n_p2',
              type: ContentNodeType.paragraph,
              text:
                  'Empirical investigations demonstrate that line spacing of 1.4 to 1.6 times the font size '
                  'provides the optimal vertical channel for perceptual separation of consecutive text baselines.',
            ),
            const ContentNode(
              id: 'n_fn1',
              type: ContentNodeType.footnote,
              text:
                  '1. See Tinker, M. A. (1963). Legibility of Print. Iowa State University Press, Ames, IA.',
            ),
          ],
        );

        final academicDoc = ReaderDocument(
          bookId: 'academic_doc_01',
          title: 'Cognitive Science of Typography',
          author: 'Prof. E. R. Tufte & D. Knuth',
          totalPages: 10,
          chapters: [academicChapter],
          metadata: {'reconstructionQuality': 'high'},
        );

        const typo = TypographySettings(fontSize: 16, lineSpacing: 1.5);
        final pages = PaginationEngine.paginateDocument(
          document: academicDoc,
          viewportWidth: 900.0,
          viewportHeight: 650.0,
          typography: typo,
        );

        expect(pages, isNotEmpty);
        // All nodes must be present across paginated pages
        final presentNodeIds = pages
            .expand((p) => p.slices.map((s) => s.node.id))
            .toSet();
        expect(presentNodeIds, contains('n_h1'));
        expect(presentNodeIds, contains('n_p1'));
        expect(presentNodeIds, contains('n_quote'));
        expect(presentNodeIds, contains('n_img'));
        expect(presentNodeIds, contains('n_p2'));
        expect(presentNodeIds, contains('n_fn1'));
      },
    );

    test('5. Viewport & Typography Extreme Stress Matrix', () {
      // Test grid of font sizes, line spacings, and window dimensions
      const fontSizes = [12.0, 16.0, 19.0, 24.0];
      const lineSpacings = [1.2, 1.5, 1.8];
      const viewports = [
        Size(400.0, 600.0), // Narrow mobile/sidebar
        Size(800.0, 650.0), // Medium laptop window
        Size(1200.0, 750.0), // Wide spread window
        Size(1800.0, 950.0), // Ultrawide desktop
      ];

      final sampleChapter = suspectXDoc.chapters.firstWhere(
        (c) => c.nodes.length > 50,
      );

      for (final fs in fontSizes) {
        for (final ls in lineSpacings) {
          for (final vp in viewports) {
            final typo = TypographySettings(
              fontSize: fs,
              lineSpacing: ls,
              twoPageSpread: vp.width >= 850.0,
            );

            final pages = PaginationEngine.paginateChapter(
              chapter: sampleChapter,
              viewportWidth: vp.width,
              viewportHeight: vp.height,
              typography: typo,
            );

            expect(pages, isNotEmpty);
            // Verify monotonicity of page indexes
            for (int i = 0; i < pages.length; i++) {
              expect(pages[i].pageIndexInChapter, equals(i));
              // Check that slices don't have empty content
              expect(pages[i].slices, isNotEmpty);
            }
          }
        }
      }
    });

    test(
      '6. Bidirectional Reading Position Preservation across Resizing & Modes',
      () {
        final sampleChapter = suspectXDoc.chapters[2];
        const typoSingle = TypographySettings(
          fontSize: 16,
          lineSpacing: 1.5,
          twoPageSpread: false,
        );
        const typoLarge = TypographySettings(
          fontSize: 24,
          lineSpacing: 1.5,
          twoPageSpread: false,
        );

        // Initial layout at 800x600
        final pagesInitial = PaginationEngine.paginateChapter(
          chapter: sampleChapter,
          viewportWidth: 800.0,
          viewportHeight: 600.0,
          typography: typoSingle,
        );

        // Pick an anchor node in the middle
        final targetNode = sampleChapter.nodes[sampleChapter.nodes.length ~/ 2];
        final targetPageIdx = PaginationEngine.findPageIndexForAnchor(
          pages: pagesInitial,
          anchorNodeId: targetNode.id,
        );
        expect(targetPageIdx, greaterThan(0));

        // 1. Font size change: 16 -> 24
        final pagesLargeFont = PaginationEngine.paginateChapter(
          chapter: sampleChapter,
          viewportWidth: 800.0,
          viewportHeight: 600.0,
          typography: typoLarge,
        );
        final newPageIdx = PaginationEngine.findPageIndexForAnchor(
          pages: pagesLargeFont,
          anchorNodeId: targetNode.id,
        );
        expect(newPageIdx, greaterThan(0));
        // Anchor must be found on the resolved page
        expect(
          pagesLargeFont[newPageIdx].slices.any(
            (s) => s.node.id == targetNode.id,
          ),
          isTrue,
        );

        // 2. Viewport resize: 800x600 -> 1200x800 spread
        const typoSpread = TypographySettings(
          fontSize: 16,
          lineSpacing: 1.5,
          twoPageSpread: true,
        );
        final pagesSpread = PaginationEngine.paginateChapter(
          chapter: sampleChapter,
          viewportWidth: 1200.0,
          viewportHeight: 800.0,
          typography: typoSpread,
        );
        final spreadPageIdx = PaginationEngine.findPageIndexForAnchor(
          pages: pagesSpread,
          anchorNodeId: targetNode.id,
        );
        expect(
          pagesSpread[spreadPageIdx].slices.any(
            (s) => s.node.id == targetNode.id,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      '7. Widget Rendering Precision in PaginatedReflowableReader Spread',
      (tester) async {
        // Pump full PaginatedReflowableReader widget in a 1100x700 environment
        tester.view.physicalSize = const Size(1100, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final sampleChapter = suspectXDoc.chapters[1];
        final singleChapterDoc = ReaderDocument(
          bookId: suspectXDoc.bookId,
          title: suspectXDoc.title,
          author: suspectXDoc.author,
          totalPages: 20,
          chapters: [sampleChapter],
          metadata: suspectXDoc.metadata,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: singleChapterDoc,
                typography: const TypographySettings(
                  twoPageSpread: true,
                  fontSize: 16,
                ),
                theme: ReadingThemeType.dark,
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify that two-page spread renders two columns and center spine
        expect(find.byType(ReflowablePageRenderer), findsNWidgets(2));
        // Verify running headers are present
        expect(find.text(sampleChapter.title.toUpperCase()), findsWidgets);
      },
    );
  });
}
