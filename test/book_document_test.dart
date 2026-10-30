import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookDocument Model Tests', () {
    test('Serializes and deserializes BookDocument correctly', () {
      final doc = BookDocument(
        id: 'test-123',
        title: 'Moby Dick',
        author: 'Herman Melville',
        totalPages: 100,
        isScanned: false,
        chapters: [
          BookChapter(
            id: 'ch-1',
            index: 0,
            title: 'Chapter 1: Loomings',
            blocks: [
              const BookBlock(
                id: 'blk-1',
                type: BlockType.heading,
                text: 'Chapter 1: Loomings',
                headingLevel: 1,
                originalPageNumber: 1,
              ),
              const BookBlock(
                id: 'blk-2',
                type: BlockType.paragraph,
                text: 'Call me Ishmael. Some years ago—never mind how long precisely...',
                originalPageNumber: 1,
              ),
            ],
          ),
        ],
        metadata: {'genre': 'Adventure', 'year': 1851},
      );

      final jsonStr = doc.toJsonString();
      final restored = BookDocument.fromJsonString(jsonStr);

      expect(restored.id, 'test-123');
      expect(restored.title, 'Moby Dick');
      expect(restored.author, 'Herman Melville');
      expect(restored.totalPages, 100);
      expect(restored.isScanned, false);
      expect(restored.chapters.length, 1);
      expect(restored.chapters.first.title, 'Chapter 1: Loomings');
      expect(restored.chapters.first.blocks.length, 2);
      expect(restored.chapters.first.blocks.last.text,
          contains('Call me Ishmael'));
    });
  });
}

