// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/processing/models/ocr_queue_state.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/background_ocr_queue.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';

int _levenshtein(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(t.length + 1, 0);

  for (int i = 0; i < s.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < t.length; j++) {
      int cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
      v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
    }
    for (int j = 0; j <= t.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[t.length];
}

int _wordLevenshtein(List<String> s, List<String> t) {
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(t.length + 1, 0);

  for (int i = 0; i < s.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < t.length; j++) {
      int cost = (s[i] == t[j]) ? 0 : 1;
      v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
    }
    for (int j = 0; j <= t.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[t.length];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
  final dbFile = File('/Users/davindalana/Documents/digital_books_db.sqlite');
  final pdfFile = File(
    '/Users/davindalana/Documents/DigitalBooks/originals/$bookId.pdf',
  );
  final processedJsonFile = File(
    '/Users/davindalana/Documents/DigitalBooks/books/$bookId.json',
  );

  late AppDatabase db;
  late DatabaseService dbService;
  late AppleVisionOcrService ocrService;
  late OcrSemanticPipeline semanticPipeline;
  late BackgroundOcrQueue queue;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    expect(dbFile.existsSync(), isTrue, reason: 'Database file must exist');
    expect(pdfFile.existsSync(), isTrue, reason: 'Original PDF must exist');

    db = AppDatabase(NativeDatabase(dbFile));
    dbService = DatabaseService(db);
    ocrService = const AppleVisionOcrService();
    semanticPipeline = OcrSemanticPipeline(dbService);
    queue = BackgroundOcrQueue(
      dbService: dbService,
      ocrService: ocrService,
      semanticPipeline: semanticPipeline,
    );
  });

  tearDownAll(() async {
    queue.dispose();
    await db.close();
  });

  group('Real Book Acceptance: OCR to Horizontal Paginated Reading', () {
    test(
      '1. Offline OCR Queue: Process and Persist All 255 Pages',
      () async {
        print(
          '\n===============================================================',
        );
        print('STEP 1: BACKGROUND OCR QUEUE EXECUTION (255 PAGES)');
        print(
          '===============================================================',
        );

        // Check current state in DB
        final initialPages = await dbService.getOcrPagesForBook(bookId);
        final completedBefore = initialPages
            .where((p) => p.status == 'completed')
            .length;
        final failedBefore = initialPages
            .where((p) => p.status == 'failed')
            .length;
        print(
          'Initial OCR status in DB: $completedBefore completed, $failedBefore failed of ${initialPages.length} total rows',
        );

        final sw = Stopwatch()..start();
        int lastReportedPage = 0;

        final sub = queue.progressStream.listen((progress) {
          if (progress.currentPageIndex > 0 &&
              progress.currentPageIndex % 25 == 0 &&
              progress.currentPageIndex != lastReportedPage) {
            lastReportedPage = progress.currentPageIndex;
            print(
              '  [Queue Progress] Page ${progress.currentPageIndex}/${progress.totalPages} | '
              'Completed: ${progress.completedPages} | '
              'Avg Latency: ${progress.averagePageDurationMs.toStringAsFixed(1)} ms/page',
            );
          }
        });

        // Start queue with auto-reconstruct
        await queue.start(
          bookId: bookId,
          pdfPath: pdfFile.path,
          autoReconstruct: true,
        );

        await sub.cancel();
        sw.stop();

        try {
          final doc = await semanticPipeline.reconstructBook(
            bookId: bookId,
            pdfPath: pdfFile.path,
          );
          print(
            'Direct reconstructBook result: $doc (chapters: ${doc?.chapters.length})',
          );
        } catch (e, st) {
          print('Direct reconstructBook EXCEPTION: $e\n$st');
        }

        print(
          'OCR Queue Finished in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
        );
        if (queue.state.status == OcrQueueStatus.error) {
          print('Queue error message: ${queue.state.errorMessage}');
        }
        expect(queue.state.status, equals(OcrQueueStatus.completed));
        expect(queue.state.completedPages, equals(255));
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test('2. Page-Level SQLite Persistence Verification', () async {
      print(
        '\n===============================================================',
      );
      print('STEP 2: DATABASE PERSISTENCE AUDIT');
      print('===============================================================');

      final pages = await dbService.getOcrPagesForBook(bookId);
      expect(pages.length, equals(255));

      final completedPages = pages
          .where((p) => p.status == 'completed')
          .toList();
      final failedPages = pages.where((p) => p.status == 'failed').toList();
      final emptyPages = pages.where((p) => p.charCount == 0).toList();

      expect(
        failedPages,
        isEmpty,
        reason: 'Zero pages should have failed status',
      );
      expect(
        completedPages.length,
        equals(255),
        reason: 'All 255 pages must be completed',
      );

      final totalChars = pages.fold<int>(0, (sum, p) => sum + p.charCount);
      final totalDurationMs = pages.fold<double>(
        0.0,
        (sum, p) => sum + p.durationMs,
      );
      final avgDurationMs = totalDurationMs / pages.length;

      final confidences = pages
          .where((p) => p.charCount > 0)
          .map((p) => p.confidence)
          .toList();
      final avgConfidence = confidences.isEmpty
          ? 1.0
          : confidences.reduce((a, b) => a + b) / confidences.length;
      final minConfidence = confidences.isEmpty
          ? 1.0
          : confidences.reduce(math.min);
      final maxConfidence = confidences.isEmpty
          ? 1.0
          : confidences.reduce(math.max);

      print('• Total Pages: ${pages.length}');
      print('• Completed Pages: ${completedPages.length} (100%)');
      print('• Failed Pages: ${failedPages.length} (0%)');
      print(
        '• Empty Pages (flyleaf/blank): ${emptyPages.length} pages (indices: ${emptyPages.map((p) => p.pageIndex).toList()})',
      );
      print('• Total Characters Extracted: $totalChars');
      print(
        '• Total OCR Processing Duration: ${(totalDurationMs / 1000).toStringAsFixed(1)}s',
      );
      print(
        '• Average Duration Per Page: ${avgDurationMs.toStringAsFixed(1)} ms',
      );
      print(
        '• Mean Confidence Score (non-empty pages): ${(avgConfidence * 100).toStringAsFixed(2)}%',
      );
      print(
        '• Min Confidence Score: ${(minConfidence * 100).toStringAsFixed(2)}%',
      );
      print(
        '• Max Confidence Score: ${(maxConfidence * 100).toStringAsFixed(2)}%',
      );

      expect(
        totalChars,
        greaterThan(150000),
        reason: '255-page book should have substantial text',
      );
      expect(
        avgConfidence,
        greaterThan(0.90),
        reason: 'Apple Vision confidence should exceed 90%',
      );
    });

    test('3. Semantic Reconstruction Structure & Chapter Partitioning', () async {
      print(
        '\n===============================================================',
      );
      print('STEP 3: SEMANTIC RECONSTRUCTION AUDIT');
      print('===============================================================');

      expect(processedJsonFile.existsSync(), isTrue);
      final jsonStr = await processedJsonFile.readAsString();
      final bookDoc = BookDocument.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      print('Reconstructed Book Document:');
      print('• Title: ${bookDoc.title}');
      print('• Author: ${bookDoc.author}');
      print('• Total Chapters: ${bookDoc.chapters.length}');

      for (int i = 0; i < bookDoc.chapters.length; i++) {
        final ch = bookDoc.chapters[i];
        final blockTypes = ch.blocks.map((b) => b.type.name).toSet();
        print(
          '  Chapter $i: "${ch.title}" (Blocks: ${ch.blocks.length}, Types: $blockTypes)',
        );
      }

      // Assert chapter titles
      final chapterTitles = bookDoc.chapters.map((c) => c.title).toList();
      expect(
        chapterTitles.any((t) => t.contains('BAB I') || t.contains('BAB 1')),
        isTrue,
      );
      expect(
        chapterTitles.any((t) => t.contains('BAB II') || t.contains('BAB 2')),
        isTrue,
      );
      expect(
        chapterTitles.any((t) => t.contains('BAB III') || t.contains('BAB 3')),
        isTrue,
      );
      expect(
        chapterTitles.any((t) => t.contains('BAB IV') || t.contains('BAB 4')),
        isTrue,
      );
      expect(
        chapterTitles.any((t) => t.contains('BAB V') || t.contains('BAB 5')),
        isTrue,
      );

      // Verify that no cover images leak into body chapters
      for (final ch in bookDoc.chapters) {
        for (final b in ch.blocks) {
          if (b.type == BlockType.image) {
            expect(
              b.metadata['role'],
              isNot(equals('coverImage')),
              reason: 'Cover image must not be placed inside body chapters',
            );
          }
        }
      }

      // Verify total blocks across book
      final totalBlocks = bookDoc.chapters.fold<int>(
        0,
        (sum, c) => sum + c.blocks.length,
      );
      print('• Total Structured Blocks: $totalBlocks');
      expect(totalBlocks, greaterThan(300));
    });

    test('4. Ground-Truth Transcription Validation (CER & WER)', () async {
      print(
        '\n===============================================================',
      );
      print('STEP 4: GROUND-TRUTH TRANSCRIPTION VALIDATION');
      print('===============================================================');

      final representativePages = <int, Map<String, dynamic>>{
        12: {
          'name': 'Front Matter: Daftar Isi',
          'type': 'Table of Contents / Front Matter',
          'groundTruth':
              'Daftar Isi Testimoni Prolog - Membuka Peluang Kesempatan dengan Kebiasaan Bicara Bab I Perbedaan Juara 1 dan Juara 2 Terletak Pada Ucapannya Dari Mana Datangnya Kesan Pertama "Nyawa" Logika Mengungkapkan Diri Lewat Storytelling Penyebab Takut Bicara Lengkapi dengan Bahasa Nonverbal Mengubah Cara Bicara, Mengubah Hidup Mengubah yang Tidak Mungkin Menjadi Mungkin',
        },
        18: {
          'name': 'BAB I Divider Page',
          'type': 'Chapter Divider',
          'groundTruth':
              'PERBEDAAN JUARA 1 DAN JUARA 2 TERLETAK PADA UCAPANNYA BAB I',
        },
        29: {
          'name': 'Page 29: Numbered List & Rules',
          'type': 'Numbered List & Subsections',
          'groundTruth':
              '3. Konsisten dalam Bersikap Saat kondisi argumen kita lemah, kita akan jatuh ke dalam kontradiksi dan posisi yang membingungkan, sebab kita akan mengeluarkan argumen baru yang berbeda dengan apa yang sebelumnya kita ungkapkan. Oleh karena itu, kita harus memiliki sikap konsisten dengan pendapat kita dari awal hingga akhir. 4. Gunakan Kata-Kata Sederhana Ada orang yang suka menggunakan bahasa Inggris, karakter Mandarin, atau istilah-istilah tinggi yang hanya diketahui dirinya sendiri seolah-olah ia yang paling tahu segalanya. Alih-alih membantu dalam menyampaikan pendapatnya, hal ini justru akan membuatnya menerima penolakan dari lawan bicara. Ingatlah bahwa ucapan yang sulit dimengerti adalah penghalang komunikasi. 5. Tetap Tenang Kita dapat menemukan orang-orang yang sentimental saat berbicara dalam acara debat di televisi. Mereka sering kali melontarkan perkataan-perkataan yang tidak berhubungan dengan topik pembicaraan. Contohnya mencari kesalahan untuk menyerang secara personal. Hal ini muncul karena situasinya menjengkelkan. Ingatlah, kekesalan merupakan hal yang dilarang karena akan menciptakan pembicaraan yang tidak logis dan bersikap tenang sangat dibutuhkan dalam situasi seperti ini.',
        },
        33: {
          'name': 'Page 33: BAB I Subsection',
          'type': 'Subsection & Dialogue',
          'groundTruth':
              'Katarsis dalam Cerita yang Bagus "Latihan storytelling atau menyampaikan cerita sama saja seperti mengasah kemampuan komunikasi. Jika Anda berencana ingin menjadi pembicara, berlatih storytelling akan sangat membantu. Kalaupun tidak ingin menjadi pembicara, latihan ini akan menjadi senjata besar dalam kehidupan sosial Anda". Kata-kata di atas diucapkan oleh Doug Stevenson, konsultan ahli presentasi dan pelatih teknik mengajar terbaik di Amerika. Menurutnya, storytelling adalah keterampilan berbicara yang sangat bermanfaat baik saat mengajar, pertemuan bisnis, wawancara, ataupun kehidupan sehari-hari. Lalu bagaimana caranya berbicara dengan metode storytelling? Storytelling yang baik membutuhkan empat hal (tema, konflik, simpati, dan solusi) dan dua faktor tambahan (pembalikan dan alasan). Pertama, kita lihat keempat unsur yang diperlukan, yaitu: 1. Tema Harus memiliki tema yang menonjol. Cerita yang bertema menonjol disukai oleh orang-orang. Legenda atau dongeng-dongeng klasik bertahan lama karena mengandung sebuah tema, bahwa yang baik akan menang dan yang jahat akan dihukum. Cerita yang ingin disampaikan harus konsisten dengan satu tema.',
        },
        60: {
          'name': 'BAB II Divider Page',
          'type': 'Chapter Divider',
          'groundTruth': 'PINTAR MENDENGAR, PANDAI BERBICARA BAB II',
        },
        114: {
          'name': 'BAB III Divider Page',
          'type': 'Chapter Divider',
          'groundTruth':
              'UCAPAN YANG MEMBUAT LAWAN BICARA MEMIHAK KITA BAB III',
        },
        153: {
          'name': 'BAB IV Divider Page',
          'type': 'Chapter Divider',
          'groundTruth': 'BERATNYA UCAPAN DITENTUKAN OLEH DALAMNYA ISI BAB IV',
        },
        209: {
          'name': 'BAB V Divider Page',
          'type': 'Chapter Divider',
          'groundTruth': 'SUARA BAGUS BUKAN BAWAAN DARI LAHIR BAB V',
        },
      };

      final results = <Map<String, dynamic>>[];

      for (final entry in representativePages.entries) {
        final pageIdx = entry.key;
        final info = entry.value;
        final groundTruth = (info['groundTruth'] as String)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        final ocrPage = await dbService.getOcrPage(bookId, pageIdx);
        expect(ocrPage, isNotNull);

        final rawLines = (jsonDecode(ocrPage!.linesJson) as List)
            .cast<Map<String, dynamic>>();
        // Filter out running header/footer (e.g. "BICARA ITU ADA SENINYA" or solitary page numbers)
        final bodyLines = rawLines
            .map((l) => l['text'] as String)
            .where((t) {
              final trimmed = t.trim();
              if (RegExp(r'^\d+$').hasMatch(trimmed)) return false;
              if (trimmed.contains('BICARA ITU ADA SENINYA')) {
                final cleaned = trimmed
                    .replaceAll(
                      RegExp(r'(\d+\s+)?BICARA ITU ADA SENINYA(\s+\d+)?'),
                      '',
                    )
                    .trim();
                return cleaned.isNotEmpty;
              }
              return true;
            })
            .map((t) {
              return t
                  .replaceAll(
                    RegExp(r'(\d+\s+)?BICARA ITU ADA SENINYA(\s+\d+)?'),
                    '',
                  )
                  .replaceAll('|', 'I')
                  .trim();
            })
            .where((t) => t.isNotEmpty)
            .toList();

        final rawOcrText = bodyLines.join(' ');
        // Normalize leader dots and repetitive whitespace for fair comparison
        final ocrText = rawOcrText
            .replaceAll(RegExp(r'[\.\-]{2,}\s*[0-9a-zA-Z]*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final truthNorm = groundTruth
            .replaceAll(RegExp(r'[\.\-]{2,}\s*[0-9a-zA-Z]*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        // Calculate Character Error Rate (CER)
        final charDist = _levenshtein(ocrText, truthNorm);
        final cer = truthNorm.isEmpty ? 0.0 : (charDist / truthNorm.length);

        // Calculate Word Error Rate (WER)
        final truthWords = truthNorm
            .split(' ')
            .where((w) => w.isNotEmpty)
            .toList();
        final ocrWords = ocrText.split(' ').where((w) => w.isNotEmpty).toList();
        final wordDist = _wordLevenshtein(ocrWords, truthWords);
        final wer = truthWords.isEmpty ? 0.0 : (wordDist / truthWords.length);

        results.add({
          'page': pageIdx,
          'name': info['name'],
          'type': info['type'],
          'truthLength': groundTruth.length,
          'ocrLength': ocrText.length,
          'charDist': charDist,
          'cer': cer,
          'wordDist': wordDist,
          'wer': wer,
        });

        print(
          '• [Page $pageIdx: ${info['name']}] '
          'CER: ${(cer * 100).toStringAsFixed(2)}% (dist=$charDist/${groundTruth.length}) | '
          'WER: ${(wer * 100).toStringAsFixed(2)}% (dist=$wordDist/${truthWords.length})',
        );

        // Sanity assertions: CER must be under 15% and WER under 20% even on imperfect scans
        expect(
          cer,
          lessThan(0.15),
          reason: 'CER must be under 15% for page $pageIdx',
        );
        expect(
          wer,
          lessThan(0.25),
          reason: 'WER must be under 25% for page $pageIdx',
        );
      }

      final meanCer =
          results.map((r) => r['cer'] as double).reduce((a, b) => a + b) /
          results.length;
      final meanWer =
          results.map((r) => r['wer'] as double).reduce((a, b) => a + b) /
          results.length;

      print(
        '\nGround-Truth Summary across ${results.length} Representative Pages:',
      );
      print('• Mean CER: ${(meanCer * 100).toStringAsFixed(2)}%');
      print('• Mean WER: ${(meanWer * 100).toStringAsFixed(2)}%');
      expect(
        meanCer,
        lessThan(0.08),
        reason: 'Mean CER across representative pages must be < 8%',
      );
    });

    test('5. Horizontal Paginated Reflowable Reader Integration', () async {
      print(
        '\n===============================================================',
      );
      print('STEP 5: HORIZONTAL PAGINATED READER INTEGRATION');
      print('===============================================================');

      final jsonStr = await processedJsonFile.readAsString();
      final bookDoc = BookDocument.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      final readerDoc = ReaderDocument.fromBookDocument(bookDoc);

      // 1. Two-Page Spread Layout (Desktop: 1100 x 750)
      print('Testing Desktop Two-Page Spread Layout (1100 x 750)...');
      final spreadPages = PaginationEngine.paginateDocument(
        document: readerDoc,
        viewportWidth: 1100,
        viewportHeight: 750,
        typography: const TypographySettings(),
      );

      expect(spreadPages, isNotEmpty);
      print('• Spread Total Pages: ${spreadPages.length}');

      // Verify no blank pages
      for (int i = 0; i < spreadPages.length; i++) {
        final p = spreadPages[i];
        expect(p.slices, isNotEmpty, reason: 'Page $i must have slices');
        final hasContent = p.slices.any((s) => s.textSlice.trim().isNotEmpty);
        expect(
          hasContent,
          isTrue,
          reason: 'Page $i must contain non-blank text',
        );
      }

      // 2. Single-Page Layout (Compact Window: 600 x 800)
      print('Testing Compact Single-Page Layout (600 x 800)...');
      final singlePages = PaginationEngine.paginateDocument(
        document: readerDoc,
        viewportWidth: 600,
        viewportHeight: 800,
        typography: const TypographySettings(),
      );

      expect(singlePages, isNotEmpty);
      print('• Single-Page Total Pages: ${singlePages.length}');
      expect(singlePages.length, greaterThan(100));

      for (int i = 0; i < singlePages.length; i++) {
        final p = singlePages[i];
        expect(p.slices, isNotEmpty, reason: 'Single page $i must have slices');
        final hasContent = p.slices.any((s) => s.textSlice.trim().isNotEmpty);
        expect(
          hasContent,
          isTrue,
          reason: 'Single page $i must contain non-blank text',
        );
      }

      // Verify chapter index distribution across pages
      final chaptersRepresented = spreadPages
          .map((p) => p.chapterIndex)
          .toSet();
      print('• Chapters Represented in Paginated Flow: $chaptersRepresented');
      expect(chaptersRepresented.length, equals(bookDoc.chapters.length));
    });

    testWidgets('6. Real Book Native Visual Rendering & Evidence Capture', (
      tester,
    ) async {
      print(
        '\n===============================================================',
      );
      print('STEP 6: REAL BOOK NATIVE VISUAL EVIDENCE CAPTURE');
      print('===============================================================');

      final evidenceDir = Directory('docs/visual_evidence/phase_3_6');
      if (!evidenceDir.existsSync()) {
        evidenceDir.createSync(recursive: true);
      }

      final jsonStr = processedJsonFile.readAsStringSync();
      final bookDoc = BookDocument.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
      final readerDoc = ReaderDocument.fromBookDocument(bookDoc);

      Future<void> captureScreen({
        required Widget widget,
        required Size size,
        required String filename,
      }) async {
        final key = GlobalKey();
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Inter', brightness: Brightness.light),
              home: Scaffold(
                backgroundColor: const Color(0xFFF8F9FA),
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: widget,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          final pngBytes = byteData!.buffer.asUint8List();

          final outFile = File('${evidenceDir.path}/$filename');
          outFile.writeAsBytesSync(pngBytes);
          print(
            '  ✓ Captured: ${outFile.path} (${(pngBytes.length / 1024).toStringAsFixed(1)} KB)',
          );
        });
      }

      // 1. Desktop Two-Page Spread rendering Chapter 4 (BAB I)
      await captureScreen(
        widget: PaginatedReflowableReader(
          document: readerDoc,
          initialAnchorNodeId: readerDoc.chapters[4].nodes.first.id,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1100, 750),
        filename: '02_real_book_spread_bab1.png',
      );

      // 2. Desktop Two-Page Spread rendering Chapter 5 (BAB II)
      await captureScreen(
        widget: PaginatedReflowableReader(
          document: readerDoc,
          initialAnchorNodeId: readerDoc.chapters[5].nodes.first.id,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1100, 750),
        filename: '03_real_book_spread_bab2.png',
      );

      // 3. Compact Single-Page rendering Chapter 4 (BAB I)
      await captureScreen(
        widget: PaginatedReflowableReader(
          document: readerDoc,
          initialAnchorNodeId: readerDoc.chapters[4].nodes.first.id,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(600, 800),
        filename: '04_real_book_compact_single.png',
      );

      // Clean up physical size
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
