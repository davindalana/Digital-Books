// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' show Rect;
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/utils/file_storage_service.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/background_ocr_queue.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/reader/models/book_document.dart';

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
    '/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf',
  );

  setUp(() async {
    tempAppDir = Directory.systemTemp.createTempSync('digital_books_ocr_test_');
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

    // Seed test book in DB
    await dbService.insertBook(
      BooksCompanion(
        id: const Value('book_semantic_test'),
        title: const Value('Laut Bercerita'),
        author: const Value('Leila S. Chudori'),
        originalPdfPath: Value(lautPdf.path),
        totalPages: const Value(379),
        isScanned: const Value(true),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    queue.dispose();
    await db.close();
    try {
      tempAppDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group(
    'Phase 3.1 Checkpoint D: OCR Semantic Pipeline & BookDocument Reconstruction',
    () {
      test(
        'Processes pages 14-16, synthesizes BookDocument, and updates DB & disk',
        () async {
          expect(lautPdf.existsSync(), isTrue);

          // 1. Run queue on pages 14, 15, 16 with autoReconstruct = true
          await queue.start(
            bookId: 'book_semantic_test',
            pdfPath: lautPdf.path,
            startPage: 14,
            endPage: 16,
            autoReconstruct: true,
          );

          print('DEBUG: Queue status: ${queue.state.status}');
          if (queue.state.errorMessage != null) {
            print('DEBUG: Queue error: ${queue.state.errorMessage}');
          }

          // 2. Verify book in DB now has processedBookPath
          final updatedBook = await dbService.getBookById('book_semantic_test');
          expect(updatedBook, isNotNull);
          expect(updatedBook!.processedBookPath, isNotNull);
          final jsonPath = updatedBook.processedBookPath!;
          expect(File(jsonPath).existsSync(), isTrue);

          // 3. Read and deserialize BookDocument from disk
          final jsonContent = await FileStorageService.readProcessedBook(
            jsonPath,
          );
          expect(jsonContent, isNotNull);
          final bookDoc = BookDocument.fromJsonString(jsonContent!);

          // 4. Verify semantic structure
          expect(bookDoc.title, equals('Laut Bercerita'));
          expect(bookDoc.author, equals('Leila S. Chudori'));
          expect(bookDoc.chapters.isNotEmpty, isTrue);

          // Total blocks across all chapters
          final allBlocks = bookDoc.chapters.expand((c) => c.blocks).toList();
          expect(allBlocks.isNotEmpty, isTrue);

          // Check original page number bindings (should be 15, 16, or 17)
          final pageNumbers = allBlocks
              .map((b) => b.originalPageNumber)
              .toSet();
          expect(pageNumbers.any((p) => p == 15), isTrue);

          // Check text content quality: should have real Indonesian words
          final fullText = allBlocks.map((b) => b.text).join(' ');
          expect(fullText, contains('mobil'));
          expect(fullText, contains('kami'));

          // Check chapter persistence in DB
          final dbChapters = await dbService.getChaptersForBook(
            'book_semantic_test',
          );
          expect(dbChapters.isNotEmpty, isTrue);
          expect(dbChapters.first.title, isNotEmpty);

          // 5. Verify provenance metadata
          expect(bookDoc.metadata['ocrSource'], equals('apple_vision_offline'));
          expect(bookDoc.metadata['ocrCompletedPages'], equals(3));
          expect(bookDoc.metadata.containsKey('reconstructionQuality'), isTrue);

          print(
            '\n===============================================================',
          );
          print('CHECKPOINT D: SEMANTIC BOOK RECONSTRUCTION AUDIT');
          print(
            '===============================================================',
          );
          print('Chapters created: ${bookDoc.chapters.length}');
          print('Total semantic blocks: ${allBlocks.length}');
          print('Original page anchors: $pageNumbers');
          print(
            'Saved JSON path: $jsonPath (${File(jsonPath).lengthSync()} bytes)',
          );
          print(
            'First block sample: "${allBlocks.first.text.substring(0, allBlocks.first.text.length.clamp(0, 80))}..."',
          );
        },
      );

      test(
        'Strict Indonesian Preposition vs Passive Prefix and Morphology Normalization',
        () {
          // 1. Passive prefix: di + verb -> ditutup, ditendang, didorong, dibaca, ditulis
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Pintu itu di tutup rapat.'),
            equals('Pintu itu ditutup rapat.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Aku di tendang ke depan.'),
            equals('Aku ditendang ke depan.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Buku ini di baca banyak orang.'),
            equals('Buku ini dibaca banyak orang.'),
          );

          // 2. Preposition complements: MUST NEVER BE JOINED
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Kami tinggal di rumah itu.'),
            equals('Kami tinggal di rumah itu.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Di manakah aku berada?'),
            equals('Di manakah aku berada?'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Kami berada di atas mobil.'),
            equals('Kami berada di atas mobil.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Buku disimpan di dalam lemari.'),
            equals('Buku disimpan di dalam lemari.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Dia sedang bekerja di kantor.'),
            equals('Dia sedang bekerja di kantor.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Mereka pergi ke sekolah.'),
            equals('Mereka pergi ke sekolah.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Ke manakah engkau akan pergi?'),
            equals('Ke manakah engkau akan pergi?'),
          );

          // 3. Stray hyphens and spaces on prepositional complements
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Berada di- rumah kakek.'),
            equals('Berada di rumah kakek.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Menuju ke- sekolah baru.'),
            equals('Menuju ke sekolah baru.'),
          );

          // 4. Stray hyphens and spaces on genuine affixes
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Sebuah peng- alaman membaca.'),
            equals('Sebuah pengalaman membaca.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Membeli se- buah buku.'),
            equals('Membeli sebuah buku.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Hari ke- dua pekan ini.'),
            equals('Hari kedua pekan ini.'),
          );

          // 5. Reduplication preservation
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Anak- anak bermain di taman.'),
            equals('Anak-anak bermain di taman.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Tiba- tiba terdengar suara.'),
            equals('Tiba-tiba terdengar suara.'),
          );
          expect(
            ReconstructedParagraphBuilder.cleanOcrText('Untuk mengira- ngira lokasi.'),
            equals('Untuk mengira-ngira lokasi.'),
          );

          // 6. Cross-line dehyphenation preserving prepositions vs joining verbs
          const prepLine1 = ExtractedTextLine(
            text: 'Ia sedang berada di-',
            bounds: Rect.fromLTWH(50, 100, 200, 14),
            lineIndex: 0,
            pageIndex: 0,
            fontSize: 12,
          );
          const prepLine2 = ExtractedTextLine(
            text: 'rumah paman.',
            bounds: Rect.fromLTWH(50, 120, 150, 14),
            lineIndex: 1,
            pageIndex: 0,
            fontSize: 12,
          );

          final prepBuilder = ReconstructedParagraphBuilder(prepLine1);
          prepBuilder.appendLine(prepLine2);
          final prepParagraph = prepBuilder.build();
          expect(prepParagraph.text, equals('Ia sedang berada di rumah paman.'));
          expect(prepParagraph.text.contains('dirumah'), isFalse);

          // And cross-line verb joining:
          const verbLine1 = ExtractedTextLine(
            text: 'Pintu itu di-',
            bounds: Rect.fromLTWH(50, 100, 150, 14),
            lineIndex: 0,
            pageIndex: 0,
            fontSize: 12,
          );
          const verbLine2 = ExtractedTextLine(
            text: 'tutup oleh penjaga.',
            bounds: Rect.fromLTWH(50, 120, 180, 14),
            lineIndex: 1,
            pageIndex: 0,
            fontSize: 12,
          );

          final verbBuilder = ReconstructedParagraphBuilder(verbLine1);
          verbBuilder.appendLine(verbLine2);
          final verbParagraph = verbBuilder.build();
          expect(verbParagraph.text, equals('Pintu itu ditutup oleh penjaga.'));
        },
      );
    },
  );
}
