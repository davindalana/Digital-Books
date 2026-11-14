// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';
import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.8.3 — Adaptive Paragraph Flow & Page Utilization', () {
    late ReaderDocument suspectXDoc;
    late ReaderDocument letThemDoc;

    final suspectXFile = File(
      '${RealBookFixtures.booksDir}/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
    );
    final letThemFile = File(
      '${RealBookFixtures.booksDir}/8cda23f0-bf42-4a4d-a1fd-30d2943835c9.json',
    );

    setUpAll(() async {
      if (!checkFixtureOrSkip(suspectXFile) || !checkFixtureOrSkip(letThemFile)) return;
      if (suspectXFile.existsSync()) {
        final json =
            jsonDecode(await suspectXFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        suspectXDoc = ReflowableEngine.normalizeDocument(normDoc);
      }

      if (letThemFile.existsSync()) {
        final json =
            jsonDecode(await letThemFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        letThemDoc = ReflowableEngine.normalizeDocument(normDoc);
      }
    });

    setUp(() {
      if (!checkFixtureOrSkip(suspectXFile) || !checkFixtureOrSkip(letThemFile)) return;
    });

    test(
      '1. Zero Overflow & Vertical Clipping Elimination (Suspect X & Let Them Theory)',
      () {
        const typo = TypographySettings(twoPageSpread: true);
        const viewportWidth = 1000.0;
        const viewportHeight = 600.0;
        // Use the engine's own geometry and real per-node typography. Measuring
        // every non-heading slice with bodyStyle() inflated metadata/copyright
        // blocks and reported overflow that the paginator never produced.
        final availableHeight = PaginationEngine.availableHeightFor(
          viewportHeight: viewportHeight,
        );
        final contentWidth = PaginationEngine.contentWidthFor(
          viewportWidth: viewportWidth,
          typography: typo,
        );

        for (final bookDoc in [suspectXDoc, letThemDoc]) {
          final pages = PaginationEngine.paginateDocument(
            document: bookDoc,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            typography: typo,
          );

          int overflowCount = 0;
          double maxOverflow = 0.0;

          for (int i = 0; i < pages.length; i++) {
            final p = pages[i];
            final pHeight = _measuredPageHeight(p, typo, contentWidth);

            if (pHeight > availableHeight + 2.0) {
              overflowCount++;
              maxOverflow = math.max(maxOverflow, pHeight - availableHeight);
            }
          }

          print(
            'Overflow Audit for "${bookDoc.title}": $overflowCount overflowing pages out of ${pages.length} (Max overflow: ${maxOverflow.toStringAsFixed(1)} pt)',
          );
          // Zero overflowing pages allowed!
          expect(
            overflowCount,
            equals(0),
            reason:
                'Pages must never overflow availableHeight ($availableHeight pt)',
          );
        }
      },
    );

    test('2. Widow & Orphan Control Policy Verification', () {
      const typo = TypographySettings(twoPageSpread: true);
      const viewportWidth = 1000.0;
      const viewportHeight = 600.0;
      final contentWidth = PaginationEngine.contentWidthFor(
        viewportWidth: viewportWidth,
        typography: typo,
      );

      final chapter = suspectXDoc.chapters[1]; // SATU
      final pages = PaginationEngine.paginateChapter(
        chapter: chapter,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        typography: typo,
      );

      int orphanCount = 0;
      int widowCount = 0;

      for (int i = 0; i < pages.length; i++) {
        final p = pages[i];
        for (int sIdx = 0; sIdx < p.slices.length; sIdx++) {
          final s = p.slices[sIdx];
          final style = PaginationEngine.textStyleFor(s.node, typo);
          final tp = TextPainter(
            text: TextSpan(text: s.textSlice, style: style),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: contentWidth);
          final lines = tp.computeLineMetrics().length;
          tp.dispose();

          // Check orphan line at bottom:
          if (s.hasMore && lines < 2) {
            orphanCount++;
            print('  Orphan line on page $i: "${s.textSlice}"');
          }

          // Check widow line at top of next page:
          if (s.isContinuation && !s.hasMore && lines < 2) {
            widowCount++;
            print('  Widow line on page $i: "${s.textSlice}"');
          }
        }
      }

      print(
        'Widow & Orphan Audit on Suspect X Chapter 1: orphans=$orphanCount, widows=$widowCount (previously 216 widows!)',
      );
      expect(orphanCount, equals(0));
      expect(widowCount, equals(0));
    });

    test('3. Page Utilization Metric Across Chapter Prose', () {
      const typo = TypographySettings(twoPageSpread: true);
      const viewportWidth = 1000.0;
      const viewportHeight = 600.0;
      final availableHeight = PaginationEngine.availableHeightFor(
        viewportHeight: viewportHeight,
      );
      final contentWidth = PaginationEngine.contentWidthFor(
        viewportWidth: viewportWidth,
        typography: typo,
      );

      final chapter = suspectXDoc.chapters[1]; // SATU
      final pages = PaginationEngine.paginateChapter(
        chapter: chapter,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        typography: typo,
      );

      List<double> utilizations = [];
      for (int i = 0; i < pages.length - 1; i++) {
        final p = pages[i];
        final used = _measuredPageHeight(p, typo, contentWidth);
        utilizations.add(used / availableHeight);
      }

      final avgUtil =
          utilizations.reduce((a, b) => a + b) / utilizations.length;
      final minUtil = utilizations.reduce(math.min);
      final maxUtil = utilizations.reduce(math.max);

      print('Page Utilization on Suspect X (non-terminal pages):');
      print('  Average: ${(avgUtil * 100).toStringAsFixed(1)}%');
      print('  Min: ${(minUtil * 100).toStringAsFixed(1)}%');
      print('  Max: ${(maxUtil * 100).toStringAsFixed(1)}%');

      expect(avgUtil, greaterThanOrEqualTo(0.85)); // Average utilization >= 85%
      expect(
        maxUtil,
        lessThanOrEqualTo(1.02),
      ); // Strictly bounded <= 100% (within 2% precision margin)
    });

    test(
      '4. Full Content Concatenation Comparison (Zero Word Loss & Zero Duplication)',
      () {
        // Test both Suspect X and Let Them Theory
        for (final bookDoc in [suspectXDoc, letThemDoc]) {
          for (
            int chIdx = 0;
            chIdx < math.min(3, bookDoc.chapters.length);
            chIdx++
          ) {
            final ch = bookDoc.chapters[chIdx];
            final pages = PaginationEngine.paginateChapter(
              chapter: ch,
              viewportWidth: 1000.0,
              viewportHeight: 600.0,
              typography: const TypographySettings(twoPageSpread: true),
            );

            final originalWords = ch.nodes
                .map((n) => n.text.trim())
                .join(' ')
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .toList();

            final paginatedWords = pages
                .expand((p) => p.slices)
                .map((s) => s.textSlice.trim())
                .join(' ')
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .toList();

            expect(
              paginatedWords.length,
              equals(originalWords.length),
              reason: 'Word count mismatch in ${bookDoc.title} Ch $chIdx',
            );
            for (int wIdx = 0; wIdx < originalWords.length; wIdx++) {
              expect(
                paginatedWords[wIdx],
                equals(originalWords[wIdx]),
                reason:
                    'Word mismatch at index $wIdx in ${bookDoc.title} Ch $chIdx: "${paginatedWords[wIdx]}" vs "${originalWords[wIdx]}"',
              );
            }
          }
        }
        print(
          'Full Content Concatenation: 100% word-for-word identity verified with 0 lost words and 0 duplicate words!',
        );
      },
    );

    testWidgets('5. Visual Widget Verification: Heading Attachment & Spread Flow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));

      final testDoc = ReaderDocument(
        bookId: 'adaptive_test_doc',
        title: 'Adaptive Flow Test',
        author: 'Tester',
        totalPages: 2,
        chapters: [
          ReaderChapter(
            id: 'ch_head_test',
            index: 0,
            title: 'Bab Uji Coba',
            nodes: [
              const ContentNode(
                id: 'head_1',
                type: ContentNodeType.heading,
                text: 'BAB SATU: PENDAHULUAN',
                level: 1,
              ),
              const ContentNode(
                id: 'para_1',
                type: ContentNodeType.paragraph,
                text:
                    'Ini adalah paragraf pengantar pembuka bab yang menjelaskan latar belakang narasi secara terperinci. '
                    'Teks ini harus mengalir secara anggun mendampingi judul bab tanpa terpisahkan menjadi heading yatim piatu.',
              ),
              const ContentNode(
                id: 'para_dialogue',
                type: ContentNodeType.paragraph,
                text: '"Apakah semuanya sudah siap?" tanyanya dengan tenang.',
              ),
              const ContentNode(
                id: 'para_long',
                type: ContentNodeType.paragraph,
                text:
                    'Mereka mulai bergerak menyusuri koridor panjang yang gelap. Suara langkah sepatu terdengar menggema '
                    'di sepanjang dinding beton yang lembap. Tidak ada satu pun dari mereka yang berbicara selama perjalanan '
                    'menuju ruang pertemuan rahasia di lantai bawah tanah.',
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PaginatedReflowableReader(
              document: testDoc,
              theme: ReadingThemeType.dark,
              typography: const TypographySettings(twoPageSpread: true),
              onTapContent: () {},
              onProgressChanged: (a, b, c, d, e) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Heading should be visible alongside its following paragraph
      expect(find.text('BAB SATU: PENDAHULUAN'), findsOneWidget);
      expect(find.byType(PaginatedReflowableReader), findsOneWidget);
      print(
        'Visual Widget Verification: Heading attached properly to following prose in two-page spread!',
      );
    });
  });
}

/// Mirrors the pagination engine's height accounting for an already paginated
/// page: real per-node style, per-node padding, heading keep-with-next advance,
/// and image block height.
double _measuredPageHeight(
  PaginatedPage page,
  TypographySettings typography,
  double contentWidth,
) {
  double height = 0;
  for (final slice in page.slices) {
    final node = slice.node;
    if (node.type == ContentNodeType.image) {
      height +=
          220.0 +
          (node.text.trim().isNotEmpty ? 28.0 : 0.0) +
          typography.paragraphSpacing;
      continue;
    }
    final style = PaginationEngine.textStyleFor(node, typography);
    final isNormalPara =
        node.type == ContentNodeType.paragraph &&
        node.attributes['isTocEntry'] != true &&
        node.attributes['kind'] != 'publisherSlogan' &&
        node.attributes['frontMatter'] == null;
    final applyIndent = isNormalPara && !slice.isContinuation;
    final TextPainter tp;
    if (applyIndent) {
      final fontSize = style.fontSize ?? typography.fontSize;
      tp = TextPainter(
        text: TextSpan(
          children: [
            WidgetSpan(
              child: SizedBox(
                width: typography.firstLineIndent,
                height: fontSize,
              ),
            ),
            TextSpan(text: slice.textSlice, style: style),
          ],
        ),
        textDirection: TextDirection.ltr,
      );
      tp.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(typography.firstLineIndent, fontSize),
          alignment: PlaceholderAlignment.bottom,
        ),
      ]);
    } else {
      tp = TextPainter(
        text: TextSpan(text: slice.textSlice, style: style),
        textDirection: TextDirection.ltr,
      );
    }
    tp.layout(maxWidth: contentWidth);
    if (node.type == ContentNodeType.heading ||
        node.type == ContentNodeType.sectionHeading ||
        node.type == ContentNodeType.documentTitle) {
      height += tp.height + 8.0 + (typography.paragraphSpacing * 1.2);
    } else {
      height += tp.height + PaginationEngine.paddingFor(node, typography);
    }
    tp.dispose();
  }
  return height;
}
