// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable_book_reader.dart';
import 'helpers/real_book_fixtures.dart';
import 'helpers/test_evidence_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ocrService = AppleVisionOcrService();
  late Directory tempDir;
  final visualEvidenceDir = resolveTestEvidenceDir('phase_3_1_1');

  final lautBerceritaPath =
      p.join(RealBookFixtures.downloadsDir, 'Laut Bercerita (Leila S. Chudori).pdf');
  final bicaraSeninyaPath =
      p.join(RealBookFixtures.downloadsDir, 'Bicara Itu Ada Seninya (Oh Su Hyang).pdf');
  final mrXPath =
      p.join(RealBookFixtures.downloadsDir, 'Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf');

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('db_visual_acceptance_test_');
    Directory(visualEvidenceDir).createSync(recursive: true);
    await ocrService.ensureBinaryAvailable();
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> renderAndSaveScanPage({
    required String pdfPath,
    required int pageIndex,
    required String outputPath,
  }) async {
    final pdfDoc = await PdfDocument.openFile(pdfPath);
    final page = pdfDoc.pages[pageIndex];
    final img = await page.render(
      width: (page.width * 1.5).round(),
      height: (page.height * 1.5).round(),
    );
    final uiImg = await img?.createImage();
    final byteData = await uiImg?.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      File(outputPath).writeAsBytesSync(byteData.buffer.asUint8List());
    }
    await pdfDoc.dispose();
  }

  Future<BookDocument> ocrAndReconstructPage({
    required String pdfPath,
    required int pageIndex,
    required String title,
    required String author,
  }) async {
    final pdfDoc = await PdfDocument.openFile(pdfPath);
    final page = pdfDoc.pages[pageIndex];
    final img = await page.render(
      width: (page.width * 2.0).round(),
      height: (page.height * 2.0).round(),
    );
    final uiImg = await img?.createImage();
    final byteData = await uiImg?.toByteData(format: ui.ImageByteFormat.png);
    final tempImgPath = p.join(tempDir.path, 'temp_ocr_$pageIndex.png');
    File(tempImgPath).writeAsBytesSync(byteData!.buffer.asUint8List());

    final ocrResult = await ocrService.processImage(tempImgPath);
    final geom = ocrResult.toExtractedPageGeometry(
      pageIndex: pageIndex,
      pageSize: Size(page.width, page.height),
    );

    final extraction = DocumentExtractionResult(
      bookId: 'doc-$pageIndex',
      totalPages: 1,
      pages: [geom],
      totalTextLines: geom.lines.length,
      totalImages: 0,
      layerBreakdown: const {PageLayerType.nativeText: 1},
      hasUsableTextLayer: true,
      warnings: const [],
      durationMs: ocrResult.durationMs,
    );

    final reconstructed = await SemanticDocumentReconstructor.reconstruct(
      extraction: extraction,
      title: title,
      author: author,
    );

    await pdfDoc.dispose();
    if (File(tempImgPath).existsSync()) {
      File(tempImgPath).deleteSync();
    }

    return reconstructed.toBookDocument();
  }

  testWidgets(
    '1. Capture Visual Comparison: Laut Bercerita Page 15 (Scan vs Reflowable)',
    (tester) async {
      if (!checkFixtureOrSkip(lautBerceritaPath)) return;
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Render and save raw scanned page
      final scanOut = '$visualEvidenceDir/laut_bercerita_p15_scan.png';
      await tester.runAsync(() async {
        await renderAndSaveScanPage(
          pdfPath: lautBerceritaPath,
          pageIndex: 14,
          outputPath: scanOut,
        );
      });
      expect(File(scanOut).existsSync(), isTrue);

      // 2. OCR and reconstruct
      late BookDocument doc;
      await tester.runAsync(() async {
        doc = await ocrAndReconstructPage(
          pdfPath: lautBerceritaPath,
          pageIndex: 14,
          title: 'Laut Bercerita',
          author: 'Leila S. Chudori',
        );
      });

      // 3. Render ReflowableBookReader in warm paper theme
      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: ReflowableBookReader(
                document: doc,
                theme: ReadingThemeType.warmPaper,
                typography: const TypographySettings(
                  fontSize: 18.0,
                  lineSpacing: 1.6,
                  paragraphSpacing: 14.0,
                ),
                initialChapterIndex: 0,
                initialPosition: 1,
                onProgressChanged: (ch, p, pct) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 4. Capture native screenshot
      await tester.runAsync(() async {
        final boundary =
            repaintKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            File(
              '$visualEvidenceDir/laut_bercerita_p15_reflowable.png',
            ).writeAsBytesSync(bytes.buffer.asUint8List());
          }
        }
      });

      expect(
        File(
          '$visualEvidenceDir/laut_bercerita_p15_reflowable.png',
        ).existsSync(),
        isTrue,
      );
    },
  );

  testWidgets(
    '2. Capture Visual Comparison: Bicara Itu Ada Seninya Page 33 (Scan vs Reflowable)',
    (tester) async {
      if (!checkFixtureOrSkip(bicaraSeninyaPath)) return;
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Render and save raw scanned page
      final scanOut = '$visualEvidenceDir/bicara_seninya_p33_scan.png';
      await tester.runAsync(() async {
        await renderAndSaveScanPage(
          pdfPath: bicaraSeninyaPath,
          pageIndex: 32,
          outputPath: scanOut,
        );
      });
      expect(File(scanOut).existsSync(), isTrue);

      // 2. OCR and reconstruct
      late BookDocument doc;
      await tester.runAsync(() async {
        doc = await ocrAndReconstructPage(
          pdfPath: bicaraSeninyaPath,
          pageIndex: 32,
          title: 'Bicara Itu Ada Seninya',
          author: 'Oh Su Hyang',
        );
      });

      // 3. Render ReflowableBookReader in default light theme
      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: ReflowableBookReader(
                document: doc,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(
                  fontSize: 18.0,
                  lineSpacing: 1.6,
                  paragraphSpacing: 14.0,
                ),
                initialChapterIndex: 0,
                initialPosition: 1,
                onProgressChanged: (ch, p, pct) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 4. Capture native screenshot
      await tester.runAsync(() async {
        final boundary =
            repaintKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            File(
              '$visualEvidenceDir/bicara_seninya_p33_reflowable.png',
            ).writeAsBytesSync(bytes.buffer.asUint8List());
          }
        }
      });

      expect(
        File(
          '$visualEvidenceDir/bicara_seninya_p33_reflowable.png',
        ).existsSync(),
        isTrue,
      );
    },
  );

  testWidgets(
    '3. Capture Visual: The Devotion of Suspect X Page 11 Narrative Reflowable',
    (tester) async {
      if (!checkFixtureOrSkip(mrXPath)) return;
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late BookDocument doc;
      await tester.runAsync(() async {
        doc = await ocrAndReconstructPage(
          pdfPath: mrXPath,
          pageIndex: 10,
          title: 'Kesetiaan Mr. X',
          author: 'Keigo Higashino',
        );
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: ReflowableBookReader(
                document: doc,
                theme: ReadingThemeType.warmPaper,
                typography: const TypographySettings(
                  fontSize: 18.0,
                  lineSpacing: 1.6,
                  paragraphSpacing: 14.0,
                ),
                initialChapterIndex: 0,
                initialPosition: 1,
                onProgressChanged: (ch, p, pct) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary =
            repaintKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            File(
              '$visualEvidenceDir/suspect_x_p11_reflowable.png',
            ).writeAsBytesSync(bytes.buffer.asUint8List());
          }
        }
      });

      expect(
        File('$visualEvidenceDir/suspect_x_p11_reflowable.png').existsSync(),
        isTrue,
      );
    },
  );
}
