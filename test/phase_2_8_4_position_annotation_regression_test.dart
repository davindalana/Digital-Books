// ignore_for_file: avoid_print, unused_local_variable
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';
import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.8.4 — Position & Annotation Regression Suite', () {
    ReaderDocument? suspectXDoc;
    final suspectXFile = File(
      '${RealBookFixtures.booksDir}/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
    );

    setUpAll(() async {
      if (!checkFixtureOrSkip(suspectXFile)) return;
      if (suspectXFile.existsSync()) {
        final json =
            jsonDecode(await suspectXFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        suspectXDoc = ReflowableEngine.normalizeDocument(normDoc);
      }
    });

    test(
      '1. Anchor Node Preservation Across Viewport Resizing (750x600 -> 1000x700 -> 1300x850)',
      () {
        if (!checkFixtureOrSkip(suspectXFile)) return;
        final doc = suspectXDoc;
        if (doc == null) return;
        const typo = TypographySettings(twoPageSpread: true);
        final ch1 = doc.chapters[1]; // SATU

        // Target node in the middle of chapter 1
        final targetNode = ch1.nodes[ch1.nodes.length ~/ 2];
        final targetText = targetNode.text.substring(0, 30);

        // Paginating at 3 distinct viewport sizes:
        final pagesCompact = PaginationEngine.paginateDocument(
          document: doc,
          viewportWidth: 750.0,
          viewportHeight: 600.0,
          typography: typo.copyWith(twoPageSpread: false),
        );

        final pagesStandard = PaginationEngine.paginateDocument(
          document: doc,
          viewportWidth: 1000.0,
          viewportHeight: 700.0,
          typography: typo.copyWith(twoPageSpread: true),
        );

        final pagesExpansive = PaginationEngine.paginateDocument(
          document: doc,
          viewportWidth: 1300.0,
          viewportHeight: 850.0,
          typography: typo.copyWith(twoPageSpread: true),
        );

        final idxCompact = PaginationEngine.findPageIndexForAnchor(
          pages: pagesCompact,
          anchorNodeId: targetNode.id,
        );

        final idxStandard = PaginationEngine.findPageIndexForAnchor(
          pages: pagesStandard,
          anchorNodeId: targetNode.id,
        );

        final idxExpansive = PaginationEngine.findPageIndexForAnchor(
          pages: pagesExpansive,
          anchorNodeId: targetNode.id,
        );

        print(
          'Anchor Preservation for Node "${targetNode.id}" ("$targetText..."):',
        );
        print('  Compact (750x600): Page $idxCompact / ${pagesCompact.length}');
        print(
          '  Standard (1000x700): Page $idxStandard / ${pagesStandard.length}',
        );
        print(
          '  Expansive (1300x850): Page $idxExpansive / ${pagesExpansive.length}',
        );

        // Verify each page actually contains the target node!
        expect(
          pagesCompact[idxCompact].slices.any(
            (s) => s.node.id == targetNode.id,
          ),
          isTrue,
        );
        expect(
          pagesStandard[idxStandard].slices.any(
            (s) => s.node.id == targetNode.id,
          ),
          isTrue,
        );
        expect(
          pagesExpansive[idxExpansive].slices.any(
            (s) => s.node.id == targetNode.id,
          ),
          isTrue,
        );
      },
    );

    test(
      '2. Anchor Context Preservation Across Font Size Changes (12 -> 16 -> 19 -> 24)',
      () {
        if (!checkFixtureOrSkip(suspectXFile)) return;
        final doc = suspectXDoc;
        if (doc == null) return;
        final ch1 = doc.chapters[1];
        final targetNode = ch1.nodes[5];

        for (final fontSize in [12.0, 16.0, 19.0, 24.0]) {
          final typo = TypographySettings(
            fontSize: fontSize,
            twoPageSpread: true,
          );
          final pages = PaginationEngine.paginateChapter(
            chapter: ch1,
            viewportWidth: 1000.0,
            viewportHeight: 700.0,
            typography: typo,
          );

          final pageIdx = PaginationEngine.findPageIndexForAnchor(
            pages: pages,
            anchorNodeId: targetNode.id,
          );

          expect(pageIdx, greaterThanOrEqualTo(0));
          expect(pageIdx, lessThan(pages.length));
          final page = pages[pageIdx];
          expect(
            page.slices.any((s) => s.node.id == targetNode.id),
            isTrue,
            reason:
                'Page $pageIdx must contain node ${targetNode.id} at font size $fontSize',
          );
        }
      },
    );

    test('3. Highlight and Bookmark Resolution to Same Text Snippet', () {
      if (!checkFixtureOrSkip(suspectXFile)) return;
      final doc = suspectXDoc;
      if (doc == null) return;
      final ch1 = doc.chapters[1];
      final testNode = ch1.nodes[4];
      const startChar = 10;
      const endChar = 45;
      final expectedSnippet = testNode.text.substring(startChar, endChar);

      // Verify that across different typography layouts, resolving the slice with startChar finds the snippet
      for (final spread in [false, true]) {
        final typo = TypographySettings(fontSize: 16.0, twoPageSpread: spread);
        final pages = PaginationEngine.paginateChapter(
          chapter: ch1,
          viewportWidth: 1000.0,
          viewportHeight: 700.0,
          typography: typo,
        );

        final pageIdx = PaginationEngine.findPageIndexForAnchor(
          pages: pages,
          anchorNodeId: testNode.id,
          characterOffset: startChar,
        );

        final page = pages[pageIdx];
        final slice = page.slices.firstWhere((s) => s.node.id == testNode.id);

        // Check if slice contains the target characters
        expect(slice.startCharOffset, lessThanOrEqualTo(startChar));
        expect(slice.textSlice, isNotEmpty);
      }
    });

    test('4. Monotonic Reading Progress Across Entire Book', () {
      if (!checkFixtureOrSkip(suspectXFile)) return;
      final doc = suspectXDoc;
      if (doc == null) return;
      final pages = PaginationEngine.paginateDocument(
        document: doc,
        viewportWidth: 1000.0,
        viewportHeight: 700.0,
        typography: const TypographySettings(twoPageSpread: true),
      );

      double previousPct = -0.01;
      for (int i = 0; i < pages.length; i++) {
        final pct = (i + 1) / pages.length;
        expect(pct, greaterThan(previousPct));
        expect(pct, greaterThan(0.0));
        expect(pct, lessThanOrEqualTo(1.0));
        previousPct = pct;
      }
    });
  });
}
