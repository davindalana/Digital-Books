import 'dart:convert';
import 'dart:io';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/utils/sample_book_generator.dart';
import 'package:digital_books/features/processing/models/ocr_quality.dart';
import 'package:digital_books/features/processing/services/ocr_quality_gate.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  OcrPage ocrPage({
    required int index,
    required String status,
    double confidence = 0.95,
    int charCount = 600,
  }) => OcrPage(
    id: 'ocr-$index',
    bookId: 'book-1',
    pageIndex: index,
    status: status,
    confidence: confidence,
    charCount: charCount,
    durationMs: 120,
    linesJson: '[]',
    createdAt: DateTime.now(),
  );

  group('OCR quality gate', () {
    test('native text layer does not require OCR', () {
      final result = OcrQualityGate.assess(
        totalPages: 100,
        pages: const [],
        hasSelectableTextLayer: true,
        isScannedSource: false,
      );

      expect(result.readiness, OcrReadiness.notRequired);
      expect(result.isReliableForBookMode, isTrue);
    });

    test('hybrid documents keep native text while OCR is still pending', () {
      final result = OcrQualityGate.assess(
        totalPages: 100,
        pages: [
          ocrPage(index: 0, status: 'completed'),
          ocrPage(index: 1, status: 'pending', charCount: 0),
        ],
        hasSelectableTextLayer: true,
        isScannedSource: false,
      );

      expect(result.readiness, OcrReadiness.notRequired);
      expect(result.isReliableForBookMode, isTrue);
      expect(result.reasons.single, contains('optional'));
    });

    test('scanned document with no OCR pages is pending', () {
      final result = OcrQualityGate.assess(
        totalPages: 10,
        pages: const [],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.pending);
      expect(result.isReliableForBookMode, isFalse);
    });

    test('scanned document with running OCR is in progress', () {
      final result = OcrQualityGate.assess(
        totalPages: 10,
        pages: [ocrPage(index: 0, status: 'processing', charCount: 0)],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.inProgress);
      expect(result.isReliableForBookMode, isFalse);
    });

    test('a failed page blocks readiness even at high coverage', () {
      final result = OcrQualityGate.assess(
        totalPages: 100,
        pages: [
          for (var i = 0; i < 99; i++) ocrPage(index: i, status: 'completed'),
          ocrPage(index: 99, status: 'failed', charCount: 0),
        ],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.failed);
      expect(result.failedPages, 1);
      expect(result.isReliableForBookMode, isFalse);
      expect(result.reasons.first, contains('failed'));
    });

    test('incomplete coverage is not ready', () {
      final result = OcrQualityGate.assess(
        totalPages: 100,
        pages: [
          for (var i = 0; i < 80; i++) ocrPage(index: i, status: 'completed'),
          for (var i = 80; i < 100; i++)
            ocrPage(index: i, status: 'pending', charCount: 0),
        ],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.inProgress);
      expect(result.coverage, closeTo(0.8, 0.0001));
      expect(result.isReliableForBookMode, isFalse);
    });

    test('low confidence is insufficient quality', () {
      final result = OcrQualityGate.assess(
        totalPages: 10,
        pages: [
          for (var i = 0; i < 10; i++)
            ocrPage(index: i, status: 'completed', confidence: 0.55),
        ],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.insufficientQuality);
      expect(result.isReliableForBookMode, isFalse);
      expect(result.reasons.join(' '), contains('confidence'));
    });

    test('low text density is insufficient quality', () {
      final result = OcrQualityGate.assess(
        totalPages: 10,
        pages: [
          for (var i = 0; i < 10; i++)
            ocrPage(index: i, status: 'completed', charCount: 5),
        ],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.insufficientQuality);
      expect(result.reasons.join(' '), contains('characters'));
    });

    test('complete high-quality OCR is ready', () {
      final result = OcrQualityGate.assess(
        totalPages: 10,
        pages: [
          for (var i = 0; i < 10; i++) ocrPage(index: i, status: 'completed'),
        ],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );

      expect(result.readiness, OcrReadiness.ready);
      expect(result.isReliableForBookMode, isTrue);
      expect(result.coverage, 1.0);
      expect(result.averageConfidence, closeTo(0.95, 0.0001));
    });

    test('JSON metadata exposes every gate input', () {
      final result = OcrQualityGate.assess(
        totalPages: 10,
        pages: [ocrPage(index: 0, status: 'failed', charCount: 0)],
        hasSelectableTextLayer: false,
        isScannedSource: true,
      );
      final json = result.toJson();

      expect(json['readiness'], 'failed');
      expect(json['reliableForBookMode'], isFalse);
      expect(json['totalPages'], 10);
      expect(json['failedPages'], 1);
      expect(json['reasons'], isNotEmpty);
    });
  });

  group('OCR pipeline metadata wiring', () {
    late AppDatabase db;
    late DatabaseService dbService;
    late Directory tempDir;
    late File pdf;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dbService = DatabaseService(db);
      tempDir = await Directory.systemTemp.createTemp('phase38_ocr_');
      pdf = await SampleBookGenerator.createSamplePdfFile(tempDir);

      await dbService.insertBook(
        BooksCompanion(
          id: const Value('book-1'),
          title: const Value('Scanned Sample'),
          author: const Value('Tester'),
          originalPdfPath: Value(pdf.path),
          totalPages: const Value(1),
          isScanned: const Value(true),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> insertOcrLine(String text) {
      return dbService.insertOcrPage(
        OcrPagesCompanion(
          id: const Value('ocr-0'),
          bookId: const Value('book-1'),
          pageIndex: const Value(0),
          status: const Value('completed'),
          confidence: const Value(0.94),
          charCount: Value(text.length),
          durationMs: const Value(100),
          linesJson: Value(
            jsonEncode([
              {
                'text': text,
                'confidence': 0.94,
                'box': {'x': 0.1, 'y': 0.1, 'width': 0.8, 'height': 0.05},
              },
            ]),
          ),
          createdAt: Value(DateTime.now()),
        ),
      );
    }

    test('verified OCR produces a ready Book Mode derivative', () async {
      await insertOcrLine(
        'Bab satu dimulai dengan sebuah kalimat yang cukup panjang untuk '
        'memenuhi ambang kualitas teks hasil pemindaian dokumen ini.',
      );

      final doc = await OcrSemanticPipeline(
        dbService,
      ).reconstructDocument(bookId: 'book-1', pdfPath: pdf.path);

      expect(doc, isNotNull);
      expect(doc!.isScanned, isTrue);
      expect(doc.metadata['ocrReadiness'], 'ready');
      expect(doc.metadata['processingStatus'], isNot('requiresOcr'));
      final quality = doc.metadata['ocrQuality'] as Map<String, dynamic>;
      expect(quality['reliableForBookMode'], isTrue);
    });

    test('insufficient OCR is not advertised as verified Book Mode', () async {
      await insertOcrLine('Hi');

      final doc = await OcrSemanticPipeline(
        dbService,
      ).reconstructDocument(bookId: 'book-1', pdfPath: pdf.path);

      expect(doc, isNotNull);
      expect(doc!.metadata['ocrReadiness'], 'insufficientQuality');
      expect(doc.metadata['processingStatus'], 'requiresOcr');
      expect(
        (doc.metadata['processingReasons'] as List<dynamic>).join(' '),
        contains('characters'),
      );
    });
  });
}
