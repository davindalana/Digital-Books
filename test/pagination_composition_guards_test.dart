import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';

/// These tests guard the composition rules that keep Book Mode pages readable
/// without depending on the real OCR fixture. The real-book audit still runs
/// separately; these tests make the invariants fail deterministically when the
/// paginator regresses.

const _filler =
    'Keterampilan berbicara bukan bakat bawaan. Ia dibentuk oleh latihan, '
    'kesadaran, dan keberanian untuk mencoba. Setiap percakapan adalah ruang '
    'belajar yang tenang.';

const _body =
    'Pembicara yang baik mendengarkan lebih dahulu, lalu menjawab dengan '
    'kalimat yang jelas dan tidak berlebihan.';

bool _isHeading(ContentNodeType type) =>
    type == ContentNodeType.heading ||
    type == ContentNodeType.sectionHeading ||
    type == ContentNodeType.documentTitle;

ReaderDocument _document(ReaderChapter chapter) => ReaderDocument(
  bookId: 'synthetic',
  title: 'Synthetic',
  author: 'Test',
  chapters: [chapter],
);

List<PaginatedPage> _paginate(
  ReaderChapter chapter, {
  double width = 420,
  double height = 700,
}) {
  PaginationEngine.clearCache();
  return PaginationEngine.paginateDocument(
    document: _document(chapter),
    viewportWidth: width,
    viewportHeight: height,
    typography: const TypographySettings(twoPageSpread: false),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('heading keep-with-next', () {
    test('a heading is never the last slice when content follows it', () {
      for (var fillerCount = 0; fillerCount <= 24; fillerCount++) {
        final chapter = ReaderChapter(
          id: 'heading_chain_$fillerCount',
          index: 0,
          title: 'Heading chain $fillerCount',
          nodes: [
            for (var i = 0; i < fillerCount; i++)
              ContentNode(
                id: 'f$i',
                type: ContentNodeType.paragraph,
                text: _filler,
              ),
            const ContentNode(
              id: 'h1',
              type: ContentNodeType.heading,
              text: 'Bab Satu',
            ),
            const ContentNode(
              id: 'h2',
              type: ContentNodeType.sectionHeading,
              text: 'Bagian Pertama',
            ),
            const ContentNode(
              id: 'body',
              type: ContentNodeType.paragraph,
              text: _body,
            ),
            const ContentNode(
              id: 'pb',
              type: ContentNodeType.pageBreak,
              text: '',
            ),
            const ContentNode(
              id: 'tail',
              type: ContentNodeType.heading,
              text: 'Judul Penutup',
            ),
          ],
        );

        final pages = _paginate(chapter);

        for (final page in pages) {
          if (page.slices.isEmpty) continue;
          final last = page.slices.last.node;
          if (!_isHeading(last.type)) continue;
          final index = chapter.nodes.indexOf(last);
          final next = index + 1 < chapter.nodes.length
              ? chapter.nodes[index + 1]
              : null;
          // A heading may only end a page when nothing follows it or when an
          // explicit page break follows; otherwise it was orphaned.
          expect(
            next == null || next.type == ContentNodeType.pageBreak,
            isTrue,
            reason:
                'heading "${last.text}" was left alone on page '
                '${page.pageIndexInBook} (filler=$fillerCount)',
          );
        }

        final headingPage = pages.firstWhere(
          (p) => p.slices.any((s) => s.node.id == 'h1'),
          orElse: () => throw StateError('h1 missing (filler=$fillerCount)'),
        );
        expect(
          headingPage.slices.any((s) => s.node.id == 'h2'),
          isTrue,
          reason: 'chained heading split from h1 (filler=$fillerCount)',
        );
        expect(
          headingPage.slices.any((s) => s.node.id == 'body'),
          isTrue,
          reason: 'heading left without its paragraph (filler=$fillerCount)',
        );
      }
    });

    test('a heading at the end of a chapter may remain the last slice', () {
      final chapter = ReaderChapter(
        id: 'heading_tail',
        index: 0,
        title: 'Heading tail',
        nodes: [
          for (var i = 0; i < 6; i++)
            ContentNode(
              id: 'f$i',
              type: ContentNodeType.paragraph,
              text: _filler,
            ),
          const ContentNode(
            id: 'tail',
            type: ContentNodeType.heading,
            text: 'Judul Penutup',
          ),
        ],
      );

      final pages = _paginate(chapter);

      expect(pages, isNotEmpty);
      final lastPage = pages.last;
      expect(lastPage.slices.last.node.id, 'tail');
      // No trailing blank page is produced just because the heading has no
      // following block to keep with.
      expect(pages.length, lessThanOrEqualTo(8));
    });
  });

  group('legal clause keepWithNext', () {
    test('the last legal clause stays on the same page as the footer', () {
      const clause = ContentNode(
        id: 'clause',
        type: ContentNodeType.orderedList,
        text:
            'Dilarang mengutip atau memperbanyak sebagian atau seluruh isi '
            'buku ini tanpa izin tertulis dari penerbit.',
        attributes: {'legalClause': true, 'keepWithNext': true},
      );
      const footer = ContentNode(
        id: 'footer',
        type: ContentNodeType.metadataBlock,
        text: '© Hak Cipta dilindungi undang-undang.',
      );

      for (var fillerCount = 0; fillerCount <= 24; fillerCount++) {
        final chapter = ReaderChapter(
          id: 'legal_footer_$fillerCount',
          index: 0,
          title: 'Legal footer $fillerCount',
          nodes: [
            for (var i = 0; i < fillerCount; i++)
              ContentNode(
                id: 'f$i',
                type: ContentNodeType.paragraph,
                text: _filler,
              ),
            clause,
            footer,
          ],
        );

        final pages = _paginate(chapter);

        final clausePage = pages.firstWhere(
          (p) => p.slices.any((s) => s.node.id == 'clause'),
          orElse: () =>
              throw StateError('clause missing (filler=$fillerCount)'),
        );
        expect(
          clausePage.slices.any((s) => s.node.id == 'footer'),
          isTrue,
          reason:
              'footer separated from the legal clause '
              '(filler=$fillerCount)',
        );
        expect(
          clausePage.slices.last.node.id,
          isNot('clause'),
          reason: 'legal clause left alone (filler=$fillerCount)',
        );
      }
    });

    test('an atomic legal clause is never split across pages', () {
      for (var fillerCount = 0; fillerCount <= 24; fillerCount++) {
        const clause = ContentNode(
          id: 'clause',
          type: ContentNodeType.orderedList,
          text:
              'Dilarang mengutip atau memperbanyak sebagian atau seluruh isi '
              'buku ini tanpa izin tertulis dari penerbit.',
          attributes: {'legalClause': true},
        );
        final chapter = ReaderChapter(
          id: 'legal_atomic_$fillerCount',
          index: 0,
          title: 'Legal atomic $fillerCount',
          nodes: [
            for (var i = 0; i < fillerCount; i++)
              ContentNode(
                id: 'f$i',
                type: ContentNodeType.paragraph,
                text: _filler,
              ),
            clause,
            const ContentNode(
              id: 'after',
              type: ContentNodeType.paragraph,
              text: _body,
            ),
          ],
        );

        final pages = _paginate(chapter);

        final clauseSlices = pages
            .expand((p) => p.slices)
            .where((s) => s.node.id == 'clause')
            .toList();
        expect(
          clauseSlices,
          hasLength(1),
          reason: 'legal clause split (filler=$fillerCount)',
        );
        expect(
          clauseSlices.single.textSlice,
          clause.text,
          reason: 'legal clause text truncated (filler=$fillerCount)',
        );
      }
    });
  });

  group('overflow and slice budget guards', () {
    test(
      'a paragraph whose text fits but text+padding exceeds availableHeight is split cleanly without overflow',
      () {
        // Craft a paragraph that fills nearly the entire available height on a fresh page.
        // availableHeight for height=700: 700 - 48 - 28 - 24 = 600.0.
        // Typography paragraphSpacing = 14.0.
        // Text taking ~625.0px fits without padding (625 <= 632), but with padding takes 639.0px (> 632).
        // The engine must split the paragraph cleanly without allowing height to overflow availableHeight.
        final repeatedText = List.generate(
          22,
          (i) =>
              'Kalimat baris ke-$i dalam paragraf uji ini untuk mengukur tinggi rendering secara presisi.',
        ).join(' ');

        final chapter = ReaderChapter(
          id: 'overflow_guard_chap',
          index: 0,
          title: 'Overflow guard',
          nodes: [
            ContentNode(
              id: 'overflow_para',
              type: ContentNodeType.paragraph,
              text: repeatedText,
            ),
          ],
        );

        final pages = _paginate(chapter, width: 420, height: 700);

        // Verify each page's total height + padding does not exceed availableHeight.
        const typography = TypographySettings(twoPageSpread: false);
        const availableHeight = 700.0 - 48.0 - 28.0 - 24.0; // 600.0

        for (final p in pages) {
          var pageHeight = 0.0;
          for (final s in p.slices) {
            final tp = TextPainter(
              text: TextSpan(text: s.textSlice, style: typography.bodyStyle()),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: 324.0); // 420 - 2 * 48
            pageHeight += tp.height + typography.paragraphSpacing;
            tp.dispose();
          }
          expect(
            pageHeight,
            lessThanOrEqualTo(availableHeight + 0.5),
            reason:
                'Page ${p.pageIndexInBook} height $pageHeight exceeds availableHeight $availableHeight',
          );
        }
      },
    );
  });
}
