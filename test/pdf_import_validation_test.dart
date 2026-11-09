import 'dart:io';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/services/pdf_processing_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late DatabaseService dbService;
  late PdfProcessingPipeline pipeline;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_validation_test_');
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    pipeline = PdfProcessingPipeline(dbService);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rejects a non-PDF file before any database or file writes', () async {
    final file = File(p.join(tempDir.path, 'not-a-pdf.pdf'));
    await file.writeAsBytes(List<int>.filled(200, 65));

    await expectLater(
      pipeline.processAndImportPdf(pdfFile: file),
      throwsA(
        predicate(
          (e) => e.toString().contains('not a valid PDF'),
          'reports an invalid PDF format',
        ),
      ),
    );
    expect(await dbService.getAllBooks(), isEmpty);
  });

  test('reports a clear error for a corrupt PDF container', () async {
    final file = File(p.join(tempDir.path, 'corrupt.pdf'));
    await file.writeAsBytes(
      '%PDF-1.4\nthis is not a real pdf body and has no xref table\n'
              .codeUnits +
          List<int>.filled(80, 32),
    );

    await expectLater(
      pipeline.processAndImportPdf(pdfFile: file),
      throwsA(
        predicate((e) {
          final message = e.toString().toLowerCase();
          return message.contains('unable to open pdf') ||
              message.contains('has no pages');
        }, 'reports an unreadable or empty PDF'),
      ),
    );
    expect(await dbService.getAllBooks(), isEmpty);
  });
}
