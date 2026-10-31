// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:ui' show Size;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_reference_holder.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';
import 'package:uuid/uuid.dart';

import '../models/extracted_page_geometry.dart';

/// Service responsible for Geometry-Aware PDF content and image extraction.
/// Preserves exact 2D bounding boxes, font attributes, image dimensions, and layer classifications.
class GeometryAwarePdfExtractor {
  /// Extracts geometry, text lines, and embedded images from a PDF file.
  static Future<DocumentExtractionResult> extractDocument({
    required File pdfFile,
    required String bookId,
    Directory? imageOutputDir,
    bool extractImagesToDisk = true,
    void Function(double progress, String status)? onProgress,
  }) async {
    final sw = Stopwatch()..start();
    final warnings = <String>[];

    if (!await pdfFile.exists()) {
      throw Exception('PDF file does not exist at: ${pdfFile.path}');
    }

    final bytes = await pdfFile.readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    final totalPages = doc.pages.count;
    final extractor = PdfTextExtractor(doc);

    // Prepare images output directory if extracting to disk
    Directory? bookImagesDir;
    if (extractImagesToDisk && imageOutputDir != null) {
      bookImagesDir = Directory(p.join(imageOutputDir.path, bookId));
      if (!await bookImagesDir.exists()) {
        await bookImagesDir.create(recursive: true);
      }
    }

    final List<ExtractedPageGeometry> extractedPages = [];
    final Map<PageLayerType, int> layerCounts = {
      PageLayerType.nativeText: 0,
      PageLayerType.scannedImage: 0,
      PageLayerType.hybrid: 0,
      PageLayerType.emptyOrUnsupported: 0,
    };

    int totalTextLinesCount = 0;
    int totalImagesCount = 0;

    for (int pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final pageNum = pageIdx + 1;
      onProgress?.call(
        pageIdx / (totalPages > 0 ? totalPages : 1),
        'Analyzing page $pageNum of $totalPages...',
      );

      final page = doc.pages[pageIdx];
      final pageSize = Size(page.size.width, page.size.height);

      // 1. Geometry-Aware Text Line Extraction
      final List<ExtractedTextLine> pageLines = [];
      int pageCharCount = 0;

      try {
        final rawLines = extractor.extractTextLines(
          startPageIndex: pageIdx,
          endPageIndex: pageIdx,
        );

        for (int lineIdx = 0; lineIdx < rawLines.length; lineIdx++) {
          final rl = rawLines[lineIdx];
          final text = rl.text.trim();
          if (text.isEmpty) continue;

          final words = rl.wordCollection.map((w) {
            return ExtractedTextWord(bounds: w.bounds, text: w.text);
          }).toList();

          pageLines.add(
            ExtractedTextLine(
              bounds: rl.bounds,
              text: text,
              fontSize: rl.fontSize,
              fontStyle: List.from(rl.fontStyle),
              fontName: rl.fontName,
              words: words,
              lineIndex: lineIdx,
              pageIndex: pageIdx,
            ),
          );
          pageCharCount += text.length;
        }
      } catch (e) {
        warnings.add('Failed to extract text lines from Page $pageNum: $e');
      }

      totalTextLinesCount += pageLines.length;

      // 2. Embedded Image Asset Extraction from /Resources /XObject
      final List<ExtractedImage> pageImages = [];
      try {
        final images = await _extractImagesFromPage(
          page: page,
          pageNumber: pageIdx,
          bookId: bookId,
          targetDirectory: bookImagesDir,
        );
        pageImages.addAll(images);
        totalImagesCount += images.length;
      } catch (e) {
        warnings.add('Failed to extract images from Page $pageNum: $e');
      }

      // 3. Page-Level Text Layer Classification
      final PageLayerType pageLayer;
      final bool hasText = pageLines.isNotEmpty && pageCharCount > 15;
      final bool hasImages = pageImages.isNotEmpty;

      if (hasText && !hasImages) {
        pageLayer = PageLayerType.nativeText;
      } else if (!hasText && hasImages) {
        pageLayer = PageLayerType.scannedImage;
      } else if (hasText && hasImages) {
        pageLayer = PageLayerType.hybrid;
      } else {
        pageLayer = PageLayerType.emptyOrUnsupported;
      }

      layerCounts[pageLayer] = (layerCounts[pageLayer] ?? 0) + 1;

      extractedPages.add(
        ExtractedPageGeometry(
          pageIndex: pageIdx,
          pageSize: pageSize,
          lines: pageLines,
          images: pageImages,
          layerType: pageLayer,
          charCount: pageCharCount,
        ),
      );
    }

    doc.dispose();
    sw.stop();

    final nativeOrHybridPages =
        (layerCounts[PageLayerType.nativeText] ?? 0) +
        (layerCounts[PageLayerType.hybrid] ?? 0);
    final hasUsableTextLayer =
        totalPages > 0 && (nativeOrHybridPages / totalPages) >= 0.5;

    return DocumentExtractionResult(
      bookId: bookId,
      totalPages: totalPages,
      pages: extractedPages,
      totalTextLines: totalTextLinesCount,
      totalImages: totalImagesCount,
      layerBreakdown: layerCounts,
      hasUsableTextLayer: hasUsableTextLayer,
      warnings: warnings,
      durationMs: sw.elapsedMicroseconds / 1000.0,
    );
  }

  /// Inspects page dictionary and extracts embedded XObject images safely to disk.
  static Future<List<ExtractedImage>> _extractImagesFromPage({
    required PdfPage page,
    required int pageNumber,
    required String bookId,
    Directory? targetDirectory,
  }) async {
    final List<ExtractedImage> images = [];
    final pageHelper = PdfPageHelper.getHelper(page);
    final dict = pageHelper.dictionary;
    if (dict == null) return images;

    final resObj = dict.getValue('Resources', 'parent');
    PdfDictionary? resDict;
    if (resObj is PdfDictionary) resDict = resObj;
    if (resObj is PdfReferenceHolder && resObj.object is PdfDictionary) {
      resDict = resObj.object as PdfDictionary;
    }
    if (resDict == null) return images;

    final xobjObj = resDict.getValue('XObject', 'parent');
    PdfDictionary? xobjDict;
    if (xobjObj is PdfDictionary) xobjDict = xobjObj;
    if (xobjObj is PdfReferenceHolder && xobjObj.object is PdfDictionary) {
      xobjDict = xobjObj.object as PdfDictionary;
    }
    if (xobjDict == null || xobjDict.items == null) return images;

    for (final entry in xobjDict.items!.entries) {
      final imageName = entry.key?.name ?? 'image';
      var item = entry.value;
      if (item is PdfReferenceHolder) item = item.object;

      if (item is PdfStream) {
        final subtype = item.getValue('Subtype', 'parent');
        final subtypeName = subtype is PdfName
            ? subtype.name
            : subtype.toString();
        if (subtypeName != 'Image') continue;

        final widthObj = item.getValue('Width', 'parent');
        final heightObj = item.getValue('Height', 'parent');
        final width =
            (widthObj is PdfNumber ? widthObj.value : 0.0)?.toDouble() ?? 0.0;
        final height =
            (heightObj is PdfNumber ? heightObj.value : 0.0)?.toDouble() ?? 0.0;
        final aspectRatio = height > 0 ? (width / height) : 1.0;

        final filterObj = item.getValue('Filter', 'parent');
        final filterName = filterObj is PdfName
            ? filterObj.name
            : filterObj.toString();

        final streamBytes = item.dataStream;
        final bytesLen = streamBytes?.length ?? 0;
        String? savedImagePath;

        // Save JPEG images (DCTDecode) directly without transcoding
        if (targetDirectory != null &&
            streamBytes != null &&
            streamBytes.isNotEmpty &&
            filterName == 'DCTDecode') {
          try {
            final fileName =
                'p${pageNumber}_${imageName}_${width.toInt()}x${height.toInt()}.jpg';
            final outFile = File(p.join(targetDirectory.path, fileName));
            await outFile.writeAsBytes(streamBytes, flush: true);
            savedImagePath = outFile.path;
          } catch (_) {}
        }

        images.add(
          ExtractedImage(
            id: const Uuid().v4(),
            name: imageName,
            sourcePage: pageNumber,
            dimensions: Size(width, height),
            aspectRatio: aspectRatio,
            filter: filterName ?? 'Unknown',
            imagePath: savedImagePath,
            bytesLength: bytesLen,
            isCover: pageNumber == 0,
          ),
        );
      }
    }

    return images;
  }
}
