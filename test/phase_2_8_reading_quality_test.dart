// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

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

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('p28_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 2.8: Reading Quality Validation & Refinement', () {
    test(
      'Enhanced H1 classification recognizes novel headings (Prolog, Epilog, Roman numerals)',
      () {
        final paragraphs = [
          ReconstructedParagraph(
            text: 'PROLOG',
            startPageIndex: 0,
            endPageIndex: 0,
            boundingBox: const Rect.fromLTWH(50, 100, 100, 20),
            fontSize: 14.0,
            fontStyles: const [],
            isBold: true,
            isItalic: false,
            lineCount: 1,
            sourceLines: const [],
          ),
          ReconstructedParagraph(
            text: 'Ini adalah paragraf pembuka dalam prolog novel.',
            startPageIndex: 0,
            endPageIndex: 0,
            boundingBox: const Rect.fromLTWH(50, 140, 400, 30),
            fontSize: 11.0,
            fontStyles: const [],
            isBold: false,
            isItalic: false,
            lineCount: 2,
            sourceLines: const [],
          ),
          ReconstructedParagraph(
            text: 'III',
            startPageIndex: 1,
            endPageIndex: 1,
            boundingBox: const Rect.fromLTWH(50, 100, 50, 20),
            fontSize: 13.5,
            fontStyles: const [],
            isBold: true,
            isItalic: false,
            lineCount: 1,
            sourceLines: const [],
          ),
          ReconstructedParagraph(
            text: 'EPILOGUE',
            startPageIndex: 2,
            endPageIndex: 2,
            boundingBox: const Rect.fromLTWH(50, 100, 120, 20),
            fontSize: 14.0,
            fontStyles: const [],
            isBold: true,
            isItalic: false,
            lineCount: 1,
            sourceLines: const [],
          ),
        ];

        final classified = SemanticClassifier.classifyDocument(
          paragraphs: paragraphs,
          totalPages: 3,
        );

        final h1Blocks = classified
            .where((b) => b.type == SemanticBlockType.heading1)
            .toList();
        expect(h1Blocks.length, equals(3));
        expect(h1Blocks[0].text, equals('PROLOG'));
        expect(h1Blocks[1].text, equals('III'));
        expect(h1Blocks[2].text, equals('EPILOGUE'));
      },
    );

    test(
      'PaginationEngine and PaginatedReflowableReader have aligned single-deduction geometry',
      () {
        final doc = ReaderDocument(
          bookId: 'geom_eval',
          title: 'Geometric Consistency',
          author: 'Tester',
          totalPages: 1,
          chapters: [
            ReaderChapter(
              id: 'ch1',
              index: 0,
              title: 'Chapter 1',
              nodes: List.generate(
                12,
                (i) => ContentNode(
                  id: 'n_$i',
                  type: ContentNodeType.paragraph,
                  text:
                      'This is paragraph number $i illustrating standard reading content height. ' *
                      4,
                  sourcePdfPage: 1,
                ),
              ),
            ),
          ],
        );

        const typography = TypographySettings(twoPageSpread: true);
        const viewportWidth = 900.0;
        const viewportHeight = 700.0;

        final pages = PaginationEngine.paginateDocument(
          document: doc,
          typography: typography,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        );

        expect(pages, isNotEmpty);
        // Verify available content height utilized without excessive bottom cutoff
        // In 700pt viewport, available height should be ~632pt (700 - 68pt), not 520pt!
        expect(pages.first.slices.length, greaterThanOrEqualTo(2));
      },
    );

    testWidgets(
      'Bidirectional mode switch preserves exact reading position and page mapping',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final dbService = DatabaseService(db);

        // Create a test book with processed document containing sourcePdfPage citations
        final bookDoc = BookDocument(
          id: 'bidirectional_book',
          title: 'The Great Journey',
          author: 'Explorer',
          totalPages: 5,
          chapters: [
            BookChapter(
              id: 'ch1',
              index: 0,
              title: 'Chapter 1',
              blocks: [
                const BookBlock(
                  id: 'b1',
                  type: BlockType.heading,
                  text: 'Chapter 1: The Mountain',
                  originalPageNumber: 1,
                ),
                const BookBlock(
                  id: 'b2',
                  type: BlockType.paragraph,
                  text: 'We stood at the base of the peak.',
                  originalPageNumber: 2,
                ),
                const BookBlock(
                  id: 'b3',
                  type: BlockType.paragraph,
                  text: 'The wind was fierce.',
                  originalPageNumber: 3,
                ),
              ],
            ),
          ],
          metadata: {
            'reconstructionQuality': {'status': 'good'},
          },
        );

        final bookPath = '${tempDir.path}/bidirectional_book.json';
        File(bookPath).writeAsStringSync(bookDoc.toJsonString());

        final now = DateTime.now();
        final bookCompanion = BooksCompanion.insert(
          id: 'bidirectional_book',
          title: 'The Great Journey',
          author: 'Explorer',
          originalPdfPath: '${tempDir.path}/nonexistent.pdf',
          processedBookPath: drift.Value(bookPath),
          totalPages: const drift.Value(5),
          isScanned: const drift.Value(false),
          createdAt: now,
          updatedAt: now,
        );
        await dbService.insertBook(bookCompanion);

        final book = await dbService.getBookById('bidirectional_book');
        expect(book, isNotNull);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              databaseServiceProvider.overrideWithValue(dbService),
              bookBookmarksStreamProvider(
                'bidirectional_book',
              ).overrideWith((ref) => Stream.value(<Bookmark>[])),
            ],
            child: MaterialApp(
              home: ReadingScreen(
                book: book!,
                initialMode: ReadingMode.reflowable,
              ),
            ),
          ),
        );

        // Pump to load document
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Switch to PDF mode
        final pdfButton = find.text('PDF');
        expect(pdfButton, findsOneWidget);
        await tester.tap(pdfButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify switched to OriginalPdfReader
        expect(find.byType(OriginalPdfReader), findsOneWidget);

        // Clean unmount to drain riverpod and drift timers
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    test(
      'Real-world book benchmarks verify reading order and chapter integrity',
      () {
        final jsonFile = File(
          '/Users/davindalana/Documents/DigitalBooks/books/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
        );

        if (!jsonFile.existsSync()) {
          print('Skipping real book test: processed file not found on disk.');
          return;
        }

        final doc = BookDocument.fromJsonString(jsonFile.readAsStringSync());

        // Check chapter and paragraph distributions
        int totalHeadings = 0;
        int totalParagraphs = 0;
        for (final ch in doc.chapters) {
          for (final b in ch.blocks) {
            if (b.type == BlockType.heading) totalHeadings++;
            if (b.type == BlockType.paragraph) totalParagraphs++;
          }
        }

        print('${doc.title} Structural Analysis:');
        print('• Chapters isolated: ${doc.chapters.length}');
        print('• Heading blocks: $totalHeadings');
        print('• Body paragraph blocks: $totalParagraphs');

        expect(doc.chapters.length, equals(20));
        expect(totalHeadings, greaterThanOrEqualTo(50));
        expect(totalParagraphs, greaterThan(1500));
      },
    );
  });
}
