import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/front_matter_reconstructor.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/toc_reconstructor.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/models/book_document.dart';

ExtractedTextLine _line(
  String text, {
  required int page,
  required double top,
  double height = 12,
  double left = 70,
  double width = 400,
  int index = 0,
}) {
  return ExtractedTextLine(
    bounds: Rect.fromLTWH(left, top, width, height),
    text: text,
    fontSize: height * 0.8,
    pageIndex: page,
    lineIndex: index,
  );
}

PageReadingOrderResult _page(int index, List<ExtractedTextLine> lines) {
  return PageReadingOrderResult(
    pageIndex: index,
    layoutStructure: PageLayoutStructure.singleColumn,
    orderedLines: lines,
    columnConfidence: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Book Mode defaults to justified body text', () {
    expect(const TypographySettings().textAlign.name, 'justify');
  });

  test('App reader path preserves semantic block metadata', () {
    final doc = BookDocument(
      id: 'book-1',
      title: 'Book',
      author: 'Author',
      totalPages: 1,
      metadata: const {
        'reconstructionQuality': {'score': 1.0},
      },
      chapters: const [
        BookChapter(
          id: 'ch0',
          index: 0,
          title: 'Bagian Awal',
          blocks: [
            BookBlock(
              id: 'toc-title',
              type: BlockType.metadataBlock,
              text: 'Daftar Isi',
              metadata: {'frontMatter': 'toc', 'kind': 'tocTitle'},
            ),
            BookBlock(
              id: 'legal-clause',
              type: BlockType.orderedList,
              text: '1. Ketentuan hukum.',
              metadata: {'legalClause': true, 'listMarker': '1.'},
            ),
          ],
        ),
      ],
    );

    final readerDoc = ReflowableEngine.normalizeDocument(doc);
    final nodes = readerDoc.chapters.first.nodes;

    expect(nodes[0].attributes['kind'], 'tocTitle');
    expect(nodes[0].attributes['frontMatter'], 'toc');
    expect(nodes[1].attributes['legalClause'], isTrue);
    expect(nodes[1].attributes['listMarker'], '1.');
  });

  test(
    'Front matter cover is split into title, author and publisher roles',
    () {
      final cover = _page(0, [
        _line('BIP', page: 0, top: 50, left: 470, height: 20, index: 0),
        _line('KELOMPOK', page: 0, top: 75, left: 470, height: 10, index: 1),
        _line('GRAMEDIA', page: 0, top: 88, left: 470, height: 10, index: 2),
        _line(
          'THE SECRET HABITS TO MASTER YOUR ART OF SPEAKING',
          page: 0,
          top: 130,
          height: 27,
          index: 3,
        ),
        _line('BICARA', page: 0, top: 180, height: 120, width: 250, index: 4),
        _line('ADA ITU', page: 0, top: 330, height: 140, width: 250, index: 5),
        _line('SENINYA', page: 0, top: 500, height: 120, width: 250, index: 6),
        _line(
          'RAHASIA KOMUNIKASI YANG EFEKTIF',
          page: 0,
          top: 640,
          height: 30,
          index: 7,
        ),
        _line(
          'OH SU HYANG',
          page: 0,
          top: 700,
          height: 50,
          width: 200,
          index: 8,
        ),
        _line(
          '(DOSEN & PAKAR KOMUNIKASI TERKENAL DI KOREA SELATAN)',
          page: 0,
          top: 770,
          height: 17,
          index: 9,
        ),
      ]);

      final result = FrontMatterReconstructor.reconstruct(
        pages: [cover],
        totalPages: 255,
        bookTitle: 'Bicara Itu Ada Seninya',
      );

      expect(result.blocks, isNotEmpty);
      final mainTitle = result.blocks.firstWhere(
        (b) => b.metadata['kind'] == 'mainTitle',
      );
      expect(mainTitle.type, SemanticBlockType.documentTitle);
      expect(mainTitle.text.toLowerCase(), 'bicara itu ada seninya');
      expect(
        result.blocks.any(
          (b) =>
              b.metadata['kind'] == 'author' &&
              b.type == SemanticBlockType.metadataBlock,
        ),
        isTrue,
      );
      expect(
        result.blocks.any((b) => b.metadata['kind'] == 'publisherLogo'),
        isTrue,
      );
      expect(
        result.blocks.any((b) => b.metadata['kind'] == 'credential'),
        isTrue,
      );
    },
  );

  test('Copyright page groups legal clauses and labels publisher metadata', () {
    final copyright = _page(3, [
      _line(
        'THE SECRET HABITS TO MASTER YOUR ART OF SPEAKING',
        page: 3,
        top: 60,
        index: 0,
      ),
      _line('By Oh Su Hyang', page: 3, top: 78, index: 1),
      _line('All right reserved', page: 3, top: 95, index: 2),
      _line('ISBN: 978-602-455-392-0', page: 3, top: 250, index: 3),
      _line('Diterbitkan pertama kali oleh', page: 3, top: 400, index: 4),
      _line('Penerbit Bhuana Ilmu Populer', page: 3, top: 415, index: 5),
      _line(
        'Hak cipta dilindungi oleh Undang-Undang.',
        page: 3,
        top: 480,
        index: 6,
      ),
      _line('Sanksi Pelanggaran Pasal 113', page: 3, top: 550, index: 7),
      _line(
        '1. Setiap orang yang dengan tanpa hak melakukan pelanggaran',
        page: 3,
        top: 580,
        index: 8,
      ),
      _line(
        '2. Setiap orang yang dengan tanpa izin pencipta',
        page: 3,
        top: 610,
        index: 9,
      ),
      _line(
        '3. Setiap orang yang dengan tanpa hak dan atau',
        page: 3,
        top: 640,
        index: 10,
      ),
      _line(
        '4. Setiap orang yang memenuhi unsur pembajakan',
        page: 3,
        top: 670,
        index: 11,
      ),
    ]);

    final result = FrontMatterReconstructor.reconstruct(
      pages: [
        _page(0, [
          _line('BICARA ITU ADA SENINYA', page: 0, top: 100, height: 80),
        ]),
        _page(1, const []),
        _page(2, const []),
        copyright,
      ],
      totalPages: 255,
      bookTitle: 'Bicara Itu Ada Seninya',
    );

    final clauses = result.blocks
        .where((b) => b.metadata['legalClause'] == true)
        .toList();
    expect(clauses.length, equals(4));
    for (final clause in clauses) {
      expect(clause.type, SemanticBlockType.orderedListItem);
      expect(clause.text, matches(RegExp(r'^[1-4]\. ')));
    }
    expect(
      result.blocks.any(
        (b) => b.metadata['sectionLabel'] == 'Informasi Penerbitan',
      ),
      isTrue,
    );
    expect(
      result.blocks.any((b) => b.metadata['kind'] == 'legalHeading'),
      isTrue,
    );
  });

  test('TOC fragment lines become one entry with a page label', () {
    final toc = _page(12, [
      _line('Daftar Isi', page: 12, top: 150, left: 220, height: 20, index: 0),
      _line('Testimoni ...............', page: 12, top: 260, index: 1),
      _line('... v', page: 12, top: 270, left: 440, width: 30, index: 2),
      _line(
        'Prolog - Membuka Peluang Kesempatan dengan',
        page: 12,
        top: 290,
        index: 3,
      ),
      _line('Kebiasaan Bicara ..', page: 12, top: 313, index: 4),
      _line('.vii', page: 12, top: 315, left: 450, width: 30, index: 5),
      _line('Bab I', page: 12, top: 400, left: 80, width: 50, index: 6),
      _line(
        'Perbedaan Juara 1 dan Juara 2 Terletak',
        page: 12,
        top: 430,
        index: 7,
      ),
      _line('Pada Ucapannya', page: 12, top: 460, index: 8),
      _line('Dari Mana Datangnya Kesan Pertama.', page: 12, top: 510, index: 9),
      _line('..3', page: 12, top: 510, left: 450, width: 25, index: 10),
      _line('Bab II', page: 12, top: 600, left: 80, width: 60, index: 11),
    ]);

    final result = TocReconstructor.reconstruct(pages: [toc]);
    expect(result.blocks.first.type, SemanticBlockType.heading1);
    expect(result.blocks.first.text, 'Daftar Isi');

    final testimoni = result.blocks.firstWhere(
      (b) => b.metadata['kind'] == 'tocEntry' && b.text == 'Testimoni',
    );
    expect(testimoni.metadata['tocPage'], 'v');

    final prolog = result.blocks.firstWhere(
      (b) => b.metadata['kind'] == 'tocEntry' && b.text.startsWith('Prolog'),
    );
    expect(prolog.metadata['tocPage'], 'vii');
    expect(prolog.text, contains('Kebiasaan Bicara'));

    final chapterLabel = result.blocks.firstWhere(
      (b) => b.metadata['kind'] == 'tocChapterLabel',
    );
    expect(chapterLabel.text, 'BAB I');

    final chapterTitle = result.blocks.firstWhere(
      (b) => b.metadata['kind'] == 'tocChapterTitle',
    );
    expect(chapterTitle.text, contains('Perbedaan Juara'));
  });

  test(
    'Indented TOC person names become sub-entries of the preceding title',
    () {
      final toc = _page(14, [
        _line(
          'Daftar Isi',
          page: 14,
          top: 100,
          left: 220,
          height: 20,
          index: 0,
        ),
        _line('Sosok yang Menawan Telinga ....', page: 14, top: 200, index: 1),
        _line('.... 203', page: 14, top: 202, left: 440, width: 30, index: 2),
        _line(
          'Lee Byung Hun/Lee Seo Jin',
          page: 14,
          top: 230,
          left: 92,
          width: 300,
          index: 3,
        ),
        _line('Laut yang Jernih .....', page: 14, top: 280, index: 4),
        _line('... 209', page: 14, top: 282, left: 440, width: 30, index: 5),
        _line(
          'Song Joong Ki/Kim Su Hyun',
          page: 14,
          top: 310,
          left: 94,
          width: 300,
          index: 6,
        ),
        _line('Annatainer Kaya Karakter ..', page: 14, top: 360, index: 7),
        _line('214', page: 14, top: 362, left: 440, width: 30, index: 8),
        _line('- Kim Seong Joo/Jun Hyun Moo', page: 14, top: 390, index: 9),
        _line('Pembawa Acara Komedi ....', page: 14, top: 440, index: 10),
        _line('... 219', page: 14, top: 442, left: 440, width: 30, index: 11),
        _line('- Yoo Jae Suk/Kim Gur', page: 14, top: 470, index: 12),
      ]);

      final result = TocReconstructor.reconstruct(pages: [toc]);
      final entries = result.blocks
          .where((b) => b.metadata['kind'] == 'tocEntry')
          .map((b) => b.text)
          .toList();
      final persons = result.blocks
          .where((b) => b.metadata['kind'] == 'tocPerson')
          .toList();

      expect(entries, contains('Laut yang Jernih'));
      expect(entries, contains('Annatainer Kaya Karakter'));
      expect(entries, contains('Pembawa Acara Komedi'));
      expect(
        entries.any((e) => e.contains('Lee Byung Hun')),
        isFalse,
        reason: 'person name must not be merged into a work title',
      );
      expect(
        entries.any((e) => e.contains('Song Joong Ki')),
        isFalse,
        reason: 'person name must not be merged into a work title',
      );
      expect(persons.map((b) => b.text), [
        'Lee Byung Hun/Lee Seo Jin',
        'Song Joong Ki/Kim Su Hyun',
        'Kim Seong Joo/Jun Hyun Moo',
        'Yoo Jae Suk/Kim Gur',
      ]);
      expect(
        persons.first.metadata['parentTocTitle'],
        'Sosok yang Menawan Telinga',
      );
      expect(persons[1].metadata['parentTocTitle'], 'Laut yang Jernih');
      expect(persons[2].metadata['parentTocTitle'], 'Annatainer Kaya Karakter');
    },
  );

  test('Page break semantic block maps to a reader page break', () {
    final block = SemanticReconstructedBlock(
      type: SemanticBlockType.pageBreak,
      sourcePageIndex: 3,
    );
    expect(block.toBookBlock().type.name, 'pageBreak');
  });
}
