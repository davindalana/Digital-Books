import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'helpers/corpus_pdf_generator.dart';

void main() {
  late Directory tempDir;
  late Directory corpusDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('db_extraction_test_');
    corpusDir = Directory('test/fixtures/corpus');
    if (!corpusDir.existsSync() || corpusDir.listSync().isEmpty) {
      await CorpusPdfGenerator.generateAllCorpusFiles(corpusDir);
    }
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 2.7 Geometry-Aware Extraction Suite', () {
    test(
      '1. Preserves exact line bounding boxes, X/Y coordinates and word details',
      () async {
        final pdfFile = File('${corpusDir.path}/01_single_column_novel.pdf');
        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_book_01',
          imageOutputDir: tempDir,
        );

        expect(result.totalPages, equals(1));
        expect(result.pages.length, equals(1));

        final page = result.pages.first;
        expect(page.pageSize.width, equals(595.0));
        expect(page.pageSize.height, equals(842.0));
        expect(page.lines.length, greaterThanOrEqualTo(4));

        for (final line in page.lines) {
          expect(line.bounds.width, greaterThan(0));
          expect(line.bounds.height, greaterThan(0));
          expect(line.bounds.left, greaterThanOrEqualTo(50.0));
          expect(line.bounds.top, greaterThanOrEqualTo(50.0));
          expect(line.words.isNotEmpty, isTrue);

          for (final word in line.words) {
            expect(word.bounds.width, greaterThan(0));
            expect(word.bounds.height, greaterThan(0));
            expect(word.text.isNotEmpty, isTrue);
          }
        }
      },
    );

    test(
      '2. Preserves font metrics: distinguishes 18pt bold heading from 11pt regular body',
      () async {
        final pdfFile = File('${corpusDir.path}/01_single_column_novel.pdf');
        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_book_01_fonts',
          imageOutputDir: tempDir,
        );

        final page = result.pages.first;
        final headingLine = page.lines.firstWhere(
          (l) => l.text.contains('Chapter 1'),
        );
        final bodyLine = page.lines.firstWhere(
          (l) => l.text.contains('dark and stormy'),
        );

        expect(headingLine.fontSize, equals(18.0));
        expect(headingLine.isBold, isTrue);

        expect(bodyLine.fontSize, equals(11.0));
        expect(bodyLine.isBold, isFalse);
      },
    );

    test(
      '3. Extracts embedded images to disk with dimensions, aspect ratio and filter',
      () async {
        final pdfFile = File('${corpusDir.path}/02_illustrated_novel.pdf');
        final imagesDir = Directory('${tempDir.path}/images_illustrated');
        await imagesDir.create(recursive: true);

        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_book_02_img',
          imageOutputDir: imagesDir,
        );

        final page = result.pages.first;
        expect(page.images.length, equals(1));

        final img = page.images.first;
        expect(img.filter, equals('DCTDecode'));
        expect(img.dimensions.width, greaterThan(0));
        expect(img.dimensions.height, greaterThan(0));
        expect(img.aspectRatio, greaterThan(0));

        expect(img.imagePath, isNotNull);
        final savedFile = File(img.imagePath!);
        expect(savedFile.existsSync(), isTrue);
        expect(savedFile.lengthSync(), greaterThan(50));
      },
    );

    test(
      '4. Correctly classifies page layer as nativeText, scannedImage, hybrid, or empty',
      () async {
        // Single-column: pure text
        final resText = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: File('${corpusDir.path}/01_single_column_novel.pdf'),
          bookId: 'test_layer_text',
          imageOutputDir: tempDir,
        );
        expect(resText.pages.first.layerType, equals(PageLayerType.nativeText));
        expect(resText.hasUsableTextLayer, isTrue);

        // Scanned image only: 0 text chars
        final resScan = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: File('${corpusDir.path}/08_scanned_image_only.pdf'),
          bookId: 'test_layer_scan',
          imageOutputDir: tempDir,
        );
        expect(
          resScan.pages.first.layerType,
          equals(PageLayerType.scannedImage),
        );
        expect(resScan.hasUsableTextLayer, isFalse);
        expect(resScan.recommendedReaderTier, contains('Original PDF Reader'));

        // Illustrated: hybrid
        final resHybrid = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: File('${corpusDir.path}/02_illustrated_novel.pdf'),
          bookId: 'test_layer_hybrid',
          imageOutputDir: tempDir,
        );
        expect(resHybrid.pages.first.layerType, equals(PageLayerType.hybrid));
        expect(resHybrid.hasUsableTextLayer, isTrue);
      },
    );

    test(
      '5. Multi-page document correctly tracks heterogeneous page layers across pages',
      () async {
        final pdfFile = File('${corpusDir.path}/09_hybrid_mixed.pdf');
        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_heterogeneous_layers',
          imageOutputDir: tempDir,
        );

        expect(result.totalPages, equals(3));
        expect(result.pages[0].layerType, equals(PageLayerType.nativeText));
        expect(result.pages[1].layerType, equals(PageLayerType.scannedImage));
        expect(result.pages[2].layerType, equals(PageLayerType.hybrid));

        expect(result.layerBreakdown[PageLayerType.nativeText], equals(1));
        expect(result.layerBreakdown[PageLayerType.scannedImage], equals(1));
        expect(result.layerBreakdown[PageLayerType.hybrid], equals(1));
      },
    );

    test(
      '6. Multi-column academic document retains separate text line coordinates without flattening',
      () async {
        final pdfFile = File('${corpusDir.path}/04_two_column_academic.pdf');
        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_two_column_geo',
          imageOutputDir: tempDir,
        );

        final page = result.pages.first;
        // Filter body lines (excluding title)
        final bodyLines = page.lines
            .where((l) => !l.text.contains('Comparative Study'))
            .toList();
        final leftLines = bodyLines.where((l) => l.bounds.left < 200).toList();
        final rightLines = bodyLines.where((l) => l.bounds.left > 300).toList();

        expect(leftLines.isNotEmpty, isTrue);
        expect(rightLines.isNotEmpty, isTrue);

        // Verify that left column lines stay within the left column boundary
        for (final l in leftLines) {
          expect(l.bounds.right, lessThanOrEqualTo(320.0));
        }
        for (final r in rightLines) {
          expect(r.bounds.left, greaterThanOrEqualTo(340.0));
        }
      },
    );

    test(
      '7. Header and footer line coordinates are accurately measured for filtering',
      () async {
        final pdfFile = File('${corpusDir.path}/05_headers_footers.pdf');
        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_headers_footers_geo',
          imageOutputDir: tempDir,
        );

        for (final page in result.pages) {
          final topHeaders = page.lines
              .where((l) => l.bounds.top < 80.0)
              .toList();
          final bottomFooters = page.lines
              .where((l) => l.bounds.top > 800.0)
              .toList();

          expect(topHeaders.isNotEmpty, isTrue);
          expect(topHeaders.first.text, contains('SHERLOCK HOLMES'));

          expect(bottomFooters.isNotEmpty, isTrue);
          expect(bottomFooters.first.text, contains('Page'));
        }
      },
    );

    test('8. Non-existent file throws clear exception', () async {
      expect(
        () => GeometryAwarePdfExtractor.extractDocument(
          pdfFile: File('/nonexistent/sample.pdf'),
          bookId: 'test_missing',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      '9. Diagnostic serialization produces valid structured JSON',
      () async {
        final pdfFile = File('${corpusDir.path}/03_diagrams_maps.pdf');
        final result = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: pdfFile,
          bookId: 'test_json_diag',
          imageOutputDir: tempDir,
        );

        final jsonMap = result.toJson();
        expect(jsonMap['bookId'], equals('test_json_diag'));
        expect(jsonMap['totalPages'], equals(1));
        expect(jsonMap['totalImages'], equals(1));
        expect(jsonMap['hasUsableTextLayer'], isTrue);
        expect(jsonMap['pages'], isA<List>());
      },
    );
  });
}
