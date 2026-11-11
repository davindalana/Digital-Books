// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:digital_books/features/processing/services/chapter_quality_normalizer.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BookBlock paragraph(String id, String text, {int page = 1}) => BookBlock(
    id: id,
    type: BlockType.paragraph,
    text: text,
    originalPageNumber: page,
  );

  BookBlock heading(String id, String text, {int page = 1}) => BookBlock(
    id: id,
    type: BlockType.heading,
    text: text,
    originalPageNumber: page,
  );

  BookChapter chapter(
    String id,
    String title,
    List<BookBlock> blocks, {
    int index = 0,
  }) => BookChapter(id: id, index: index, title: title, blocks: blocks);

  Map<String, int> textCounts(Iterable<BookBlock> blocks) {
    final counts = <String, int>{};
    for (final block in blocks) {
      final text = block.text.trim();
      if (text.isEmpty) continue;
      counts.update(text, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  group('real saved artifact: Laut Bercerita (pre-3.8 pipeline)', () {
    late BookDocument original;
    late List<BookChapter> normalized;

    setUpAll(() {
      final resolved = requireRealBook(RealBookFixtures.lautSavedArtifact);
      final json =
          jsonDecode(resolved.file.readAsStringSync()) as Map<String, dynamic>;
      original = BookDocument.fromJson(json);
      resolved.report(
        'loaded saved artifact',
        details: {
          'chapters': original.chapters.length,
          'blocks': original.chapters.fold<int>(
            0,
            (sum, c) => sum + c.blocks.length,
          ),
        },
      );
      normalized = ChapterQualityNormalizer.normalize(original.chapters);
    });

    test('duplicate chapter titles are merged', () {
      final titles = normalized
          .map((c) => c.title.trim().toLowerCase())
          .toList();
      expect(
        titles.toSet().length,
        titles.length,
        reason: 'Chapter titles must be unique after normalization: $titles',
      );

      expect(
        normalized.where((c) => c.title == 'Prolog').length,
        1,
        reason:
            'The table-of-contents Prolog entry must merge with the '
            'real Prolog chapter.',
      );
      expect(
        normalized.where((c) => c.title == 'Ucapan Terima Kasih').length,
        1,
      );
    });

    test('sentence-like display lines are not chapter titles', () {
      for (final c in normalized) {
        expect(
          c.title.trim().endsWith('.'),
          isFalse,
          reason: 'Sentence fragments must not become chapters: "${c.title}"',
        );
      }
      expect(normalized.length, lessThan(original.chapters.length));
    });

    test('table-of-contents chapter is folded into front matter', () {
      expect(normalized.any((c) => c.title == 'Daftar Isi'), isFalse);
    });

    test('all body content is preserved', () {
      final before = <String, int>{};
      for (final chapter in original.chapters) {
        for (final block in chapter.blocks) {
          final text = block.text.trim();
          if (text.isEmpty) continue;
          // A heading that only repeats its own chapter title is removed by
          // the normalizer; that is the intended de-duplication.
          final isDuplicateTitleHeading =
              (block.type == BlockType.heading ||
                  block.type == BlockType.sectionHeading) &&
              text.toLowerCase() == chapter.title.trim().toLowerCase();
          if (isDuplicateTitleHeading) continue;
          before.update(text, (value) => value + 1, ifAbsent: () => 1);
        }
      }
      final after = textCounts(normalized.expand((c) => c.blocks));

      for (final entry in before.entries) {
        final remaining = after[entry.key] ?? 0;
        expect(
          remaining,
          greaterThanOrEqualTo(entry.value),
          reason:
              'Text was lost during normalization: "${entry.key}" '
              '(before ${entry.value}, after $remaining)',
        );
      }
    });

    test('every chapter still has readable blocks', () {
      for (final c in normalized) {
        expect(c.blocks, isNotEmpty, reason: 'Empty chapter: ${c.title}');
        expect(
          c.blocks.any((b) => b.text.trim().isNotEmpty),
          isTrue,
          reason: 'Chapter has no text: ${c.title}',
        );
      }
    });
  });

  group('real PDF: The Let Them Theory (native text layer)', () {
    late BookDocument doc;
    late int extractionChars;

    setUpAll(() async {
      final resolved = requireRealBook(RealBookFixtures.letThemTheory);
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: resolved.file,
        bookId: 'phase38-letthem',
        extractImagesToDisk: false,
      );
      extractionChars = extraction.pages.fold<int>(
        0,
        (sum, page) => sum + page.charCount,
      );
      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: resolved.fixture.title,
        author: 'Mel Robbins',
      );
      doc = reconstructed.toBookDocument();
      resolved.report(
        'reconstructed',
        details: {
          'pages': extraction.totalPages,
          'usableTextLayer': extraction.hasUsableTextLayer,
          'chapters': doc.chapters.length,
          'blocks': doc.chapters.fold<int>(
            0,
            (sum, c) => sum + c.blocks.length,
          ),
          'quality': reconstructed.quality.status.name,
        },
      );
    });

    test('table-of-contents entries are not promoted to chapters', () {
      final titles = doc.chapters.map((c) => c.title).toList();
      expect(
        titles.any((t) => t.contains('Table of Contents')),
        isFalse,
        reason: 'TOC header leaked as a chapter: $titles',
      );
      expect(
        titles.any((t) => t.contains('My Story')),
        isFalse,
        reason:
            'TOC entry "Introduction: My Story" leaked as a chapter: $titles',
      );
      expect(
        titles.where((t) => t.toUpperCase().startsWith('CONCLUSION')).length,
        1,
        reason:
            'The TOC conclusion entry must not create a second chapter: '
            '$titles',
      );
    });

    test('chapter order follows the document', () {
      final starts = <int>[];
      for (final c in doc.chapters) {
        final pages = c.blocks
            .map((b) => b.originalPageNumber)
            .where((p) => p > 0)
            .toList();
        starts.add(pages.isEmpty ? 0 : pages.reduce((a, b) => a < b ? a : b));
      }
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i],
          greaterThanOrEqualTo(starts[i - 1]),
          reason:
              'Chapter $i ("${doc.chapters[i].title}") starts before the '
              'previous chapter: $starts',
        );
      }
    });

    test('chapter numbering is complete and sequential', () {
      final numbers = doc.chapters
          .map((c) => RegExp(r'^CHAPTER\s+(\d+)$').firstMatch(c.title.trim()))
          .whereType<RegExpMatch>()
          .map((m) => int.parse(m.group(1)!))
          .toList();

      expect(numbers.length, greaterThanOrEqualTo(20));
      expect(numbers, List<int>.generate(numbers.length, (i) => i + 1));
      expect(doc.chapters.any((c) => c.title == 'INTRODUCTION'), isTrue);
      expect(doc.chapters.last.title, 'CONCLUSION');
    });

    test('no duplicated or sentence-like chapter titles', () {
      final titles = doc.chapters.map((c) => c.title.trim()).toList();
      expect(titles.toSet().length, titles.length, reason: '$titles');
      for (final title in titles) {
        expect(
          title.endsWith('.'),
          isFalse,
          reason: 'Sentence title promoted to chapter: "$title"',
        );
      }
    });

    test('body text is preserved through reconstruction', () {
      final docChars = doc.chapters.fold<int>(
        0,
        (sum, c) => sum + c.blocks.fold<int>(0, (s, b) => s + b.text.length),
      );
      expect(
        docChars,
        greaterThan(extractionChars * 0.97),
        reason:
            'Reconstruction dropped too much text: '
            '$docChars vs $extractionChars extracted characters.',
      );
    });
  });

  group('normalization rules', () {
    test('tiny duplicate title merges into the substantial chapter', () {
      final chapters = [
        chapter('c1', 'Prolog', [
          heading('h1', 'Prolog'),
          paragraph('p1', 'Daftar isi: Prolog .... 13'),
        ]),
        chapter('c2', 'Prolog', [
          heading('h2', 'Prolog'),
          paragraph('p2', 'Isi prolog yang sebenarnya.'),
        ], index: 1),
      ];

      final result = ChapterQualityNormalizer.normalize(chapters);

      expect(result, hasLength(1));
      expect(result.single.title, 'Prolog');
      final texts = result.single.blocks.map((b) => b.text).toList();
      expect(texts, contains('Daftar isi: Prolog .... 13'));
      expect(texts, contains('Isi prolog yang sebenarnya.'));
      expect(
        texts.where((t) => t == 'Prolog').length,
        1,
        reason: 'Only one title heading should survive the merge.',
      );
    });

    test('sentence display line merges into the previous chapter', () {
      final chapters = [
        chapter('c1', 'Ucapan Terima Kasih', [
          paragraph('p1', 'Terima kasih kepada semua pembaca.'),
        ]),
        chapter('c2', 'bagian dari kisah mereka. Dan kisah kita juga.', [
          paragraph('p2', 'Kalimat penutup yang panjang.'),
        ], index: 1),
      ];

      final result = ChapterQualityNormalizer.normalize(chapters);

      expect(result, hasLength(1));
      expect(result.single.title, 'Ucapan Terima Kasih');
      expect(
        result.single.blocks.map((b) => b.text),
        contains('Kalimat penutup yang panjang.'),
      );
    });

    test(
      'heading-only table-of-contents chapter merges into its neighbour',
      () {
        final chapters = [
          chapter('c1', 'Pengantar', [
            paragraph('p1', 'Kata pengantar penerbit.'),
          ]),
          chapter('c2', 'Daftar Isi', [heading('h2', 'Daftar Isi')], index: 1),
          chapter('c3', 'Bab 1', [
            paragraph('p3', 'Isi bab pertama.'),
          ], index: 2),
        ];

        final result = ChapterQualityNormalizer.normalize(chapters);

        expect(result.map((c) => c.title), ['Pengantar', 'Bab 1']);
      },
    );

    test('a contents chapter with real entries is preserved', () {
      final chapters = [
        chapter('c1', 'Pengantar', [
          paragraph('p1', 'Kata pengantar penerbit.'),
        ]),
        chapter('c2', 'Daftar Isi', [
          heading('h2', 'Daftar Isi'),
          paragraph('p2', 'Bab 1 .... 5'),
        ], index: 1),
      ];

      final result = ChapterQualityNormalizer.normalize(chapters);

      expect(result.map((c) => c.title), ['Pengantar', 'Daftar Isi']);
      expect(result.last.blocks.map((b) => b.text), contains('Bab 1 .... 5'));
    });

    test('consecutive duplicate headings are collapsed', () {
      final result = ChapterQualityNormalizer.normalize([
        chapter('c1', 'Bab 1', [
          heading('h1', 'Bab 1'),
          heading('h2', 'Bab 1'),
          paragraph('p1', 'Isi.'),
        ]),
      ]);

      expect(
        result.single.blocks.where((b) => b.type == BlockType.heading).length,
        1,
      );
    });

    test('a roman label inside an arabic sequence is repaired', () {
      final result = ChapterQualityNormalizer.normalize([
        chapter('c10', 'CHAPTER 10', [paragraph('p10', 'Sepuluh.')]),
        chapter('c11', 'CHAPTER II', [paragraph('p11', 'Sebelas.')], index: 1),
        chapter('c12', 'CHAPTER 12', [
          paragraph('p12', 'Dua belas.'),
        ], index: 2),
      ]);

      expect(result.map((c) => c.title), [
        'CHAPTER 10',
        'CHAPTER 11',
        'CHAPTER 12',
      ]);
    });

    test('a genuine roman numbering scheme is left untouched', () {
      final result = ChapterQualityNormalizer.normalize([
        chapter('c1', 'BAB I', [paragraph('p1', 'Satu.')]),
        chapter('c2', 'BAB II', [paragraph('p2', 'Dua.')], index: 1),
        chapter('c3', 'BAB III', [paragraph('p3', 'Tiga.')], index: 2),
      ]);

      expect(result.map((c) => c.title), ['BAB I', 'BAB II', 'BAB III']);
    });
  });
}
