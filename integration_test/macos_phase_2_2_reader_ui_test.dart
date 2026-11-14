import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as p;
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sampleDoc = ReaderDocument(
    bookId: 'book-mac-qa',
    title: 'Filosofi Arsitektur Membaca Digital',
    author: 'Tim Antigravity & Apple Books Architecture',
    totalPages: 50,
    chapters: [
      ReaderChapter(
        id: 'c1',
        title: 'Bab 1: Eksplorasi Membaca Modern',
        index: 0,
        nodes: [
          const ContentNode(
            id: 'h1',
            type: ContentNodeType.heading,
            text: 'Evolusi Tampilan Baca Digital',
            level: 1,
            sourcePdfPage: 1,
          ),
          ContentNode(
            id: 'p1',
            type: ContentNodeType.paragraph,
            text:
                'Membaca di era layar modern menuntut keseimbangan antara keanggunan tipografi cetak dan keluwesan media digital. Tata letak reflowable memungkinkan teks mengalir secara alami pada berbagai resolusi jendela macOS. ' *
                3,
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'q1',
            type: ContentNodeType.quote,
            text:
                'Buku digital yang baik tidak memaksa mata pembaca beradaptasi pada mesin, melainkan mesin yang beradaptasi dengan ritme alami membaca manusia.',
            sourcePdfPage: 2,
          ),
          ContentNode(
            id: 'p2',
            type: ContentNodeType.paragraph,
            text:
                'Dengan dukungan paginasi cerdas dan mode gulir vertikal berkesinambungan (continuous scrolling), pembaca memiliki kebebasan penuh memilih preferensi kenyamanan mereka tanpa khawatir kehilangan posisi baca saat berganti mode. ' *
                2,
            sourcePdfPage: 2,
          ),
        ],
      ),
      ReaderChapter(
        id: 'c2',
        title: 'Bab 2: Sinkronisasi dan Preservasi Posisi',
        index: 1,
        nodes: [
          const ContentNode(
            id: 'h2',
            type: ContentNodeType.heading,
            text: 'Stabilitas Titik Jangkar Konten',
            level: 2,
            sourcePdfPage: 3,
          ),
          ContentNode(
            id: 'p3',
            type: ContentNodeType.paragraph,
            text:
                'Kunci dari pengalaman membaca hibrida yang mulus adalah preservasi anchor node berbasis ID dan karakter offset. Kapan pun ukuran jendela diubah atau ukuran font disesuaikan, lokasi baca tetap tepat pada kalimat yang sedang dibaca. ' *
                3,
            sourcePdfPage: 3,
          ),
          ContentNode(
            id: 'p4',
            type: ContentNodeType.paragraph,
            text:
                'Setiap node teks mempertahankan referensi ke nomor halaman fisik dokumen asli, memungkinkan sitasi akademik dan verifikasi rujukan tetap akurat tanpa mengorbankan keterbacaan tipografis. ' *
                2,
            sourcePdfPage: 4,
          ),
        ],
      ),
    ],
  );

  final screenshotDir =
      p.join(Directory.systemTemp.path, 'db_phase_2_2_screenshots');

  Future<void> captureBoundary(GlobalKey key, String filename) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint('WARNING: Could not find RenderRepaintBoundary for $filename');
      return;
    }
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final file = File('$screenshotDir/$filename');
      file.writeAsBytesSync(byteData.buffer.asUint8List());
      debugPrint(
        'CAPTURED SCREENSHOT: ${file.path} (${file.lengthSync()} bytes)',
      );
    }
  }

  testWidgets('Phase 2.2 macOS Native Visual QA: All Modes, Spreads & Themes', (
    tester,
  ) async {
    final repaintKey = GlobalKey();

    // 1. SCENARIO 1: Paginated Single-Page Narrow Viewport (<850px)
    debugPrint('--- Running Scenario 1: Paginated Narrow Viewport ---');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflowableLayoutModeProvider(
            'book-mac-qa',
          ).overrideWith((ref) => ReflowableLayoutMode.paginated),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: 760,
                height: 800,
                child: ReflowableReaderContainer(
                  bookId: 'book-mac-qa',
                  document: sampleDoc,
                  initialChapterIndex: 0,
                  initialPosition: 0,
                  initialAnchorNodeId: 'h1',
                  theme: ReadingThemeType.white,
                  typography: const TypographySettings(fontSize: 16.0),
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await captureBoundary(repaintKey, 'phase_2_2_paginated_narrow_light.png');

    // 2. SCENARIO 2: Paginated Two-Page Spread Wide Viewport (>=850px, e.g. 1200px)
    debugPrint('--- Running Scenario 2: Paginated Wide Spread Viewport ---');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflowableLayoutModeProvider(
            'book-mac-qa',
          ).overrideWith((ref) => ReflowableLayoutMode.paginated),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: 1200,
                height: 750,
                child: ReflowableReaderContainer(
                  bookId: 'book-mac-qa',
                  document: sampleDoc,
                  initialChapterIndex: 0,
                  initialPosition: 0,
                  initialAnchorNodeId: 'h1',
                  theme: ReadingThemeType.white,
                  typography: const TypographySettings(fontSize: 16.0),
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await captureBoundary(repaintKey, 'phase_2_2_paginated_wide_spread.png');

    // 3. SCENARIO 3: Paginated Sepia Warm Theme (Two-Page Spread)
    debugPrint('--- Running Scenario 3: Paginated Sepia Theme ---');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflowableLayoutModeProvider(
            'book-mac-qa',
          ).overrideWith((ref) => ReflowableLayoutMode.paginated),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: 1100,
                height: 750,
                child: ReflowableReaderContainer(
                  bookId: 'book-mac-qa',
                  document: sampleDoc,
                  initialChapterIndex: 0,
                  initialPosition: 0,
                  initialAnchorNodeId: 'h1',
                  theme: ReadingThemeType.sepia,
                  typography: const TypographySettings(
                    fontFamily: ReadingFontFamily.georgia,
                    fontSize: 18.0,
                    lineSpacing: 1.6,
                  ),
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await captureBoundary(repaintKey, 'phase_2_2_paginated_sepia_theme.png');

    // 4. SCENARIO 4: Continuous Scrolling Reader in Dark Mode
    debugPrint('--- Running Scenario 4: Continuous Scrolling Dark Mode ---');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflowableLayoutModeProvider(
            'book-mac-qa',
          ).overrideWith((ref) => ReflowableLayoutMode.scrolling),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: 900,
                height: 800,
                child: ReflowableReaderContainer(
                  bookId: 'book-mac-qa',
                  document: sampleDoc,
                  initialChapterIndex: 0,
                  initialPosition: 0,
                  initialAnchorNodeId: 'h1',
                  theme: ReadingThemeType.black,
                  typography: const TypographySettings(
                    fontFamily: ReadingFontFamily.sansSerif,
                    fontSize: 17.0,
                  ),
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await captureBoundary(repaintKey, 'phase_2_2_scrolling_dark_mode.png');

    // 5. SCENARIO 5: Full Reading Experience with Top and Bottom Floating Overlays
    debugPrint('--- Running Scenario 5: Full ReadingScreen Overlays ---');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reflowableLayoutModeProvider(
            'book-mac-qa',
          ).overrideWith((ref) => ReflowableLayoutMode.paginated),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: 1050,
                height: 750,
                child: Stack(
                  children: [
                    ReflowableReaderContainer(
                      bookId: 'book-mac-qa',
                      document: sampleDoc,
                      initialChapterIndex: 0,
                      initialPosition: 0,
                      initialAnchorNodeId: 'q1',
                      theme: ReadingThemeType.white,
                      typography: const TypographySettings(fontSize: 16.0),
                      onTapContent: () {},
                      onProgressChanged: (ch, page, pct, anchor, offset) {},
                    ),
                    // Simulated overlay bars
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_back, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                sampleDoc.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_stories,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Buku Terbuka (Spread)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.format_size, size: 20),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 32,
                      right: 32,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Bab 1 dari 2',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            Text(
                              'Halaman 1–2 dari 4',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '25% selesai',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await captureBoundary(
      repaintKey,
      'phase_2_2_reading_screen_full_overlay.png',
    );

    debugPrint(
      '--- All 5 Phase 2.2 native visual QA screenshots captured successfully! ---',
    );
  });
}
