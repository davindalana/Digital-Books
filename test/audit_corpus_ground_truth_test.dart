// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';

const _bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
const _jsonPath =
    '/Users/davindalana/Documents/DigitalBooks/books/$_bookId.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Audit corpus ground truth: OCR, TOC, and paragraph continuations', () async {
    final dbFile = File('/Users/davindalana/Documents/digital_books_db.sqlite');
    final pdfFile = File(
      '/Users/davindalana/Documents/DigitalBooks/originals/$_bookId.pdf',
    );

    BookDocument? bookDoc;
    if (dbFile.existsSync() && pdfFile.existsSync()) {
      final db = AppDatabase(NativeDatabase(dbFile));
      final dbService = DatabaseService(db);
      final pipeline = OcrSemanticPipeline(dbService);
      bookDoc = await pipeline.reconstructDocument(
        bookId: _bookId,
        pdfPath: pdfFile.path,
      );
      await db.close();
      print(
        'Audited document reconstructed in-memory from OCR pages (db read-only).',
      );
    }

    if (bookDoc == null) {
      final file = File(_jsonPath);
      if (!file.existsSync()) {
        markTestSkipped('Real book JSON corpus not found at ${file.path}');
        return;
      }
      bookDoc = BookDocument.fromJsonString(await file.readAsString());
      print('Audited document loaded from pre-existing JSON.');
    }

    final readerDoc = ReflowableEngine.normalizeDocument(bookDoc);

    // 1. Audit OCR Corrections
    print('\n=== 1. OCR CORRECTION AUDIT ===');
    var ocrCorrectionCount = 0;
    final correctionsList = <Map<String, dynamic>>[];
    for (final ch in readerDoc.chapters) {
      for (final n in ch.nodes) {
        final corrections = n.attributes['ocrCorrections'];
        if (corrections is List && corrections.isNotEmpty) {
          ocrCorrectionCount += corrections.length;
          for (final c in corrections) {
            correctionsList.add({
              'chapter': ch.title,
              'nodeId': n.id,
              'correction': c,
            });
          }
        }
      }
    }
    print('Total OCR corrections recorded in metadata: $ocrCorrectionCount');
    for (final c in correctionsList) {
      print('  [${c['chapter']}] ${c['correction']}');
    }

    // Verify critical token corrections:
    // - BAB III title: MEMHAK -> MEMIHAK
    final bab3 = readerDoc.chapters.firstWhere(
      (c) => c.title.contains('BAB III'),
      orElse: () => throw StateError('BAB III not found'),
    );
    expect(bab3.title.toLowerCase(), contains('memihak'));
    print(
      'Verified: BAB III title contains "Memihak" (original OCR had MEMHAK)',
    );

    // - TOC chapter title for BAB III
    final tocChapter = readerDoc.chapters.firstWhere(
      (c) => c.index == 3 || c.title.contains('Daftar Isi'),
      orElse: () => throw StateError('TOC chapter not found'),
    );
    final bab3TocTitle = tocChapter.nodes.firstWhere(
      (n) =>
          n.attributes['kind'] == 'tocChapterTitle' &&
          n.text.contains('Memihak'),
      orElse: () => throw StateError('BAB III TOC title not found'),
    );
    expect(bab3TocTitle.text, contains('Memihak'));
    print('Verified: TOC entry for BAB III contains "Memihak"');

    // - TOC Sentuha -> Sentuhan
    final sentuhanToc = tocChapter.nodes.firstWhere(
      (n) => n.text.contains('Sentuhan Suara yang Lembut'),
      orElse: () => throw StateError('Sentuhan TOC entry not found'),
    );
    expect(sentuhanToc.text, contains('Sentuhan'));
    print('Verified: TOC entry contains "Sentuhan" (corrected from Sentuha)');

    // 2. Audit Cross-Page Paragraph Continuations
    print('\n=== 2. PARAGRAPH CONTINUATION AUDIT ===');
    var continuationCount = 0;
    for (final ch in readerDoc.chapters) {
      for (final n in ch.nodes) {
        if (n.attributes['paragraphContinuation'] == true) {
          continuationCount++;
        }
      }
    }
    print('Total merged paragraph continuations: $continuationCount');

    // Verify dialogues are NEVER absorbed
    var absorbedDialogues = 0;
    for (final ch in readerDoc.chapters) {
      for (final n in ch.nodes) {
        if (n.attributes['paragraphContinuation'] == true) {
          final text = n.text;
          // Check if any dialogue was illegally absorbed into a prior paragraph
          if (RegExp(r"""\.\s*["“‘][A-Z]""").hasMatch(text)) {
            absorbedDialogues++;
          }
        }
      }
    }
    expect(
      absorbedDialogues,
      0,
      reason: 'Dialogue lines must never be absorbed into preceding paragraphs',
    );
    print('Verified: 0 dialogue lines absorbed across page breaks.');

    // 3. Audit Short Blocks (< 30 characters) in Prose
    print('\n=== 3. SHORT BLOCKS (< 30 chars) AUDIT ===');
    final shortBlocks = <Map<String, dynamic>>[];
    for (final ch in readerDoc.chapters) {
      if (ch.index <= 3) continue; // Skip front matter & TOC
      for (final n in ch.nodes) {
        final t = n.text.trim();
        if (t.length < 30 && t.isNotEmpty) {
          shortBlocks.add({
            'chapter': ch.title,
            'type': n.type.name,
            'kind': n.attributes['kind'] ?? '-',
            'text': t,
          });
        }
      }
    }
    print('Total short blocks in body chapters: ${shortBlocks.length}');
    for (final sb in shortBlocks) {
      print('  [${sb['type']}|${sb['kind']}] "${sb['text']}"');
    }

    // 4. Audit TOC Structure
    print('\n=== 4. TABLE OF CONTENTS AUDIT ===');
    print('Total TOC nodes: ${tocChapter.nodes.length}');
    expect(tocChapter.nodes.length, 61);

    final tocPersons = tocChapter.nodes
        .where((n) => n.attributes['kind'] == 'tocPerson')
        .toList();
    print('TOC persons identified: ${tocPersons.length}');
    for (final p in tocPersons) {
      print('  person: "${p.text}" (page: ${p.attributes['tocPage']})');
    }
    expect(tocPersons.length, 7);

    final tocChapterLabels = tocChapter.nodes
        .where((n) => n.attributes['kind'] == 'tocChapterLabel')
        .toList();
    print(
      'TOC chapter labels: ${tocChapterLabels.map((l) => l.text).toList()}',
    );
    expect(tocChapterLabels.length, 5);

    // Verify dot leaders are stripped from titles
    for (final n in tocChapter.nodes) {
      if (n.attributes['kind'] == 'tocEntry') {
        expect(
          n.text.endsWith('.'),
          isFalse,
          reason:
              'TOC entry "${n.text}" should not end with dot leader remnants',
        );
      }
    }
    print('Verified: All TOC entries have dot leaders cleanly stripped.');

    // 5. Structure and Semantic Invariants
    print('\n=== 5. STRUCTURE AND SEMANTIC INVARIANTS ===');
    final ch4 = readerDoc.chapters.firstWhere((c) => c.title.contains('BAB I'));
    final tema = ch4.nodes.firstWhere((n) => n.text == '1. Tema');
    final konflik = ch4.nodes.firstWhere((n) => n.text == '2. Konflik');
    final simpati = ch4.nodes.firstWhere((n) => n.text == '3. Simpati');
    final solusi = ch4.nodes.firstWhere((n) => n.text == '4. Solusi');
    expect(tema.type, ContentNodeType.orderedList);
    expect(konflik.type, ContentNodeType.orderedList);
    expect(simpati.type, ContentNodeType.orderedList);
    expect(solusi.type, ContentNodeType.orderedList);
    print(
      'Verified: 1. Tema, 2. Konflik, 3. Simpati, 4. Solusi all classified as orderedList.',
    );

    // Year 2013 not classified as orderedList
    final ch8 = readerDoc.chapters.firstWhere((c) => c.title.contains('BAB V'));
    final yearNode = ch8.nodes.firstWhere((n) => n.text.contains('2013.'));
    expect(yearNode.type, ContentNodeType.paragraph);
    print(
      'Verified: 2013. year boundary classified as paragraph, not ordered list.',
    );

    // Oprah Winfrey paragraph
    final oprahNode = readerDoc.chapters
        .expand((c) => c.nodes)
        .firstWhere((n) => n.text.contains('Oprah'));
    expect(oprahNode.type, ContentNodeType.paragraph);
    print(
      'Verified: Oprah Winfrey passage classified as paragraph: "${oprahNode.text.substring(0, 40)}..."',
    );
  });
}
