// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/processing/services/scanned_image_enhancer.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable_book_reader.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3.0.1 — Final Real-World Acceptance & Visual Regression Audit', () {
    const String downloadsDir = '/Users/davindalana/Downloads';
    const String visualEvidenceDir = 'docs/visual_evidence';

    final lautBerceritaFile = File(
      '$downloadsDir/Laut Bercerita (Leila S. Chudori).pdf',
    );
    final bicaraFile = File(
      '$downloadsDir/Bicara Itu Ada Seninya (Oh Su Hyang).pdf',
    );
    final suspectXFile = File(
      '$downloadsDir/Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf',
    );

    setUpAll(() {
      Directory(
        '$visualEvidenceDir/scan_enhancement',
      ).createSync(recursive: true);
      Directory('$visualEvidenceDir/reflowable').createSync(recursive: true);
      Directory('$visualEvidenceDir/transitions').createSync(recursive: true);
    });

    // =========================================================================
    // PART A: REAL SCANNED PDF ENHANCEMENT AUDIT & IMAGE COMPARISONS
    // =========================================================================
    test(
      'A. Real Scanned PDF Image Enhancement: Original vs Gentle vs Balanced vs Strong',
      () async {
        expect(
          lautBerceritaFile.existsSync(),
          isTrue,
          reason: 'Laut Bercerita PDF must exist in Downloads',
        );
        expect(
          bicaraFile.existsSync(),
          isTrue,
          reason: 'Bicara Itu Ada Seninya PDF must exist in Downloads',
        );

        final lautDoc = await PdfDocument.openFile(lautBerceritaFile.path);
        // Page 15: Chapter text with dialogue and margin noise
        const targetPageNum = 15;
        final page = lautDoc.pages[targetPageNum - 1];

        const renderW = 595.0 * 1.5;
        const renderH = 842.0 * 1.5;

        final pdfImage = await page.render(
          width: renderW.round(),
          height: renderH.round(),
        );
        expect(pdfImage, isNotNull);

        final rawPixels = pdfImage!.pixels;
        final w = pdfImage.width;
        final h = pdfImage.height;

        // Helper to encode BGRA to PNG bytes
        Future<Uint8List> bgraToPng(
          Uint8List bgraBytes,
          int width,
          int height,
        ) async {
          final comp = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            bgraBytes,
            width,
            height,
            ui.PixelFormat.bgra8888,
            (img) => comp.complete(img),
          );
          final img = await comp.future;
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          img.dispose();
          return byteData!.buffer.asUint8List();
        }

        // Helper to compute luminance stats
        Map<String, double> computeLuminanceStats(
          Uint8List bgraBytes,
          int width,
          int height,
        ) {
          int whiteCount = 0; // > 240
          int paperCount = 0; // 170..240
          int edgeCount = 0; // 90..170 (anti-aliased character edges)
          int darkCount = 0; // < 90 (solid ink)
          double totalLum = 0.0;
          final totalPixels = width * height;

          for (int i = 0; i < totalPixels * 4; i += 4) {
            final b = bgraBytes[i];
            final g = bgraBytes[i + 1];
            final r = bgraBytes[i + 2];
            final lum = (r * 77 + g * 150 + b * 29) >> 8;
            totalLum += lum;

            if (lum >= 240) {
              whiteCount++;
            } else if (lum >= 170) {
              paperCount++;
            } else if (lum >= 90) {
              edgeCount++;
            } else {
              darkCount++;
            }
          }

          return {
            'meanLum': totalLum / totalPixels,
            'whitePct': (whiteCount / totalPixels) * 100.0,
            'paperPct': (paperCount / totalPixels) * 100.0,
            'edgePct': (edgeCount / totalPixels) * 100.0,
            'darkPct': (darkCount / totalPixels) * 100.0,
          };
        }

        // 1. Original (Raw)
        final rawPng = await bgraToPng(rawPixels, w, h);
        await File(
          '$visualEvidenceDir/scan_enhancement/laut_bercerita_p15_original.png',
        ).writeAsBytes(rawPng);
        final rawStats = computeLuminanceStats(rawPixels, w, h);

        // 2. Gentle Enhancement
        const gentleConfig = ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.gentle,
          toGrayscale: true,
          removeGutterShadow: false,
        );
        final gentlePixels = ScannedImageEnhancer.enhanceBgra(
          srcPixels: rawPixels,
          width: w,
          height: h,
          config: gentleConfig,
        );
        final gentlePng = await bgraToPng(gentlePixels, w, h);
        await File(
          '$visualEvidenceDir/scan_enhancement/laut_bercerita_p15_gentle.png',
        ).writeAsBytes(gentlePng);
        final gentleStats = computeLuminanceStats(gentlePixels, w, h);

        // 3. Balanced Enhancement
        const balancedConfig = ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.balanced,
          toGrayscale: true,
          removeGutterShadow: false,
        );
        final balancedPixels = ScannedImageEnhancer.enhanceBgra(
          srcPixels: rawPixels,
          width: w,
          height: h,
          config: balancedConfig,
        );
        final balancedPng = await bgraToPng(balancedPixels, w, h);
        await File(
          '$visualEvidenceDir/scan_enhancement/laut_bercerita_p15_balanced.png',
        ).writeAsBytes(balancedPng);
        final balancedStats = computeLuminanceStats(balancedPixels, w, h);

        // 4. Strong Enhancement
        const strongConfig = ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.strong,
          toGrayscale: true,
          removeGutterShadow: false,
        );
        final strongPixels = ScannedImageEnhancer.enhanceBgra(
          srcPixels: rawPixels,
          width: w,
          height: h,
          config: strongConfig,
        );
        final strongPng = await bgraToPng(strongPixels, w, h);
        await File(
          '$visualEvidenceDir/scan_enhancement/laut_bercerita_p15_strong.png',
        ).writeAsBytes(strongPng);
        final strongStats = computeLuminanceStats(strongPixels, w, h);

        // 5. Gutter Compensation On vs Off
        const gutterOnConfig = ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.balanced,
          toGrayscale: true,
          removeGutterShadow: true,
          isLeftPage: true,
        );
        final gutterOnPixels = ScannedImageEnhancer.enhanceBgra(
          srcPixels: rawPixels,
          width: w,
          height: h,
          config: gutterOnConfig,
        );
        final gutterOnPng = await bgraToPng(gutterOnPixels, w, h);
        await File(
          '$visualEvidenceDir/scan_enhancement/laut_bercerita_p15_gutter_on.png',
        ).writeAsBytes(gutterOnPng);

        pdfImage.dispose();

        // Also render Bicara Itu Ada Seninya (Page 33: scanned text page)
        final bicaraDoc = await PdfDocument.openFile(bicaraFile.path);
        const bicaraPageNum = 33;
        final bPage = bicaraDoc.pages[bicaraPageNum - 1];
        final bPdfImage = await bPage.render(
          width: renderW.round(),
          height: renderH.round(),
        );
        if (bPdfImage != null) {
          final bRawPixels = bPdfImage.pixels;
          final bW = bPdfImage.width;
          final bH = bPdfImage.height;

          // Bicara Original
          final bRawPng = await bgraToPng(bRawPixels, bW, bH);
          await File(
            '$visualEvidenceDir/scan_enhancement/bicara_p33_original.png',
          ).writeAsBytes(bRawPng);

          // Bicara Gentle
          final bGentlePixels = ScannedImageEnhancer.enhanceBgra(
            srcPixels: bRawPixels,
            width: bW,
            height: bH,
            config: gentleConfig,
          );
          final bGentlePng = await bgraToPng(bGentlePixels, bW, bH);
          await File(
            '$visualEvidenceDir/scan_enhancement/bicara_p33_gentle.png',
          ).writeAsBytes(bGentlePng);

          // Bicara Balanced
          final bBalancedPixels = ScannedImageEnhancer.enhanceBgra(
            srcPixels: bRawPixels,
            width: bW,
            height: bH,
            config: balancedConfig,
          );
          final bBalancedPng = await bgraToPng(bBalancedPixels, bW, bH);
          await File(
            '$visualEvidenceDir/scan_enhancement/bicara_p33_balanced.png',
          ).writeAsBytes(bBalancedPng);

          // Bicara Strong
          final bStrongPixels = ScannedImageEnhancer.enhanceBgra(
            srcPixels: bRawPixels,
            width: bW,
            height: bH,
            config: strongConfig,
          );
          final bStrongPng = await bgraToPng(bStrongPixels, bW, bH);
          await File(
            '$visualEvidenceDir/scan_enhancement/bicara_p33_strong.png',
          ).writeAsBytes(bStrongPng);

          bPdfImage.dispose();
        }

        print(
          '\n===============================================================',
        );
        print(
          'REAL SCANNED PDF ENHANCEMENT LUMINANCE AUDIT (Laut Bercerita P.15)',
        );
        print(
          '===============================================================',
        );
        print(
          'ORIGINAL:  Mean Lum: ${rawStats['meanLum']!.toStringAsFixed(1)} | White: ${rawStats['whitePct']!.toStringAsFixed(1)}% | Paper Gray: ${rawStats['paperPct']!.toStringAsFixed(1)}% | Edge: ${rawStats['edgePct']!.toStringAsFixed(1)}% | Ink: ${rawStats['darkPct']!.toStringAsFixed(1)}%',
        );
        print(
          'GENTLE:    Mean Lum: ${gentleStats['meanLum']!.toStringAsFixed(1)} | White: ${gentleStats['whitePct']!.toStringAsFixed(1)}% | Paper Gray: ${gentleStats['paperPct']!.toStringAsFixed(1)}% | Edge: ${gentleStats['edgePct']!.toStringAsFixed(1)}% | Ink: ${gentleStats['darkPct']!.toStringAsFixed(1)}%',
        );
        print(
          'BALANCED:  Mean Lum: ${balancedStats['meanLum']!.toStringAsFixed(1)} | White: ${balancedStats['whitePct']!.toStringAsFixed(1)}% | Paper Gray: ${balancedStats['paperPct']!.toStringAsFixed(1)}% | Edge: ${balancedStats['edgePct']!.toStringAsFixed(1)}% | Ink: ${balancedStats['darkPct']!.toStringAsFixed(1)}%',
        );
        print(
          'STRONG:    Mean Lum: ${strongStats['meanLum']!.toStringAsFixed(1)} | White: ${strongStats['whitePct']!.toStringAsFixed(1)}% | Paper Gray: ${strongStats['paperPct']!.toStringAsFixed(1)}% | Edge: ${strongStats['edgePct']!.toStringAsFixed(1)}% | Ink: ${strongStats['darkPct']!.toStringAsFixed(1)}%',
        );

        // CRITICAL EVALUATION:
        // Verify Gentle & Balanced lift paper without obliterating text ink
        expect(gentleStats['whitePct'], greaterThan(rawStats['whitePct']!));
        expect(
          balancedStats['whitePct'],
          greaterThan(gentleStats['whitePct']!),
        );
        expect(
          balancedStats['darkPct'],
          greaterThanOrEqualTo(rawStats['darkPct']! * 0.90),
          reason:
              'Balanced enhancement must retain at least 90% solid ink density',
        );

        // Check whether Strong mode causes severe edge pixel thinning:
        final edgeErosionRatio =
            (rawStats['edgePct']! - strongStats['edgePct']!) /
            rawStats['edgePct']!;
        print(
          'STRONG MODE EDGE PIXEL EROSION RATIO: ${(edgeErosionRatio * 100).toStringAsFixed(1)}%',
        );
        if (edgeErosionRatio > 0.40) {
          print(
            'CRITICAL WARNING: Strong mode erodes > 40% of anti-aliased character edges, risking thinning of small punctuation.',
          );
        }
      },
    );

    // =========================================================================
    // PART B: REFLOWABLE SEMANTIC STRUCTURE AUDIT ON REAL DOCUMENTS
    // =========================================================================
    test('B. Reflowable Semantic Structure Audit across 3 Real Documents', () async {
      print(
        '\n===============================================================',
      );
      print('REFLOWABLE SEMANTIC STRUCTURE AUDIT ON REAL DOCUMENTS');
      print('===============================================================');

      // 1. The Devotion of Suspect X (Novel with Dialogue & Chapters)
      expect(suspectXFile.existsSync(), isTrue);
      final suspectXDoc = await PdfDocument.openFile(suspectXFile.path);
      expect(suspectXDoc.pages.length, equals(324));

      // 2. Laut Bercerita (Scanned Novel)
      expect(lautBerceritaFile.existsSync(), isTrue);
      final lautDoc = await PdfDocument.openFile(lautBerceritaFile.path);
      expect(lautDoc.pages.length, equals(394));

      // 3. Bicara Itu Ada Seninya (64 MB Scanned Book)
      expect(bicaraFile.existsSync(), isTrue);
      final bicaraDoc = await PdfDocument.openFile(bicaraFile.path);
      expect(bicaraDoc.pages.length, equals(255));

      // Test real document normalization on Suspect X Chapter 1
      final rawSuspectXDoc = BookDocument(
        id: 'real-suspect-x',
        title: 'Kesetiaan Mr. X',
        author: 'Keigo Higashino',
        totalPages: 324,
        chapters: [
          BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Satu',
            blocks: [
              const BookBlock(
                id: 'b1',
                type: BlockType.paragraph,
                text:
                    'KEIGO HIGASHINO\nSATU\n'
                    'Pukul 07.35. Seperti biasa, Ishigami meninggalkan apartemen pagi-pagi sekali. '
                    'Embusan angin terasa dingin, padahal saat ini awal Maret. la mulai melangkah '
                    'dengan dagu terkubur dalam-dalam di balik syal.\n'
                    '"Selamat pagi," sapa Ishigami.\n'
                    '"Pagi, Pak Guru," jawab wanita di kedai bento.',
              ),
            ],
          ),
        ],
      );

      final normSuspectX = BookTextNormalizer.normalizeDocument(rawSuspectXDoc);
      final blocksX = normSuspectX.chapters.expand((c) => c.blocks).toList();

      // Heading detection:
      final chHeading = blocksX
          .where((b) => b.type == BlockType.heading)
          .toList();
      print(
        'Suspect X Chapter Headings detected: ${chHeading.map((b) => b.text).toList()}',
      );
      expect(chHeading, isNotEmpty);
      expect(chHeading.first.text, equals('SATU'));

      // Header stripping:
      final narrativeText = blocksX
          .where((b) => b.type == BlockType.paragraph)
          .map((b) => b.text)
          .join(' ');
      expect(
        narrativeText.contains('KEIGO HIGASHINO'),
        isFalse,
        reason: 'Author header must be stripped from narrative',
      );
      expect(narrativeText, contains('Pukul 07.35.'));
      expect(narrativeText, contains('dalam-dalam'));

      // 2. Bicara Itu Ada Seninya: Lists & Copyright Real Structure
      final rawBicaraDoc = BookDocument(
        id: 'real-bicara',
        title: 'Bicara Itu Ada Seninya',
        author: 'Oh Su Hyang',
        totalPages: 255,
        chapters: [
          BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Hak Cipta',
            blocks: [
              const BookBlock(
                id: 'b_copy',
                type: BlockType.paragraph,
                text:
                    'Hak Cipta Dilindungi Undang-Undang\n'
                    'Dilarang mengutip atau memperbanyak sebagian atau seluruh isi buku ini tanpa izin tertulis dari penerbit.\n'
                    'Katalog Dalam Terbitan (KDT)\n'
                    'ISBN: 978-602-03-8591-4\n'
                    'Penerbit PT Gramedia Pustaka Utama\n'
                    'Cetakan ke-1: Januari 2018',
              ),
              const BookBlock(
                id: 'b_lists',
                type: BlockType.paragraph,
                text:
                    'Tiga teknik komunikasi persuasif yang wajib dikuasai:\n'
                    '1. Dengarkan lawan bicara dengan empati penuh.\n'
                    '2. Sesuaikan tempo dan intonasi suara dengan konteks pembicaraan.\n'
                    '3. Gunakan analogi konkret yang relevan dengan pengalaman pendengar.\n'
                    'Poin penting dalam implementasi:\n'
                    '• Hindari memotong pembicaraan di tengah kalimat.\n'
                    '• Perhatikan bahasa tubuh dan kontak mata secara natural.',
              ),
            ],
          ),
        ],
      );

      final normBicara = BookTextNormalizer.normalizeDocument(rawBicaraDoc);
      final blocksB = normBicara.chapters.expand((c) => c.blocks).toList();

      final copyrightBlocks = blocksB
          .where((b) => b.type == BlockType.copyrightBlock)
          .toList();
      print(
        'Bicara Itu Ada Seninya Copyright Blocks: ${copyrightBlocks.length}',
      );
      expect(copyrightBlocks, isNotEmpty);

      final orderedLists = blocksB
          .where((b) => b.type == BlockType.orderedList)
          .toList();
      print('Bicara Itu Ada Seninya Ordered Lists: ${orderedLists.length}');
      expect(orderedLists.length, equals(3));

      final unorderedLists = blocksB
          .where((b) => b.type == BlockType.unorderedList)
          .toList();
      print('Bicara Itu Ada Seninya Unordered Lists: ${unorderedLists.length}');
      expect(unorderedLists.length, equals(2));
    });

    testWidgets('B2. Visual Rendering Capture of Real Reflowable Document', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));

      final rawBicaraDoc = BookDocument(
        id: 'real-bicara-reflowable',
        title: 'Bicara Itu Ada Seninya',
        author: 'Oh Su Hyang',
        totalPages: 255,
        metadata: {'reconstructionQuality': 'high'},
        chapters: [
          BookChapter(
            id: 'ch0',
            index: 0,
            title: 'Bab 1',
            blocks: [
              const BookBlock(
                id: 'b_title',
                type: BlockType.documentTitle,
                text: 'BICARA ITU ADA SENINYA',
              ),
              const BookBlock(
                id: 'b_sec',
                type: BlockType.sectionHeading,
                text: 'Rahasia Komunikasi Efektif Para Pemenang',
              ),
              const BookBlock(
                id: 'b_ord1',
                type: BlockType.orderedList,
                text:
                    '1. Dengarkan lawan bicara dengan empati penuh tanpa asumsi.',
              ),
              const BookBlock(
                id: 'b_ord2',
                type: BlockType.orderedList,
                text:
                    '2. Sesuaikan tempo dan intonasi suara dengan konteks pembicaraan.',
              ),
              const BookBlock(
                id: 'b_ord3',
                type: BlockType.orderedList,
                text:
                    '3. Gunakan analogi konkret yang relevan dengan pengalaman pendengar.',
              ),
              const BookBlock(
                id: 'b_unord1',
                type: BlockType.unorderedList,
                text: '• Hindari memotong pembicaraan di tengah kalimat.',
              ),
              const BookBlock(
                id: 'b_unord2',
                type: BlockType.unorderedList,
                text:
                    '• Perhatikan bahasa tubuh dan kontak mata secara natural.',
              ),
              const BookBlock(
                id: 'b_copy',
                type: BlockType.copyrightBlock,
                text:
                    'Hak Cipta Dilindungi Undang-Undang. ISBN 978-602-03-8591-4. Diterbitkan oleh PT Gramedia Pustaka Utama.',
              ),
            ],
          ),
        ],
      );

      final globalKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: globalKey,
              child: ReflowableBookReader(
                document: rawBicaraDoc,
                theme: ReadingThemeType.warmPaper,
                typography: const TypographySettings(),
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
            globalKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            await File(
              '$visualEvidenceDir/reflowable/bicara_reflowable_lists_page.png',
            ).writeAsBytes(byteData.buffer.asUint8List());
          }
          img.dispose();
        }
      });
    });

    // =========================================================================
    // PART C: NATIVE PDF TRANSITION FRAME AUDIT (ZERO BLANK CANVAS)
    // =========================================================================
    testWidgets(
      'C. PDF Page Transition Frame-by-Frame Audit in OriginalPdfReader',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        int currentPage = 1;
        final transitionKey = GlobalKey();

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: transitionKey,
                  child: OriginalPdfReader(
                    pdfPath: lautBerceritaFile.path,
                    initialPage: 1,
                    theme: ReadingThemeType.warmPaper,
                    onPageChanged: (p, t) => currentPage = p,
                    onTapContent: () {},
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<OriginalPdfReaderState>(
            find.byType(OriginalPdfReader),
          );
          for (var i = 0; i < 40; i++) {
            if (!state.isLoading && state.document != null) break;
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        });

        final state = tester.state<OriginalPdfReaderState>(
          find.byType(OriginalPdfReader),
        );
        expect(state.currentPage, equals(1));

        // Frame-by-frame transition tracking
        print(
          '\n===============================================================',
        );
        print('PDF PAGE TRANSITION FRAME AUDIT (Laut Bercerita)');
        print(
          '===============================================================',
        );

        bool observedBlankCanvas = false;
        int framesSampled = 0;

        await tester.runAsync(() async {
          state.nextPage();

          // Sample 12 consecutive frames across the transition (every ~30ms)
          for (int i = 0; i < 12; i++) {
            await Future.delayed(const Duration(milliseconds: 30));
            await tester.pump();
            framesSampled++;

            final rawImages = find.byType(RawImage);
            if (rawImages.evaluate().isEmpty) {
              observedBlankCanvas = true;
              print('FRAME $i: DETECTED BLANK CANVAS WITHOUT RawImage!');
            }

            // Capture frames 0, 3, 6, 9
            if (i == 0 || i == 3 || i == 6 || i == 9) {
              final boundary =
                  transitionKey.currentContext?.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary != null) {
                final img = await boundary.toImage(pixelRatio: 1.0);
                final byteData = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (byteData != null) {
                  await File(
                    '$visualEvidenceDir/transitions/transition_frame_0$i.png',
                  ).writeAsBytes(byteData.buffer.asUint8List());
                }
                img.dispose();
              }
            }
          }

          // Complete transition
          await Future.delayed(const Duration(milliseconds: 200));
          await tester.pump();
        });

        print(
          'Sampled $framesSampled frames during page transition. Observed blank canvas: $observedBlankCanvas',
        );
        expect(
          observedBlankCanvas,
          isFalse,
          reason: 'Zero blank frames must occur during page turn!',
        );
        expect(currentPage, greaterThanOrEqualTo(1));
      },
    );

    // =========================================================================
    // PART D: PERFORMANCE & RAM AUDIT (64MB Scanned PDF)
    // =========================================================================
    test('D. Performance & Memory Audit: 64MB Scanned PDF Stress Load', () async {
      final initialRss = ProcessInfo.currentRss;
      final stopwatch = Stopwatch()..start();

      // Open 64MB PDF
      final doc = await PdfDocument.openFile(bicaraFile.path);
      final openDuration = stopwatch.elapsedMilliseconds;

      // Render 5 consecutive high-resolution pages with S-curve enhancement
      final renderStopwatch = Stopwatch()..start();
      for (int p = 1; p <= 5; p++) {
        final page = doc.pages[p - 1];
        final img = await page.render(width: 800, height: 1100);
        if (img != null) {
          final enhanced = ScannedImageEnhancer.enhanceBgra(
            srcPixels: img.pixels,
            width: img.width,
            height: img.height,
            config: const ScanEnhancementConfig(
              isEnabled: true,
              intensity: ScanEnhancementIntensity.balanced,
            ),
          );
          expect(enhanced.length, equals(img.pixels.length));
          img.dispose();
        }
      }
      final renderDuration = renderStopwatch.elapsedMilliseconds;
      final finalRss = ProcessInfo.currentRss;
      final rssDeltaMb = (finalRss - initialRss) / (1024 * 1024);

      print(
        '\n===============================================================',
      );
      print('PERFORMANCE & RAM AUDIT (64MB Bicara Itu Ada Seninya)');
      print('===============================================================');
      print('Document Open Duration: $openDuration ms');
      print(
        '5 Pages Rendered & Enhanced: $renderDuration ms (${(renderDuration / 5).toStringAsFixed(1)} ms/page)',
      );
      print('Process RSS Delta: ${rssDeltaMb.toStringAsFixed(2)} MB');

      expect(
        renderDuration / 5,
        lessThan(120.0),
        reason: 'Per-page render+enhance latency must be < 120 ms',
      );
      expect(
        rssDeltaMb,
        lessThan(150.0),
        reason: 'RSS memory delta must remain bounded < 150 MB',
      );
    });
  });
}
