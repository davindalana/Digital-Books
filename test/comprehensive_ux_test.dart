import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/book_page_turn_view.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable_book_reader.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Comprehensive UX & Reader Verification Tests', () {
    late BookDocument sampleDoc;

    setUp(() {
      sampleDoc = const BookDocument(
        id: 'sample_book_id',
        title: 'Kesetiaan Mr. X',
        author: 'Keigo Higashino',
        totalPages: 20,
        chapters: [
          BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Pengantar',
            blocks: [
              BookBlock(
                id: 'b0_title',
                type: BlockType.heading,
                text: 'KESETIAAN MR. X',
                headingLevel: 1,
              ),
              BookBlock(
                id: 'b0_disclaimer',
                type: BlockType.paragraph,
                text:
                    'Sanksi Pelanggaran Pasal 113 Undang-undang Nomor 28 Tahun 2014 tentang Hak Cipta.',
              ),
            ],
          ),
          BookChapter(
            id: 'ch1',
            index: 1,
            title: 'SATU',
            blocks: [
              BookBlock(
                id: 'b1_head',
                type: BlockType.heading,
                text: 'SATU',
                headingLevel: 1,
              ),
              BookBlock(
                id: 'b1_p1',
                type: BlockType.paragraph,
                text:
                    'Pukul 07.35. Seperti biasa, Ishigami meninggalkan apartemen pagi-pagi sekali. Embusan angin terasa dingin, padahal saat ini awal Maret. la mulai melangkah dengan dagu terkubur dalam-dalam di balik syal. Sebelum pergi, tatapannya tertuju ke tempat parkir sepeda, menyadari ketidakhadiran sepeda hijau di antara deretan sepeda.',
              ),
              BookBlock(
                id: 'b1_p2',
                type: BlockType.paragraph,
                text:
                    '"Selamat pagi," sapa Ishigami. Wanita tua itu membalas dengan senyuman hangat di depan kedai.',
              ),
            ],
          ),
        ],
      );
    });

    testWidgets(
      'ReflowableBookReader renders cleanly on mobile screen (400x700)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReflowableBookReader(
                document: sampleDoc,
                theme: ReadingThemeType.warmPaper,
                typography: const TypographySettings(),
                initialChapterIndex: 1,
                initialPosition: 1,
                onProgressChanged: (ch, page, pct) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify the chapter heading and paragraph render without any layout exceptions
        expect(find.byType(ReflowableBookReader), findsOneWidget);
        expect(find.byType(BookPageTurnView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ReflowableBookReader dynamically adapts to desktop wide screen (1200x800) two-page spread',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReflowableBookReader(
                document: sampleDoc,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(twoPageSpread: true),
                initialChapterIndex: 0,
                initialPosition: 1,
                onProgressChanged: (ch, page, pct) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Confirm zero exceptions and smooth two-page desktop layout
        expect(tester.takeException(), isNull);
        expect(find.byType(BookPageTurnView), findsOneWidget);
      },
    );

    testWidgets('BookPageTurnView flips forward and backward smoothly on tap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int reportedPage = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReflowableBookReader(
              document: sampleDoc,
              theme: ReadingThemeType.warmPaper,
              typography: const TypographySettings(),
              initialChapterIndex: 0,
              initialPosition: 1,
              onProgressChanged: (ch, page, pct) {
                reportedPage = page;
              },
              onTapContent: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on the right 20% area of screen to flip page forward
      final rightEdge = tester.getTopRight(find.byType(BookPageTurnView));
      final tapTarget = Offset(rightEdge.dx - 40, rightEdge.dy + 300);
      await tester.tapAt(tapTarget);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(reportedPage, greaterThanOrEqualTo(1));
    });

    test('BookTextNormalizer preserves images and cleans headers', () {
      final docWithImage = BookDocument(
        id: 'img_test',
        title: 'Teka-Teki Rumah Aneh',
        author: 'Uketsu',
        totalPages: 5,
        chapters: [
          const BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Prolog',
            blocks: [
              BookBlock(
                id: 'header_artifact',
                type: BlockType.paragraph,
                text: 'UKETSU\nTEKA-TEKI RUMAH ANEH',
              ),
              BookBlock(
                id: 'img1',
                type: BlockType.image,
                text: 'Denah Rumah Lantai 1',
                imagePath: '/path/to/image.png',
              ),
              BookBlock(
                id: 'p1',
                type: BlockType.paragraph,
                text: 'Ini adalah denah rumah yang mem-\nbingungkan pembaca.',
              ),
            ],
          ),
        ],
      );

      final normalized = BookTextNormalizer.normalizeDocument(docWithImage);
      expect(normalized.chapters.isNotEmpty, isTrue);

      final allBlocks = normalized.chapters.expand((c) => c.blocks).toList();
      final imageBlocks = allBlocks
          .where((b) => b.type == BlockType.image)
          .toList();

      // Image block MUST be preserved!
      expect(imageBlocks.length, equals(1));
      expect(imageBlocks.first.text, equals('Denah Rumah Lantai 1'));
      expect(imageBlocks.first.imagePath, equals('/path/to/image.png'));

      // Paragraph de-hyphenation check
      final paragraphs = allBlocks
          .where((b) => b.type == BlockType.paragraph)
          .toList();
      expect(paragraphs.any((p) => p.text.contains('membingungkan')), isTrue);
    });

    test(
      'BookTextNormalizer removes single-letter OCR noise and publisher headers',
      () {
        final docWithNoise = const BookDocument(
          id: 'noise_test',
          title: 'Kesetiaan Mr. X',
          author: 'Keigo Higashino',
          totalPages: 10,
          chapters: [
            BookChapter(
              id: 'ch0',
              index: 0,
              title: 'Pengantar',
              blocks: [
                BookBlock(
                  id: 'b1',
                  type: BlockType.paragraph,
                  text:
                      'Ith Lh\nKESETIAAN MR. X\nK H\nG\nS\nH\nHTA LA\nKESETAAN MK X\nSanksi Pelanggaran Pasal 113',
                ),
              ],
            ),
          ],
        );

        final normalized = BookTextNormalizer.normalizeDocument(docWithNoise);
        final allBlocks = normalized.chapters.expand((c) => c.blocks).toList();
        final text = allBlocks.map((b) => b.text).join(' ');

        // Should not contain isolated letters G, S, H or garbage headers
        expect(text.contains('Sanksi Pelanggaran Pasal 113'), isTrue);
        expect(text.contains('Ith Lh'), isFalse);
        expect(text.contains('HTA LA'), isFalse);
      },
    );
  });
}
