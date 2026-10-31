// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/services/pdf_processing_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

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
  test('Direct test of PDF generation and processing pipeline', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = Directory.systemTemp.createTempSync('db_test');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);

    final samplePdfFile = File(p.join(tempDir.path, 'sample.pdf'));

    final document = PdfDocument();
    document.documentInformation.title = 'The Adventures of Sherlock Holmes';
    document.documentInformation.author = 'Arthur Conan Doyle';

    final fontHeader = PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
    final fontBody = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final brush = PdfSolidBrush(PdfColor(20, 20, 20));

    final page1 = document.pages.add();
    page1.graphics.drawString(
      'CHAPTER I. A SCANDAL IN BOHEMIA',
      fontHeader,
      bounds: const Rect.fromLTWH(0, 0, 480, 30),
      brush: brush,
    );
    page1.graphics.drawString(
      'To Sherlock Holmes she is always THE woman. I have seldom heard him mention her under any other name.',
      fontBody,
      bounds: const Rect.fromLTWH(0, 40, 480, 600),
      brush: brush,
    );

    final pdfBytes = document.saveSync();
    document.dispose();
    await samplePdfFile.writeAsBytes(pdfBytes);

    final db = AppDatabase(NativeDatabase.memory());
    final dbService = DatabaseService(db);
    final pipeline = PdfProcessingPipeline(dbService);

    final book = await pipeline.processAndImportPdf(
      pdfFile: samplePdfFile,
      onProgress: (p) => print('Progress: ${p.stage} - ${p.message}'),
    );

    expect(book.title, 'The Adventures of Sherlock Holmes');
    expect(book.totalPages, 1);
    expect(File(book.coverPath!).existsSync(), isTrue);
    expect(File(book.originalPdfPath).existsSync(), isTrue);
    expect(File(book.processedBookPath!).existsSync(), isTrue);

    await db.close();
  });
}
