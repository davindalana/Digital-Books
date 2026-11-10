// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/domain/models/highlight_palette.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_crud_test_');
    final randomSuffix = DateTime.now().microsecondsSinceEpoch;
    dbPath = p.join(tempDir.path, 'crud_test_$randomSuffix.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3.3 — Annotation CRUD, Palette, and Reactive Persistence Audit', () {
    test(
      '1. Full Palette Highlight Creation, Note Attachment, Color Edit, and Deletion',
      () async {
        final appDb = AppDatabase(NativeDatabase(File(dbPath)));
        final dbService = DatabaseService(appDb);

        // Create test book
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-crud-1'),
            title: const drift.Value('Bumi Manusia'),
            author: const drift.Value('Pramoedya Ananta Toer'),
            originalPdfPath: const drift.Value('/path/to/bumi_manusia.pdf'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Test all 6 highlight palette colors
        final colors = ['yellow', 'green', 'blue', 'pink', 'purple', 'gold'];
        expect(HighlightColorType.values.length, equals(6));

        for (int i = 0; i < colors.length; i++) {
          final color = colors[i];
          final annotation = BookAnnotation(
            id: 'hl-palette-$i',
            bookId: 'book-crud-1',
            type: AnnotationType.highlight,
            selectedText: 'Kutipan teks berwarna $color.',
            chapterId: 'ch-0',
            anchorNodeId: 'node-$i',
            startOffset: 10,
            endOffset: 35,
            pageIndex: i + 1,
            color: color,
            createdAt: now.add(Duration(seconds: i)),
          );
          await dbService.saveAnnotation(annotation);
        }

        // Verify all 6 created
        var list = await dbService.getAnnotationsForBook('book-crud-1');
        expect(list.length, equals(6));
        for (final color in colors) {
          expect(
            list.any((a) => a.color == color),
            isTrue,
            reason: 'Palette color $color must be persisted',
          );
        }

        // Add a note to the first highlight
        final firstHl = list.firstWhere((a) => a.id == 'hl-palette-0');
        final updatedWithNote = firstHl.copyWith(
          note: 'Catatan kritis mengenai pemikiran Minke.',
          type: AnnotationType.note,
          updatedAt: DateTime.now(),
        );
        await dbService.saveAnnotation(updatedWithNote);

        var refreshed = await dbService.getAnnotationsForBook('book-crud-1');
        final notedHl = refreshed.firstWhere((a) => a.id == 'hl-palette-0');
        expect(notedHl.hasNote, isTrue);
        expect(
          notedHl.note,
          equals('Catatan kritis mengenai pemikiran Minke.'),
        );
        expect(notedHl.type, equals(AnnotationType.note));

        // Update color from yellow to pink
        final updatedColor = notedHl.copyWith(color: 'pink');
        await dbService.saveAnnotation(updatedColor);

        refreshed = await dbService.getAnnotationsForBook('book-crud-1');
        final colorChangedHl = refreshed.firstWhere(
          (a) => a.id == 'hl-palette-0',
        );
        expect(colorChangedHl.color, equals('pink'));

        // Create a bookmark
        final bookmark = BookAnnotation(
          id: 'bm-test-1',
          bookId: 'book-crud-1',
          type: AnnotationType.bookmark,
          selectedText: 'Halaman 15 - Bab 2',
          pageIndex: 15,
          chapterId: 'ch-1',
          anchorNodeId: 'node-bm-1',
          startOffset: 200,
          endOffset: 200,
          createdAt: DateTime.now(),
        );
        await dbService.saveAnnotation(bookmark);

        refreshed = await dbService.getAnnotationsForBook('book-crud-1');
        expect(
          refreshed.length,
          equals(7),
          reason: '6 highlights + 1 bookmark',
        );
        final foundBm = refreshed.firstWhere((a) => a.id == 'bm-test-1');
        expect(foundBm.isBookmark, isTrue);
        expect(foundBm.pageIndex, equals(15));

        // Delete a highlight
        await dbService.deleteAnnotation(
          'hl-palette-1',
          AnnotationType.highlight,
        );
        refreshed = await dbService.getAnnotationsForBook('book-crud-1');
        expect(refreshed.length, equals(6));
        expect(refreshed.any((a) => a.id == 'hl-palette-1'), isFalse);

        // Delete bookmark
        await dbService.deleteAnnotation('bm-test-1', AnnotationType.bookmark);
        refreshed = await dbService.getAnnotationsForBook('book-crud-1');
        expect(refreshed.length, equals(5));
        expect(refreshed.any((a) => a.id == 'bm-test-1'), isFalse);

        await appDb.close();
      },
    );

    test(
      '2. Reactive Stream: watchAnnotationsForBook emits live changes',
      () async {
        final appDb = AppDatabase(NativeDatabase(File(dbPath)));
        final dbService = DatabaseService(appDb);

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-stream-1'),
            title: const drift.Value('Gadis Kretek'),
            author: const drift.Value('Ratih Kumala'),
            originalPdfPath: const drift.Value('/path/to/gadis_kretek.pdf'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        final stream = dbService.watchAnnotationsForBook('book-stream-1');

        // Add highlight and verify reactive emission
        await dbService.saveAnnotation(
          BookAnnotation(
            id: 'ann-stream-1',
            bookId: 'book-stream-1',
            type: AnnotationType.highlight,
            selectedText: 'Rasa cengkeh di lintingan klobot.',
            createdAt: DateTime.now(),
          ),
        );

        final firstEmission = await stream.firstWhere(
          (list) => list.length == 1,
        );
        expect(firstEmission.length, equals(1));
        expect(firstEmission.first.id, equals('ann-stream-1'));

        // Add bookmark and verify combined reactive emission
        await dbService.saveAnnotation(
          BookAnnotation(
            id: 'ann-stream-2',
            bookId: 'book-stream-1',
            type: AnnotationType.bookmark,
            selectedText: 'Penanda Halaman 7',
            pageIndex: 7,
            createdAt: DateTime.now(),
          ),
        );

        final secondEmission = await stream.firstWhere(
          (list) => list.length == 2,
        );
        expect(secondEmission.length, equals(2));

        // Delete highlight and verify reactive removal emission
        await dbService.deleteAnnotation(
          'ann-stream-1',
          AnnotationType.highlight,
        );

        final thirdEmission = await stream.firstWhere(
          (list) => list.length == 1 && list.first.id == 'ann-stream-2',
        );
        expect(thirdEmission.length, equals(1));
        expect(thirdEmission.first.id, equals('ann-stream-2'));

        await appDb.close();
      },
    );

    test(
      '3. Cold Restart Persistence: Data survives complete database close and re-open',
      () async {
        // Step A: Save annotation in first database instance
        var appDb = AppDatabase(NativeDatabase(File(dbPath)));
        var dbService = DatabaseService(appDb);

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-restart-1'),
            title: const drift.Value('Cantik Itu Luka'),
            author: const drift.Value('Eka Kurniawan'),
            originalPdfPath: const drift.Value('/path/to/cantik_itu_luka.pdf'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        await dbService.saveAnnotation(
          BookAnnotation(
            id: 'ann-persist-1',
            bookId: 'book-restart-1',
            type: AnnotationType.note,
            selectedText:
                'Sore hari di akhir pekan, Dewi Ayu bangkit dari kuburan.',
            note: 'Paragraf pembuka yang ikonik dalam sastra Indonesia.',
            color: 'gold',
            pageIndex: 1,
            anchorNodeId: 'node-opening-1',
            startOffset: 0,
            endOffset: 56,
            createdAt: now,
          ),
        );

        // Simulate app kill / database dispose
        await appDb.close();

        // Step B: Re-open database from disk
        appDb = AppDatabase(NativeDatabase(File(dbPath)));
        dbService = DatabaseService(appDb);

        final reloaded = await dbService.getAnnotationsForBook(
          'book-restart-1',
        );
        expect(reloaded.length, equals(1));
        final reloadedAnn = reloaded.first;
        expect(reloadedAnn.id, equals('ann-persist-1'));
        expect(
          reloadedAnn.selectedText,
          equals('Sore hari di akhir pekan, Dewi Ayu bangkit dari kuburan.'),
        );
        expect(
          reloadedAnn.note,
          equals('Paragraf pembuka yang ikonik dalam sastra Indonesia.'),
        );
        expect(reloadedAnn.color, equals('gold'));
        expect(reloadedAnn.anchorNodeId, equals('node-opening-1'));
        expect(reloadedAnn.startOffset, equals(0));
        expect(reloadedAnn.endOffset, equals(56));

        await appDb.close();
      },
    );
  });
}
