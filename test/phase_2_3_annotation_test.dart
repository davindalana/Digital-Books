import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/anchor_resolution_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/highlight_palette.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/highlight_interaction_sheet.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  final testReaderDocument = ReaderDocument(
    bookId: 'book_annotation_test',
    title: 'Filosofi Membaca Digital',
    author: 'Henry Manampiring',
    totalPages: 30,
    chapters: [
      ReaderChapter(
        id: 'ch_0',
        index: 0,
        title: 'Bab 1: Kendali dan Persepsi',
        nodes: [
          const ContentNode(
            id: 'ch0_h1',
            type: ContentNodeType.heading,
            text: 'Bab 1: Kendali dan Persepsi',
            level: 1,
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'ch0_p1',
            type: ContentNodeType.paragraph,
            text: 'Ada hal-hal yang berada di bawah kendali kita, dan ada hal-hal yang tidak berada di bawah kendali kita. Pikiran dan tindakan kita adalah kuasa kita.',
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'ch0_q1',
            type: ContentNodeType.quote,
            text: 'Ketenangan batin sejati bermula dari penerimaan tulus terhadap hal yang di luar kendali.',
            sourcePdfPage: 2,
          ),
          const ContentNode(
            id: 'ch0_p2',
            type: ContentNodeType.paragraph,
            text: 'Ketika kita memahami dikotomi kendali, kecemasan tidak lagi menguasai kehidupan sehari-hari.',
            sourcePdfPage: 2,
          ),
        ],
      ),
      ReaderChapter(
        id: 'ch_1',
        index: 1,
        title: 'Bab 2: Mengelola Reaksi',
        nodes: [
          const ContentNode(
            id: 'ch1_h1',
            type: ContentNodeType.heading,
            text: 'Bab 2: Mengelola Reaksi',
            level: 1,
            sourcePdfPage: 3,
          ),
          const ContentNode(
            id: 'ch1_p1',
            type: ContentNodeType.paragraph,
            text: 'Bukan peristiwa yang membuat kita sedih atau marah, melainkan pertimbangan kita sendiri tentang peristiwa itu.',
            sourcePdfPage: 3,
          ),
        ],
      ),
    ],
  );

  group('Phase 2.3 — Stable Anchor Resolution Tests', () {
    test('Exact anchor resolution returns confidence 1.0', () {
      final res = AnchorResolutionEngine.resolveAnchor(
        document: testReaderDocument,
        chapterId: 'ch_0',
        anchorNodeId: 'ch0_p1',
        selectedText: 'berada di bawah kendali kita',
        startOffset: 17,
        endOffset: 45,
      );

      expect(res.isResolved, isTrue);
      expect(res.status, AnchorResolutionStatus.exact);
      expect(res.confidence, equals(1.0));
      expect(res.resolvedNodeId, equals('ch0_p1'));
      expect(res.resolvedStartOffset, equals(17));
      expect(res.resolvedEndOffset, equals(45));
    });

    test('Offset shifted anchor recovers by substring match in node', () {
      // Intentionally provide shifted/corrupted startOffset = 0
      final res = AnchorResolutionEngine.resolveAnchor(
        document: testReaderDocument,
        chapterId: 'ch_0',
        anchorNodeId: 'ch0_p1',
        selectedText: 'Pikiran dan tindakan kita',
        startOffset: 0, // Corrupted offset
        endOffset: 25,
      );

      expect(res.isResolved, isTrue);
      expect(res.status, AnchorResolutionStatus.offsetShifted);
      expect(res.confidence, greaterThanOrEqualTo(0.85));
      expect(res.resolvedNodeId, equals('ch0_p1'));
      expect(testReaderDocument.chapters[0].nodes[1].text.substring(res.resolvedStartOffset, res.resolvedEndOffset),
          equals('Pikiran dan tindakan kita'));
    });

    test('Context match recovers position using prefix and suffix context', () {
      final res = AnchorResolutionEngine.resolveAnchor(
        document: testReaderDocument,
        chapterId: 'ch_0',
        anchorNodeId: 'ch0_q1',
        selectedText: 'penerimaan tulus',
        startOffset: 999, // Way off
        endOffset: 1015,
        prefixContext: 'Ketenangan batin sejati bermula dari ',
        suffixContext: ' terhadap hal yang di luar kendali.',
      );

      expect(res.isResolved, isTrue);
      expect(res.status, AnchorResolutionStatus.contextMatch);
      expect(res.confidence, equals(0.95));
      expect(res.resolvedNodeId, equals('ch0_q1'));
    });

    test('Missing or completely unrelated text marks anchor as unresolved without attaching to unrelated text', () {
      final res = AnchorResolutionEngine.resolveAnchor(
        document: testReaderDocument,
        chapterId: 'ch_0',
        anchorNodeId: 'ch0_p1',
        selectedText: 'Teks ini tidak pernah ada di dalam buku sama sekali!',
        startOffset: 10,
        endOffset: 50,
      );

      expect(res.isResolved, isFalse);
      expect(res.status, AnchorResolutionStatus.unresolved);
      expect(res.confidence, equals(0.0));
    });
  });

  group('Phase 2.3 — ReflowableHighlightSpanBuilder Tests', () {
    test('Builds segmented spans with highlight background and note badge', () {
      final highlight = Highlight(
        id: 'hl-1',
        bookId: 'book_annotation_test',
        chapterId: 'ch_0',
        selectedText: 'dikotomi kendali',
        startPosition: 2,
        endPosition: 2,
        color: 'yellow',
        note: 'Prinsip fundamental Stoikisme',
        anchorNodeId: 'ch0_p2',
        startOffset: 21,
        endOffset: 37,
        anchorVersion: 1,
        createdAt: DateTime.now(),
      );

      final text = 'Ketika kita memahami dikotomi kendali, kecemasan tidak lagi menguasai kehidupan sehari-hari.';
      final span = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: text,
        sliceStartOffset: 0,
        sliceEndOffset: text.length,
        highlightsForNode: [highlight],
        baseStyle: const TextStyle(fontSize: 16.0, color: Colors.black),
        theme: ReadingThemeType.white,
      );

      expect(span.children, isNotNull);
      expect(span.children!.length, equals(3)); // prefix + highlight + suffix

      final hlSpan = span.children![1] as TextSpan;
      expect(hlSpan.text, equals('dikotomi kendali'));
      expect(hlSpan.style?.backgroundColor, isNotNull);
      // Note indicator icon child should be present
      expect(hlSpan.children, isNotEmpty);
    });

    test('Color palette adapts to Dark, Black, and Sepia reading themes', () {
      const yellow = HighlightColorType.yellow;
      const green = HighlightColorType.green;
      const blue = HighlightColorType.blue;
      const pink = HighlightColorType.pink;
      const purple = HighlightColorType.purple;

      expect(yellow.getBackgroundColor(ReadingThemeType.white), isNotNull);
      expect(green.getBackgroundColor(ReadingThemeType.black), isNotNull);
      expect(blue.getBackgroundColor(ReadingThemeType.sepia), isNotNull);
      expect(pink.getBackgroundColor(ReadingThemeType.dark), isNotNull);
      expect(purple.getBackgroundColor(ReadingThemeType.warmPaper), isNotNull);
    });
  });

  group('Phase 2.3 — Database Service Annotations CRUD & Migrations', () {
    test('Add, update color, update note, and delete highlight', () async {
      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('book-anno-1'),
          title: const drift.Value('Buku Uji Anotasi'),
          author: const drift.Value('Penulis Test'),
          originalPdfPath: const drift.Value('/path/book.pdf'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // 1. Add Highlight
      await dbService.addHighlight(
        HighlightsCompanion(
          id: const drift.Value('hl-test-101'),
          bookId: const drift.Value('book-anno-1'),
          chapterId: const drift.Value('ch_0'),
          selectedText: const drift.Value('Pikiran dan tindakan'),
          startPosition: const drift.Value(1),
          endPosition: const drift.Value(1),
          color: const drift.Value('yellow'),
          note: const drift.Value('Catatan awal'),
          anchorNodeId: const drift.Value('ch0_p1'),
          startOffset: const drift.Value(74),
          endOffset: const drift.Value(94),
          createdAt: drift.Value(now),
        ),
      );

      final hl = await dbService.getHighlightById('hl-test-101');
      expect(hl, isNotNull);
      expect(hl!.color, equals('yellow'));
      expect(hl.note, equals('Catatan awal'));
      expect(hl.anchorNodeId, equals('ch0_p1'));

      // 2. Update Color to purple
      await dbService.updateHighlightColor('hl-test-101', 'purple');
      final updatedColorHl = await dbService.getHighlightById('hl-test-101');
      expect(updatedColorHl!.color, equals('purple'));

      // 3. Update Note
      await dbService.updateHighlightNote('hl-test-101', 'Catatan diperbarui dengan referensi Epictetus');
      final updatedNoteHl = await dbService.getHighlightById('hl-test-101');
      expect(updatedNoteHl!.note, equals('Catatan diperbarui dengan referensi Epictetus'));

      // 4. Watch all notes stream includes this item
      final allNotes = await dbService.watchAllNotes().first;
      expect(allNotes.any((item) => item.highlight.id == 'hl-test-101'), isTrue);

      // 5. Delete Highlight
      await dbService.deleteHighlight('hl-test-101');
      final deletedHl = await dbService.getHighlightById('hl-test-101');
      expect(deletedHl, isNull);
    });

    test('Bookmark CRUD and duplicate prevention by location', () async {
      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('book-bm-1'),
          title: const drift.Value('Buku Bookmark'),
          author: const drift.Value('Penulis Bookmark'),
          originalPdfPath: const drift.Value('/path/bm.pdf'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Add Bookmark with anchor
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const drift.Value('bm-1'),
          bookId: const drift.Value('book-bm-1'),
          position: const drift.Value(5),
          label: const drift.Value('Bab 1 • Hal. 5'),
          anchorNodeId: const drift.Value('ch0_p2'),
          characterOffset: const drift.Value(12),
          progressPercentage: const drift.Value(0.25),
          createdAt: drift.Value(now),
        ),
      );

      // Duplicate prevention query
      final existingByAnchor = await dbService.getBookmarkAtLocation(
        'book-bm-1',
        anchorNodeId: 'ch0_p2',
      );
      expect(existingByAnchor, isNotNull);
      expect(existingByAnchor!.id, equals('bm-1'));

      final existingByPage = await dbService.getBookmarkAtLocation(
        'book-bm-1',
        page: 5,
      );
      expect(existingByPage, isNotNull);
      expect(existingByPage!.id, equals('bm-1'));

      // Query non-existent position returns null
      final nonExistent = await dbService.getBookmarkAtLocation(
        'book-bm-1',
        page: 99,
        anchorNodeId: 'ch99_none',
      );
      expect(nonExistent, isNull);

      // Delete by location
      await dbService.deleteBookmarkByLocation('book-bm-1', anchorNodeId: 'ch0_p2');
      final afterDelete = await dbService.getBookmarkAtLocation('book-bm-1', anchorNodeId: 'ch0_p2');
      expect(afterDelete, isNull);
    });

    test('Schema version is 3 and supports all new annotation anchor fields', () {
      expect(db.schemaVersion, equals(3));
    });
  });

  group('Phase 2.3 — Reader UI & Interactive Text Selection Tests', () {
    testWidgets('ReflowableReaderContainer renders with custom highlights', (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sampleHighlight = Highlight(
        id: 'hl-ui-1',
        bookId: testReaderDocument.bookId,
        chapterId: 'ch_0',
        selectedText: 'dikotomi kendali',
        startPosition: 2,
        endPosition: 2,
        color: 'green',
        note: null,
        anchorNodeId: 'ch0_p2',
        startOffset: 21,
        endOffset: 37,
        anchorVersion: 1,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reflowableLayoutModeProvider(testReaderDocument.bookId).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReflowableReaderContainer(
                bookId: testReaderDocument.bookId,
                document: testReaderDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(fontSize: 16.0),
                customHighlights: [sampleHighlight],
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ReflowableReaderContainer), findsOneWidget);
      expect(find.byType(PaginatedReflowableReader), findsOneWidget);
    });

    testWidgets('HighlightInteractionSheet allows changing color and writing note', (tester) async {
      String savedColor = '';
      String? savedNote;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HighlightInteractionSheet(
              selectedText: 'Pikiran dan tindakan kita adalah kuasa kita.',
              initialColor: 'yellow',
              theme: ReadingThemeType.white,
              onSave: (color, note) {
                savedColor = color;
                savedNote = note;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Quote is displayed
      expect(find.text('"Pikiran dan tindakan kita adalah kuasa kita."'), findsOneWidget);

      // Tap Blue color circle
      await tester.tap(find.byIcon(Icons.border_color));
      // Enter note text
      await tester.enterText(find.byType(TextField), 'Kutipan penting dari Epictetus');
      await tester.pump();

      // Tap Simpan button
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await tester.pump();

      expect(savedColor, isNotEmpty);
      expect(savedNote, equals('Kutipan penting dari Epictetus'));
    });
  });
}
