import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';

ReconstructedParagraph _paragraph({
  required String text,
  required int pageIndex,
  required Rect bounds,
  double fontSize = 11.0,
  int lineCount = 1,
  bool isBold = false,
}) {
  return ReconstructedParagraph(
    text: text,
    startPageIndex: pageIndex,
    endPageIndex: pageIndex,
    boundingBox: bounds,
    fontSize: fontSize,
    fontStyles: const [],
    isBold: isBold,
    isItalic: false,
    lineCount: lineCount,
    sourceLines: [
      ExtractedTextLine(
        bounds: bounds,
        text: text,
        fontSize: fontSize,
        fontName: 'SerifFont',
        lineIndex: 0,
        pageIndex: pageIndex,
      ),
    ],
  );
}

ReconstructedParagraph _body({
  required String text,
  required int pageIndex,
  required double top,
  double fontSize = 11.0,
  int lineCount = 2,
}) {
  return _paragraph(
    text: text,
    pageIndex: pageIndex,
    bounds: Rect.fromLTRB(50, top, 550, top + (lineCount * 14)),
    fontSize: fontSize,
    lineCount: lineCount,
  );
}

void main() {
  group('SemanticClassifier content preservation', () {
    test(
      'keeps an explicit chapter heading that sits in the page top zone',
      () {
        final paragraphs = [
          _body(
            text:
                'Paragraf pembuka buku yang cukup panjang untuk menetapkan '
                'ukuran huruf badan teks pada dokumen ini.',
            pageIndex: 0,
            top: 120,
          ),
          _body(
            text:
                'Paragraf pada halaman kedua yang juga panjang agar ukuran '
                'huruf badan teks tetap terdeteksi dengan benar.',
            pageIndex: 1,
            top: 90,
          ),
          _paragraph(
            text: 'BAB III',
            pageIndex: 1,
            bounds: const Rect.fromLTRB(50, 30, 160, 48),
            fontSize: 14,
            isBold: true,
          ),
          _body(
            text:
                'Isi bab ketiga dimulai pada halaman ini dan mengalir sebagai '
                'paragraf biasa di bawah judul bab.',
            pageIndex: 1,
            top: 130,
          ),
        ];

        final blocks = SemanticClassifier.classifyDocument(
          paragraphs: paragraphs,
          totalPages: 2,
          defaultPageHeight: 792,
          pageHeights: const {0: 792, 1: 792},
        );

        final chapter = blocks.firstWhere((b) => b.text.contains('BAB III'));
        expect(
          chapter.type,
          SemanticBlockType.heading1,
          reason:
              'A chapter marker at the physical top of a page is content, not '
              'a running header; dropping it loses the chapter.',
        );
      },
    );

    test('keeps a short paragraph that ends at the bottom of a page', () {
      final paragraphs = [
        _body(
          text:
              'Paragraf panjang di halaman pertama untuk menetapkan ukuran '
              'huruf badan teks pada dokumen ini.',
          pageIndex: 0,
          top: 120,
        ),
        _body(
          text:
              'Paragraf panjang sebelum penutup adegan pada halaman kedua '
              'agar ukuran huruf badan teks tetap dominan.',
          pageIndex: 1,
          top: 120,
        ),
        _paragraph(
          text: 'Ia pun pergi.',
          pageIndex: 1,
          bounds: const Rect.fromLTRB(50, 720, 170, 734),
          fontSize: 11,
        ),
      ];

      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: 2,
        defaultPageHeight: 792,
        pageHeights: const {0: 792, 1: 792},
      );

      final closing = blocks.firstWhere((b) => b.text == 'Ia pun pergi.');
      expect(
        closing.type,
        SemanticBlockType.bodyParagraph,
        reason:
            'A short body paragraph at the bottom of a page must not be '
            'discarded as a running footer.',
      );
    });

    test('still classifies a genuinely repeated running header', () {
      final paragraphs = [
        _paragraph(
          text: 'BUKU CONTOH',
          pageIndex: 0,
          bounds: const Rect.fromLTRB(250, 24, 360, 34),
          fontSize: 9,
        ),
        _body(
          text:
              'Isi halaman pertama yang cukup panjang untuk menetapkan '
              'ukuran huruf badan teks.',
          pageIndex: 0,
          top: 120,
        ),
        _paragraph(
          text: 'BUKU CONTOH',
          pageIndex: 1,
          bounds: const Rect.fromLTRB(250, 24, 360, 34),
          fontSize: 9,
        ),
        _body(
          text:
              'Isi halaman kedua yang juga panjang agar ukuran huruf badan '
              'teks tetap terdeteksi.',
          pageIndex: 1,
          top: 120,
        ),
      ];

      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: 2,
        defaultPageHeight: 792,
        pageHeights: const {0: 792, 1: 792},
      );

      final headers = blocks.where(
        (b) =>
            b.text == 'BUKU CONTOH' &&
            b.type == SemanticBlockType.runningHeader,
      );
      expect(headers.length, equals(2));
    });

    test('still classifies a genuinely repeated running footer', () {
      final paragraphs = [
        _body(
          text:
              'Isi halaman pertama yang cukup panjang untuk menetapkan '
              'ukuran huruf badan teks.',
          pageIndex: 0,
          top: 120,
        ),
        _paragraph(
          text: 'BUKU CONTOH',
          pageIndex: 0,
          bounds: const Rect.fromLTRB(250, 756, 360, 768),
          fontSize: 9,
        ),
        _body(
          text:
              'Isi halaman kedua yang juga panjang agar ukuran huruf badan '
              'teks tetap terdeteksi.',
          pageIndex: 1,
          top: 120,
        ),
        _paragraph(
          text: 'BUKU CONTOH',
          pageIndex: 1,
          bounds: const Rect.fromLTRB(250, 756, 360, 768),
          fontSize: 9,
        ),
      ];

      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: 2,
        defaultPageHeight: 792,
        pageHeights: const {0: 792, 1: 792},
      );

      final footers = blocks.where(
        (b) =>
            b.text == 'BUKU CONTOH' &&
            b.type == SemanticBlockType.runningFooter,
      );
      expect(footers.length, equals(2));
    });
  });
}
