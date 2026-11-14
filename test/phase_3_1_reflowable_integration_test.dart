// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/services/file_storage_service.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/background_ocr_queue.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:path/path.dart' as p;
import 'helpers/real_book_fixtures.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempAppDir;
  late AppDatabase db;
  late DatabaseService dbService;
  late AppleVisionOcrService ocrService;
  late OcrSemanticPipeline pipeline;
  late BackgroundOcrQueue queue;

  final lautPdf = File(
    p.join(RealBookFixtures.downloadsDir, 'Laut Bercerita (Leila S. Chudori).pdf'),
  );

  setUp(() async {
    if (!checkFixtureOrSkip(lautPdf)) return;
    tempAppDir = Directory.systemTemp.createTempSync('digital_books_e_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempAppDir);

    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    ocrService = const AppleVisionOcrService();
    pipeline = OcrSemanticPipeline(dbService);
    queue = BackgroundOcrQueue(
      dbService: dbService,
      ocrService: ocrService,
      semanticPipeline: pipeline,
    );
  });

  tearDown(() async {
    queue.dispose();
    await db.close();
    try {
      tempAppDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Phase 3.1 Checkpoint E: Reflowable Reader Integration & Search', () {
    test(
      '1. In-Book Search operates seamlessly on OCR-reconstructed text',
      () async {
        // Seed book and perform OCR on pages 14-16
        await dbService.insertBook(
          BooksCompanion(
            id: const Value('book_search_test'),
            title: const Value('Laut Bercerita'),
            author: const Value('Leila S. Chudori'),
            originalPdfPath: Value(lautPdf.path),
            totalPages: const Value(379),
            isScanned: const Value(true),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

        await queue.start(
          bookId: 'book_search_test',
          pdfPath: lautPdf.path,
          startPage: 14,
          endPage: 16,
          autoReconstruct: true,
        );

        final book = await dbService.getBookById('book_search_test');
        expect(book!.processedBookPath, isNotNull);

        final jsonStr = await FileStorageService.readProcessedBook(
          book.processedBookPath!,
        );
        expect(jsonStr, isNotNull);

        final bookDoc = BookDocument.fromJsonString(jsonStr!);
        final readerDoc = ReflowableEngine.normalizeDocument(bookDoc);

        // Perform search for Indonesian word recognized from page 15
        final searchResults = await InBookSearchEngine.search(
          document: readerDoc,
          query: 'mobil',
        );

        expect(searchResults.isNotEmpty, isTrue);
        final firstMatch = searchResults.first;
        expect(firstMatch.matchedText.toLowerCase(), contains('mobil'));
        // Source PDF page should be 15
        expect(firstMatch.sourcePdfPage, equals(15));

        print(
          '\n===============================================================',
        );
        print('CHECKPOINT E: IN-BOOK SEARCH ON OCR TEXT AUDIT');
        print(
          '===============================================================',
        );
        print('Matches found for "mobil": ${searchResults.length}');
        print('First match snippet: "${firstMatch.snippet}"');
        print('Matched node sourcePdfPage: ${firstMatch.sourcePdfPage}');
      },
    );

    testWidgets(
      '2. ReadingScreen mounts and displays OCR progress / controls',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final book = Book(
          id: 'book_ui_ocr_test',
          title: 'Laut Bercerita',
          author: 'Leila S. Chudori',
          originalPdfPath: lautPdf.path,
          totalPages: 379,
          isScanned: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              databaseServiceProvider.overrideWithValue(dbService),
            ],
            child: MaterialApp(
              home: ReadingScreen(
                book: book,
                initialMode: ReadingMode.originalPdf,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify that "Mulai OCR" button or Top App Bar is rendered
        expect(find.text('Laut Bercerita'), findsOneWidget);
        expect(find.text('Start OCR'), findsOneWidget);

        // Cleanly unmount to cancel periodic auto-save and auto-hide timers
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
      },
    );
  });
}
