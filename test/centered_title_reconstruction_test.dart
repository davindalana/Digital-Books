import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';

ExtractedTextLine _ocrLine({
  required String text,
  required Rect bounds,
  int index = 0,
}) => ExtractedTextLine(
  bounds: bounds,
  text: text,
  fontSize: 18.0,
  fontName: 'AppleVisionOCR',
  lineIndex: index,
  pageIndex: 0,
);

PageReadingOrderResult _page(List<ExtractedTextLine> lines) =>
    PageReadingOrderResult(
      pageIndex: 0,
      layoutStructure: PageLayoutStructure.singleColumn,
      orderedLines: lines,
      columnConfidence: 1.0,
    );

void main() {
  group('centred multi-line title reconstruction', () {
    test('keeps centred title lines in one paragraph', () {
      final page = _page([
        _ocrLine(
          text: 'Menggaruk yang Gatal dengan',
          bounds: const Rect.fromLTRB(131.4, 166.5, 486.2, 193.1),
          index: 0,
        ),
        _ocrLine(
          text: 'Pertanyaan yang Tepat',
          bounds: const Rect.fromLTRB(180.9, 201.2, 439.5, 227.8),
          index: 1,
        ),
        _ocrLine(
          text:
              'Itu adalah ucapan Kwon Yeong Chan, ahli pemasaran perusahaan '
              'tong sampah fungsional Magikan yang belakangan ini selalu '
              'terjual habis.',
          bounds: const Rect.fromLTRB(83.4, 418.3, 531.4, 435.6),
          index: 2,
        ),
        _ocrLine(
          text:
              'Rahasia di balik suksesnya penjualan Magikan adalah kemampuan '
              'berujarnya yang setara dengan bintang home shopping host.',
          bounds: const Rect.fromLTRB(83.4, 441.0, 531.4, 458.3),
          index: 3,
        ),
        _ocrLine(
          text:
              'Tong sampah konvensional yang selama ini ada mudah kotor dan '
              'berbau karena tidak dirancang dengan baik.',
          bounds: const Rect.fromLTRB(83.4, 464.0, 531.4, 481.3),
          index: 4,
        ),
      ]);

      final paragraphs = ParagraphReconstructor.reconstructPage(page);

      expect(paragraphs, hasLength(2));
      expect(
        paragraphs.first.text,
        'Menggaruk yang Gatal dengan Pertanyaan yang Tepat',
      );
      expect(paragraphs.first.lineCount, 2);
      expect(paragraphs.last.text, startsWith('Itu adalah ucapan'));
    });

    test('promotes the merged centred title to a heading', () {
      final page = _page([
        _ocrLine(
          text: 'Semua Orang Memiliki',
          bounds: const Rect.fromLTRB(173.6, 165.7, 445.3, 194.1),
          index: 0,
        ),
        _ocrLine(
          text: 'Titik Start yang Sama',
          bounds: const Rect.fromLTRB(186.3, 199.4, 429.8, 229.0),
          index: 1,
        ),
        _ocrLine(
          text:
              'Setiap orang Korea pasti akan teringat Yoo Jae Suk jika '
              'mendengar kata MC atau pembawa acara. Ia mampu memukau mata '
              'banyak penonton dengan kelihaian dalam membawakan beragam '
              'program hiburan.',
          bounds: const Rect.fromLTRB(83.4, 418.3, 531.4, 435.6),
          index: 2,
        ),
        _ocrLine(
          text:
              'Berbeda dengan pembawa acara lainnya, kelebihannya adalah bisa '
              'membuat bintang tamu merasa nyaman dan tidak pernah berdiri di '
              'depan lalu banyak bicara.',
          bounds: const Rect.fromLTRB(83.4, 441.0, 531.4, 458.3),
          index: 3,
        ),
      ]);

      final paragraphs = ParagraphReconstructor.reconstructPage(page);
      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: 1,
      );

      final title = blocks.firstWhere(
        (b) => b.text.contains('Titik Start yang Sama'),
      );
      expect(title.text, 'Semua Orang Memiliki Titik Start yang Sama');
      expect(title.type, SemanticBlockType.heading3);
    });

    test(
      'reconstructs centered titles ending with punctuation or lowercase words',
      () {
        final page = _page([
          _ocrLine(
            text: 'Dasar-Dasar Percakapan,',
            bounds: const Rect.fromLTRB(137.4, 186.2, 384.2, 226.7),
            index: 0,
          ),
          _ocrLine(
            text: 'Kiss!',
            bounds: const Rect.fromLTRB(236.3, 231.0, 287.4, 261.1),
            index: 1,
          ),
          _ocrLine(
            text: 'Lebih Pendek, Lebih Mudah',
            bounds: const Rect.fromLTRB(70.0, 436.7, 240.0, 458.8),
            index: 2,
          ),
          _ocrLine(
            text:
                'Pidato tersingkat yang menerima tepuk tangan terbanyak di dunia '
                'adalah pidato Dwight Eisenhower dalam sebuah ceramah umum.',
            bounds: const Rect.fromLTRB(70.0, 480.0, 530.0, 500.0),
            index: 3,
          ),
        ]);

        final paragraphs = ParagraphReconstructor.reconstructPage(page);
        expect(paragraphs.first.text, 'Dasar-Dasar Percakapan, Kiss!');
        expect(paragraphs.first.lineCount, 2);

        final pageLower = _page([
          _ocrLine(
            text: 'Tunjukkan Passion',
            bounds: const Rect.fromLTRB(168.0, 185.0, 348.5, 215.0),
            index: 0,
          ),
          _ocrLine(
            text: 'yang Besar',
            bounds: const Rect.fromLTRB(206.0, 235.0, 314.0, 265.0),
            index: 1,
          ),
          _ocrLine(
            text:
                'Orang yang pandai berbicara biasanya penuh semangat. Selain itu, '
                'ketertarikan dan gairahnya akan pekerjaan tampak saat berbicara.',
            bounds: const Rect.fromLTRB(70.0, 480.0, 530.0, 500.0),
            index: 2,
          ),
        ]);

        final paragraphsLower = ParagraphReconstructor.reconstructPage(
          pageLower,
        );
        expect(paragraphsLower.first.text, 'Tunjukkan Passion yang Besar');
        expect(paragraphsLower.first.lineCount, 2);
      },
    );
  });

  group('indented paragraph guard', () {
    test('still starts a new paragraph at a genuine first-line indent', () {
      final page = _page([
        _ocrLine(
          text: 'Kalimat pertama pada paragraf ini selesai dengan tanda titik.',
          bounds: const Rect.fromLTRB(83.4, 418.3, 531.4, 435.6),
          index: 0,
        ),
        _ocrLine(
          text:
              'Paragraf baru dimulai dengan baris yang menjorok ke dalam dan '
              'berlanjut pada baris berikutnya.',
          bounds: const Rect.fromLTRB(108.8, 441.0, 531.4, 458.3),
          index: 1,
        ),
        _ocrLine(
          text:
              'Baris kedua paragraf baru tetap selebar badan teks yang normal.',
          bounds: const Rect.fromLTRB(83.4, 464.0, 531.4, 481.3),
          index: 2,
        ),
      ]);

      final paragraphs = ParagraphReconstructor.reconstructPage(page);

      expect(paragraphs, hasLength(2));
      expect(paragraphs.first.text, endsWith('tanda titik.'));
      expect(paragraphs.last.text, startsWith('Paragraf baru dimulai'));
    });

    test('does not merge a left-aligned heading with the following body', () {
      final page = _page([
        _ocrLine(
          text: 'Dahulukan Kebutuhan Daripada Keinginan',
          bounds: const Rect.fromLTRB(84.6, 367.4, 394.5, 389.6),
          index: 0,
        ),
        _ocrLine(
          text:
              'Melihat yang dilihat konsumen dan membaca yang dibutuhkan '
              'konsumen adalah kunci pemasaran yang jujur.',
          bounds: const Rect.fromLTRB(108.8, 418.3, 531.4, 435.6),
          index: 1,
        ),
        _ocrLine(
          text: 'Itu adalah ucapan seorang ahli pemasaran yang berpengalaman.',
          bounds: const Rect.fromLTRB(83.4, 441.0, 531.4, 458.3),
          index: 2,
        ),
      ]);

      final paragraphs = ParagraphReconstructor.reconstructPage(page);

      expect(paragraphs, hasLength(2));
      expect(paragraphs.first.text, 'Dahulukan Kebutuhan Daripada Keinginan');
      expect(paragraphs.last.text, startsWith('Melihat yang dilihat'));
    });
  });
}
