import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';

/// Builds an OCR line on a given page. The classifier only treats a paragraph
/// as OCR-origin when its first source line carries the Apple Vision font name.
ExtractedTextLine _ocrLine({
  required int pageIndex,
  required Rect bounds,
  required String text,
}) {
  return ExtractedTextLine(
    bounds: bounds,
    text: text,
    fontSize: 14,
    fontName: 'AppleVisionOCR',
    lineIndex: 0,
    pageIndex: pageIndex,
  );
}

ReconstructedParagraph _ocrParagraph({
  required String text,
  required int startPageIndex,
  required int endPageIndex,
  required Rect boundingBox,
  required List<ExtractedTextLine> sourceLines,
  int lineCount = 1,
}) {
  return ReconstructedParagraph(
    text: text,
    startPageIndex: startPageIndex,
    endPageIndex: endPageIndex,
    boundingBox: boundingBox,
    fontSize: 14,
    fontStyles: const [],
    isBold: false,
    isItalic: false,
    lineCount: lineCount,
    sourceLines: sourceLines,
  );
}

void main() {
  group('SemanticClassifier page-aware vertical gaps', () {
    test(
      'measures gapBefore from the previous paragraph line on the current page',
      () {
        // Paragraph A starts near the bottom of page 0 and continues at the top
        // of page 1. Its boundingBox.bottom (950) belongs to page 1's
        // coordinate extension, so using it as-is would make the gap before the
        // heading collapse to zero.
        final previous = _ocrParagraph(
          text: 'Paragraf pertama yang berlanjut ke halaman berikutnya.',
          startPageIndex: 0,
          endPageIndex: 1,
          boundingBox: const Rect.fromLTRB(50, 700, 550, 950),
          lineCount: 2,
          sourceLines: [
            _ocrLine(
              pageIndex: 0,
              bounds: const Rect.fromLTRB(50, 700, 550, 712),
              text: 'Paragraf pertama yang berlanjut ke halaman',
            ),
            _ocrLine(
              pageIndex: 1,
              bounds: const Rect.fromLTRB(50, 60, 550, 72),
              text: 'berikutnya.',
            ),
          ],
        );

        final heading = _ocrParagraph(
          text: 'Melatih Logika Berbicara',
          startPageIndex: 1,
          endPageIndex: 1,
          boundingBox: const Rect.fromLTRB(50, 100, 300, 112),
          sourceLines: [
            _ocrLine(
              pageIndex: 1,
              bounds: const Rect.fromLTRB(50, 100, 300, 112),
              text: 'Melatih Logika Berbicara',
            ),
          ],
        );

        final following = _ocrParagraph(
          text:
              'Berbicara dengan logika berarti menyusun argumen yang runtut '
              'dan mudah dipahami oleh pendengar.',
          startPageIndex: 1,
          endPageIndex: 1,
          boundingBox: const Rect.fromLTRB(50, 130, 550, 190),
          lineCount: 3,
          sourceLines: [
            _ocrLine(
              pageIndex: 1,
              bounds: const Rect.fromLTRB(50, 130, 550, 142),
              text: 'Berbicara dengan logika berarti menyusun argumen yang',
            ),
            _ocrLine(
              pageIndex: 1,
              bounds: const Rect.fromLTRB(50, 150, 550, 162),
              text: 'runtut dan mudah dipahami oleh pendengar.',
            ),
          ],
        );

        final blocks = SemanticClassifier.classifyDocument(
          paragraphs: [previous, heading, following],
          totalPages: 2,
          defaultPageHeight: 792,
        );

        final headingBlock = blocks.firstWhere(
          (b) => b.text == 'Melatih Logika Berbicara',
        );
        expect(
          headingBlock.type,
          SemanticBlockType.heading3,
          reason:
              'The gap before the heading is 28pt measured from the last line '
              'on page 1, not 0pt measured from the span-wide bounding box.',
        );
        expect(headingBlock.headingLevel, 3);
      },
    );

    test('does not promote a page-spanning prose line to a heading', () {
      final previous = _ocrParagraph(
        text: 'Paragraf pertama yang berlanjut.',
        startPageIndex: 0,
        endPageIndex: 1,
        boundingBox: const Rect.fromLTRB(50, 700, 550, 950),
        lineCount: 2,
        sourceLines: [
          _ocrLine(
            pageIndex: 0,
            bounds: const Rect.fromLTRB(50, 700, 550, 712),
            text: 'Paragraf pertama yang berlanjut.',
          ),
          _ocrLine(
            pageIndex: 1,
            bounds: const Rect.fromLTRB(50, 60, 550, 72),
            text: 'Lanjutannya ada di sini.',
          ),
        ],
      );

      final prose = _ocrParagraph(
        text: 'Kalimat ini adalah lanjutan isi paragraf biasa',
        startPageIndex: 1,
        endPageIndex: 1,
        boundingBox: const Rect.fromLTRB(50, 100, 550, 112),
        sourceLines: [
          _ocrLine(
            pageIndex: 1,
            bounds: const Rect.fromLTRB(50, 100, 550, 112),
            text: 'Kalimat ini adalah lanjutan isi paragraf biasa',
          ),
        ],
      );

      final following = _ocrParagraph(
        text:
            'Isi berikutnya melanjutkan pembahasan tanpa jeda yang mencolok '
            'sehingga tetap dianggap bagian dari paragraf yang sama.',
        startPageIndex: 1,
        endPageIndex: 1,
        boundingBox: const Rect.fromLTRB(50, 120, 550, 180),
        lineCount: 3,
        sourceLines: [
          _ocrLine(
            pageIndex: 1,
            bounds: const Rect.fromLTRB(50, 120, 550, 132),
            text: 'Isi berikutnya melanjutkan pembahasan tanpa jeda.',
          ),
          _ocrLine(
            pageIndex: 1,
            bounds: const Rect.fromLTRB(50, 140, 550, 152),
            text: 'Sehingga tetap dianggap bagian paragraf.',
          ),
        ],
      );

      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: [previous, prose, following],
        totalPages: 2,
        defaultPageHeight: 792,
      );

      final proseBlock = blocks.firstWhere(
        (b) => b.text.startsWith('Kalimat ini'),
      );
      expect(
        proseBlock.type,
        SemanticBlockType.bodyParagraph,
        reason:
            'A tight 8pt gap around prose must not be read as heading '
            'whitespace, even though the previous paragraph spans pages.',
      );
    });
  });
}
