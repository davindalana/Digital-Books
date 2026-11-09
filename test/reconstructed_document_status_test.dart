import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:flutter_test/flutter_test.dart';

ReconstructedDocument _document({
  required QualityStatus status,
  required bool isScannedSource,
}) {
  return ReconstructedDocument(
    bookId: 'status-book',
    title: 'Status Book',
    author: 'Tester',
    totalPages: 10,
    chapters: const [
      BookChapter(
        id: 'chapter-1',
        index: 0,
        title: 'Bab 1',
        blocks: [
          BookBlock(id: 'block-1', type: BlockType.paragraph, text: 'Isi bab.'),
        ],
      ),
    ],
    blocks: const [],
    quality: ReconstructionQuality(
      status: status,
      score: 0.9,
      reasons: const ['ok'],
      metrics: const {},
      recommendedTier: 'Smart Reflowable Reader',
    ),
    durationMs: 12,
    isScannedSource: isScannedSource,
  );
}

void main() {
  group('ReconstructedDocument processing status', () {
    test('a good text-layer document is ready and not marked scanned', () {
      final doc = _document(
        status: QualityStatus.good,
        isScannedSource: false,
      ).toBookDocument();

      expect(doc.isScanned, isFalse);
      expect(doc.metadata['processingStatus'], 'ready');
      expect(doc.metadata['isScannedSource'], isFalse);
    });

    test('a poor scanned source requires OCR but stays flagged as scanned', () {
      final doc = _document(
        status: QualityStatus.poor,
        isScannedSource: true,
      ).toBookDocument();

      expect(doc.isScanned, isTrue);
      expect(doc.metadata['processingStatus'], 'requiresOcr');
      expect(doc.metadata['isScannedSource'], isTrue);
    });

    test('an OCR derivative can be ready while the source stays scanned', () {
      final doc = _document(
        status: QualityStatus.good,
        isScannedSource: true,
      ).toBookDocument();

      expect(doc.isScanned, isTrue);
      expect(doc.metadata['processingStatus'], 'ready');
      expect(doc.metadata['isScannedSource'], isTrue);
    });
  });
}
