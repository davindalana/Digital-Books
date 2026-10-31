import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookTextNormalizer Tests', () {
    test('removes running headers and footers from lines', () {
      final doc = BookDocument(
        id: 'test_book',
        title: 'Kesetiaan Mr. X',
        author: 'Keigo Higashino',
        totalPages: 10,
        chapters: [
          BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Introduction',
            blocks: [
              const BookBlock(
                id: 'b1',
                type: BlockType.paragraph,
                text:
                    'KEIGO HIGASHINO\nSATU\nPukul 07.35. Ishigami pergi bekerja.',
              ),
              const BookBlock(
                id: 'b2',
                type: BlockType.paragraph,
                text: 'KESETIAAN MR. X\nAngin bertiup kencang.',
              ),
            ],
          ),
        ],
      );

      final normalized = BookTextNormalizer.normalizeDocument(doc);
      expect(normalized.chapters.length, greaterThanOrEqualTo(1));

      // Find chapter with SATU
      final satuChapter = normalized.chapters.firstWhere(
        (c) => c.title == 'SATU',
      );
      expect(satuChapter.blocks.first.type, equals(BlockType.heading));
      expect(satuChapter.blocks.first.text, equals('SATU'));

      // Confirm KEIGO HIGASHINO and KESETIAAN MR. X headers were stripped from narrative
      for (final ch in normalized.chapters) {
        for (final b in ch.blocks) {
          if (b.type == BlockType.paragraph) {
            expect(b.text.contains('KEIGO HIGASHINO'), isFalse);
            expect(b.text.contains('KESETIAAN MR. X'), isFalse);
          }
        }
      }
    });

    test('repairs split hyphenated words across lines', () {
      final doc = BookDocument(
        id: 'test_book_2',
        title: 'Testing Book',
        author: 'Author',
        totalPages: 2,
        chapters: [
          BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Intro',
            blocks: [
              const BookBlock(
                id: 'b1',
                type: BlockType.paragraph,
                text:
                    'la terus berjalan sambil agak mem-\nbungkuk karena angin.',
              ),
              const BookBlock(
                id: 'b2',
                type: BlockType.paragraph,
                text: 'Tatapannya terkubur dalam-\ndalam di balik syal.',
              ),
            ],
          ),
        ],
      );

      final normalized = BookTextNormalizer.normalizeDocument(doc);
      final allParagraphs = normalized.chapters
          .expand((c) => c.blocks)
          .where((b) => b.type == BlockType.paragraph)
          .map((b) => b.text)
          .join(' ');

      expect(allParagraphs.contains('membungkuk'), isTrue);
      expect(allParagraphs.contains('dalam-dalam'), isTrue);
    });
  });
}
