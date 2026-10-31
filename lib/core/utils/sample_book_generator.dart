import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../features/processing/services/pdf_processing_pipeline.dart';
import '../database/app_database.dart';

class SampleBookGenerator {
  static Future<File> createSamplePdfFile(
    Directory dir, [
    String filename = 'sherlock_holmes_sample.pdf',
  ]) async {
    final samplePdfFile = File(p.join(dir.path, filename));

    final document = PdfDocument();
    document.documentInformation.title = 'The Adventures of Sherlock Holmes';
    document.documentInformation.author = 'Arthur Conan Doyle';
    document.documentInformation.subject = 'Classic Detective Mystery';

    final fontHeader = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
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
      'To Sherlock Holmes she is always THE woman. I have seldom heard him mention her under any other name. In his eyes she eclipses and predominates the whole of her sex. It was not that he felt any emotion akin to love for Irene Adler. All emotions, and that one particularly, were abhorrent to his cold, precise but admirably balanced mind.',
      fontBody,
      bounds: const Rect.fromLTWH(0, 40, 480, 600),
      brush: brush,
    );

    final pdfBytes = document.saveSync();
    document.dispose();

    await samplePdfFile.writeAsBytes(pdfBytes);
    return samplePdfFile;
  }

  static Future<Book> generateAndImportSampleBook(
    PdfProcessingPipeline pipeline,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final samplePdfFile = await createSamplePdfFile(tempDir);

    return pipeline.processAndImportPdf(
      pdfFile: samplePdfFile,
      customTitle: 'The Adventures of Sherlock Holmes',
      customAuthor: 'Arthur Conan Doyle',
    );
  }
}
