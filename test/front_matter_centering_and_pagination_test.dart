import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
  final jsonFile = File(
    '/Users/davindalana/Documents/DigitalBooks/books/$bookId.json',
  );

  group('Front Matter Centering and Pagination Quality', () {
    testWidgets(
      'ReflowablePageRenderer vertically centers all front matter pages',
      (tester) async {
        // 1. Cover page
        final coverPage = PaginatedPage(
          pageIndexInChapter: 0,
          pageIndexInBook: 0,
          chapterIndex: 0,
          chapterTitle: 'Bagian Awal',
          firstAnchorNodeId: 'node_cover',
          lastAnchorNodeId: 'node_cover',
          slices: [
            PaginatedNodeSlice(
              node: ContentNode(
                id: 'node_cover',
                type: ContentNodeType.documentTitle,
                text: 'BICARA ITU ADA SENINYA',
                attributes: const {'frontMatter': 'cover'},
              ),
              textSlice: 'BICARA ITU ADA SENINYA',
              startCharOffset: 0,
              endCharOffset: 23,
            ),
          ],
        );

        // 2. Copyright page
        final copyrightPage = PaginatedPage(
          pageIndexInChapter: 1,
          pageIndexInBook: 1,
          chapterIndex: 0,
          chapterTitle: 'Bagian Awal',
          firstAnchorNodeId: 'node_copy',
          lastAnchorNodeId: 'node_copy',
          slices: [
            PaginatedNodeSlice(
              node: ContentNode(
                id: 'node_copy',
                type: ContentNodeType.metadataBlock,
                text: 'THE SECRET HABITS TO MASTER YOUR ART OF SPEAKING',
                attributes: const {
                  'frontMatter': 'copyright',
                  'kind': 'identity',
                },
              ),
              textSlice: 'THE SECRET HABITS TO MASTER YOUR ART OF SPEAKING',
              startCharOffset: 0,
              endCharOffset: 48,
            ),
          ],
        );

        // 3. Body page (must remain top-centered)
        final bodyPage = PaginatedPage(
          pageIndexInChapter: 0,
          pageIndexInBook: 14,
          chapterIndex: 4,
          chapterTitle: 'BAB I',
          firstAnchorNodeId: 'node_body',
          lastAnchorNodeId: 'node_body',
          slices: [
            PaginatedNodeSlice(
              node: ContentNode(
                id: 'node_body',
                type: ContentNodeType.paragraph,
                text: 'Perbedaan Juara 1 dan Juara 2.',
              ),
              textSlice: 'Perbedaan Juara 1 dan Juara 2.',
              startCharOffset: 0,
              endCharOffset: 30,
            ),
          ],
        );

        Widget buildPage(PaginatedPage p) {
          return MaterialApp(
            home: Scaffold(
              body: ReflowablePageRenderer(
                page: p,
                totalPagesInBook: 200,
                contentWidth: 400,
                typography: const TypographySettings(),
                theme: ReadingThemeType.dark,
              ),
            ),
          );
        }

        // Verify cover is centered
        await tester.pumpWidget(buildPage(coverPage));
        var fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
        expect(
          fittedBox.alignment,
          Alignment.center,
          reason: 'Cover page must be centered',
        );

        // Verify copyright page is centered (preventing asymmetric empty space at bottom)
        await tester.pumpWidget(buildPage(copyrightPage));
        fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
        expect(
          fittedBox.alignment,
          Alignment.center,
          reason: 'Copyright page must be centered',
        );

        // Verify regular body page is topCenter (standard reading flow)
        await tester.pumpWidget(buildPage(bodyPage));
        fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
        expect(
          fittedBox.alignment,
          Alignment.topCenter,
          reason: 'Body page must align to topCenter',
        );
      },
    );

    test(
      'PaginationEngine styles copyright and metadata blocks faithfully',
      () {
        final typo = const TypographySettings(fontSize: 18.0);

        // OrderedList with legalClause uses 0.80x bodyStyle
        final legalNode = ContentNode(
          id: 'legal1',
          type: ContentNodeType.orderedList,
          text: '1. Setiap orang yang dengan tanpa hak...',
          attributes: const {'legalClause': true},
        );
        final legalStyle = PaginationEngine.textStyleFor(legalNode, typo);
        expect(legalStyle.fontSize, closeTo(18.0 * 0.80, 0.01));
        expect(PaginationEngine.paddingFor(legalNode, typo), 5.0);

        // MetadataBlock publisher uses 0.72x
        final publisherNode = ContentNode(
          id: 'pub1',
          type: ContentNodeType.metadataBlock,
          text: 'Penerbit Bhuana Ilmu Populer',
          attributes: const {'kind': 'publisher'},
        );
        final pubStyle = PaginationEngine.textStyleFor(publisherNode, typo);
        expect(pubStyle.fontSize, closeTo(18.0 * 0.72, 0.01));

        // MetadataBlock catalog with sectionLabel
        final catalogNode = ContentNode(
          id: 'cat1',
          type: ContentNodeType.metadataBlock,
          text: 'ISBN 978-602-455-392-0',
          attributes: const {
            'kind': 'catalog',
            'sectionLabel': 'Informasi Penerbitan',
          },
        );
        final catStyle = PaginationEngine.textStyleFor(catalogNode, typo);
        expect(catStyle.fontSize, closeTo(18.0 * 0.80, 0.01));
        expect(
          PaginationEngine.paddingFor(catalogNode, typo),
          closeTo(22.0 + (typo.paragraphSpacing * 0.5), 0.01),
        );
      },
    );

    test('Real book Chapter 0 paginates cleanly without fragmentation', () {
      if (!jsonFile.existsSync()) {
        markTestSkipped('Processed book JSON is missing at ${jsonFile.path}');
        return;
      }

      final bookDoc = BookDocument.fromJson(
        jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>,
      );
      final readerDoc = ReflowableEngine.normalizeDocument(bookDoc);
      final typo = const TypographySettings(twoPageSpread: true);

      PaginationEngine.clearCache();
      final pages = PaginationEngine.paginateDocument(
        document: readerDoc,
        viewportWidth: 1102,
        viewportHeight: 951,
        typography: typo,
      );

      final ch0Pages = pages.where((p) => p.chapterIndex == 0).toList();
      // Previously fragmented into 8 pages; now neatly grouped in 5 pages:
      // Page 1: Cover
      // Page 2: Imprint (identity + catalog + publisher + legal)
      // Page 3: Sanksi Pelanggaran + clause 1 + clause 2
      // Page 4: Clause 3 + clause 4 + footer
      // Page 5: Title page ("Oleh Oh Su Hyang")
      expect(ch0Pages.length, lessThanOrEqualTo(5));

      final page2 = ch0Pages[1];
      final page2Kinds = page2.slices
          .map((s) => s.node.attributes['kind'])
          .toSet();
      expect(
        page2Kinds,
        containsAll(['identity', 'catalog', 'publisher', 'legal']),
        reason: 'Page 2 should contain all imprint and catalog metadata',
      );
    });
  });
}
