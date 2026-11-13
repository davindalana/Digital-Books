// ignore_for_file: avoid_print, unused_import, unused_local_variable, unnecessary_underscores
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  const screenshotDir =
      '/Users/davindalana/.gemini/antigravity/brain/d28b8768-0772-4001-8dca-34c07962ba48';

  Future<void> captureBoundary(GlobalKey key, String filename) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      print('WARNING: Could not find RenderRepaintBoundary for $filename');
      return;
    }
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final file = File('$screenshotDir/$filename');
      file.writeAsBytesSync(byteData.buffer.asUint8List());
      print('CAPTURED SCREENSHOT: ${file.path} (${file.lengthSync()} bytes)');
    }
  }

  group('Phase 2.8.4 — Native macOS Visual Regression & Reading Acceptance', () {
    late ReaderDocument suspectXDoc;
    late ReaderDocument letThemDoc;
    late ReaderDocument lautBerceritaDoc;

    const booksDir = '/Users/davindalana/Documents/DigitalBooks/books';
    const originalsDir = '/Users/davindalana/Documents/DigitalBooks/originals';

    setUpAll(() async {
      // 1. The Devotion of Suspect X
      final suspectXFile = File(
        '$booksDir/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
      );
      if (suspectXFile.existsSync()) {
        final json =
            jsonDecode(await suspectXFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        suspectXDoc = ReflowableEngine.normalizeDocument(normDoc);
      }

      // 2. The Let Them Theory
      final letThemFile = File(
        '$booksDir/8cda23f0-bf42-4a4d-a1fd-30d2943835c9.json',
      );
      if (letThemFile.existsSync()) {
        final json =
            jsonDecode(await letThemFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        letThemDoc = ReflowableEngine.normalizeDocument(normDoc);
      }

      // 3. Laut Bercerita
      final lautFile = File(
        '$booksDir/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.json',
      );
      if (lautFile.existsSync()) {
        final json =
            jsonDecode(await lautFile.readAsString()) as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        lautBerceritaDoc = ReflowableEngine.normalizeDocument(normDoc);
      }
    });

    testWidgets(
      '1. Suspect X: Chapter Opening, Dialogue & Split Paragraph Spread',
      (tester) async {
        final repaintKey = GlobalKey();
        final ch1 = suspectXDoc.chapters[1]; // SATU

        // 1A. Chapter Opening Page (Page 0 of Chapter 1)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reflowableLayoutModeProvider(
                'suspect-x',
              ).overrideWith((ref) => ReflowableLayoutMode.paginated),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              home: Scaffold(
                backgroundColor: const Color(0xFF161618),
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 1000,
                      height: 700,
                      color: const Color(0xFF1C1C1E),
                      child: PaginatedReflowableReader(
                        document: suspectXDoc,
                        initialPageIndex: 0,
                        theme: ReadingThemeType.black,
                        typography: const TypographySettings(
                          twoPageSpread: true,
                          fontSize: 16.0,
                          lineSpacing: 1.5,
                        ),
                        onTapContent: () {},
                        onProgressChanged: (_, __, ___, ____, _____) {},
                      ),
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
          'phase_2_8_4_suspect_x_chapter_opening.png',
        );

        // 1B. Dialogue-Heavy Pages (navigate forward to dialogue scene)
        final state = tester.state<PaginatedReflowableReaderState>(
          find.byType(PaginatedReflowableReader),
        );
        // Jump to page 6 (dialogue between Yasuko & Ishigami)
        state.jumpToPage(6);
        await tester.pumpAndSettle();
        await captureBoundary(
          repaintKey,
          'phase_2_8_4_suspect_x_dialogue_heavy.png',
        );

        // 1C. Ordinary Prose & Split Paragraph across Left-Right Spread
        state.jumpToPage(2);
        await tester.pumpAndSettle();
        await captureBoundary(
          repaintKey,
          'phase_2_8_4_suspect_x_split_paragraph_spread.png',
        );

        // 1D. Heading Transition
        // Jump to Chapter 2 ("DUA")
        state.jumpToChapter(2);
        await tester.pumpAndSettle();
        await captureBoundary(
          repaintKey,
          'phase_2_8_4_suspect_x_heading_transition.png',
        );
      },
    );

    testWidgets(
      '2. The Let Them Theory: Two-Page Spread vs Single-Page Layout',
      (tester) async {
        final repaintKey = GlobalKey();

        // 2A. Two-Page Spread Layout (1000 x 700)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reflowableLayoutModeProvider(
                'let-them',
              ).overrideWith((ref) => ReflowableLayoutMode.paginated),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.light(),
              home: Scaffold(
                backgroundColor: const Color(0xFFF2F2F7),
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 1000,
                      height: 700,
                      color: Colors.white,
                      child: PaginatedReflowableReader(
                        document: letThemDoc,
                        initialPageIndex: 2,
                        theme: ReadingThemeType.white,
                        typography: const TypographySettings(
                          twoPageSpread: true,
                          fontSize: 16.0,
                          lineSpacing: 1.5,
                        ),
                        onTapContent: () {},
                        onProgressChanged: (_, __, ___, ____, _____) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureBoundary(repaintKey, 'phase_2_8_4_let_them_spread.png');

        // 2B. Single-Page Layout (750 x 600, twoPageSpread = false)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reflowableLayoutModeProvider(
                'let-them',
              ).overrideWith((ref) => ReflowableLayoutMode.paginated),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.light(),
              home: Scaffold(
                backgroundColor: const Color(0xFFF2F2F7),
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 750,
                      height: 600,
                      color: Colors.white,
                      child: PaginatedReflowableReader(
                        document: letThemDoc,
                        initialPageIndex: 2,
                        theme: ReadingThemeType.white,
                        typography: const TypographySettings(
                          twoPageSpread: false,
                          fontSize: 16.0,
                          lineSpacing: 1.5,
                        ),
                        onTapContent: () {},
                        onProgressChanged: (_, __, ___, ____, _____) {},
                      ),
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
          'phase_2_8_4_let_them_single_page.png',
        );
      },
    );

    testWidgets(
      '3. Laut Bercerita: Scanned Document Recommendation & Original PDF Mode',
      (tester) async {
        final repaintKey = GlobalKey();
        const lautPdfPath =
            '$originalsDir/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.pdf';

        // 3A. Recommendation Banner in Reflowable mode
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: const Color(0xFF1C1C1E),
              body: Center(
                child: RepaintBoundary(
                  key: repaintKey,
                  child: Container(
                    width: 1000,
                    height: 700,
                    color: const Color(0xFF1C1C1E),
                    child: Stack(
                      children: [
                        // Underneath: Reflowable reader
                        PaginatedReflowableReader(
                          document: lautBerceritaDoc,
                          initialPageIndex: 0,
                          theme: ReadingThemeType.black,
                          typography: const TypographySettings(
                            twoPageSpread: true,
                          ),
                          onTapContent: () {},
                          onProgressChanged: (_, __, ___, ____, _____) {},
                        ),
                        // Top Quality Recommendation Banner
                        Positioned(
                          top: 12,
                          left: 20,
                          right: 20,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0xFF7F1D1D),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFFCA5A5),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Dokumen ini hasil pindaian (scan) tanpa lapisan teks lengkap. Mode PDF Asli direkomendasikan untuk kenyamanan membaca.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () {},
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF7F1D1D),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    child: const Text('Buka PDF Asli'),
                                  ),
                                ],
                              ),
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
          'phase_2_8_4_laut_bercerita_scanned_banner.png',
        );

        // 3B. Original PDF Reader Mode (Native PDFium)
        if (File(lautPdfPath).existsSync()) {
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: SizedBox(
                      width: 1000,
                      height: 700,
                      child: OriginalPdfReader(
                        pdfPath: lautPdfPath,
                        initialPage: 1,
                        theme: ReadingThemeType.black,
                        showControls: false,
                        onPageChanged: (_, __) {},
                        onTapContent: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          // Allow PDFium rasterizer to render pages
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          await captureBoundary(
            repaintKey,
            'phase_2_8_4_laut_bercerita_original_pdf.png',
          );
        }
      },
    );

    testWidgets('4. Viewport Dimensions & Typography Extreme Matrix', (
      tester,
    ) async {
      final repaintKey = GlobalKey();

      // Matrix of typography configurations:
      final typoConfigs = [
        (
          'phase_2_8_4_typo_font12_spacing1_2.png',
          const TypographySettings(
            fontSize: 12.0,
            lineSpacing: 1.2,
            twoPageSpread: true,
          ),
          1000.0,
          700.0,
        ),
        (
          'phase_2_8_4_typo_font19_spacing1_5.png',
          const TypographySettings(
            fontSize: 19.0,
            lineSpacing: 1.5,
            twoPageSpread: true,
          ),
          1000.0,
          700.0,
        ),
        (
          'phase_2_8_4_typo_font24_spacing1_8.png',
          const TypographySettings(
            fontSize: 24.0,
            lineSpacing: 1.8,
            twoPageSpread: true,
          ),
          1000.0,
          700.0,
        ),
        // Viewport dimensions:
        (
          'phase_2_8_4_viewport_compact_750x600.png',
          const TypographySettings(
            fontSize: 16.0,
            lineSpacing: 1.5,
            twoPageSpread: false,
          ),
          750.0,
          600.0,
        ),
        (
          'phase_2_8_4_viewport_standard_1000x700.png',
          const TypographySettings(
            fontSize: 16.0,
            lineSpacing: 1.5,
            twoPageSpread: true,
          ),
          1000.0,
          700.0,
        ),
        (
          'phase_2_8_4_viewport_expansive_1300x850.png',
          const TypographySettings(
            fontSize: 16.0,
            lineSpacing: 1.5,
            twoPageSpread: true,
          ),
          1300.0,
          850.0,
        ),
      ];

      for (final config in typoConfigs) {
        final filename = config.$1;
        final typo = config.$2;
        final w = config.$3;
        final h = config.$4;

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF1C1C1E),
              body: Center(
                child: RepaintBoundary(
                  key: repaintKey,
                  child: Container(
                    width: w,
                    height: h,
                    color: const Color(0xFF1C1C1E),
                    child: PaginatedReflowableReader(
                      document: suspectXDoc,
                      initialPageIndex: 2,
                      theme: ReadingThemeType.black,
                      typography: typo,
                      onTapContent: () {},
                      onProgressChanged: (_, __, ___, ____, _____) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureBoundary(repaintKey, filename);
      }
    });

    testWidgets(
      '5. Position & Mode Switch Regression (Paginated <-> Scrolling)',
      (tester) async {
        final repaintKey = GlobalKey();
        final containerKey = GlobalKey<ReflowableReaderContainerState>();

        // Initial Paginated
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reflowableLayoutModeProvider(
                'suspect-x',
              ).overrideWith((ref) => ReflowableLayoutMode.paginated),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: const Color(0xFF1C1C1E),
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 1000,
                      height: 700,
                      color: const Color(0xFF1C1C1E),
                      child: ReflowableReaderContainer(
                        key: containerKey,
                        bookId: 'suspect-x',
                        document: suspectXDoc,
                        initialChapterIndex: 1,
                        initialPosition: 2,
                        theme: ReadingThemeType.black,
                        typography: const TypographySettings(
                          fontSize: 16.0,
                          twoPageSpread: true,
                        ),
                        onTapContent: () {},
                        onProgressChanged: (_, __, ___, ____, _____) {},
                      ),
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
          'phase_2_8_4_regression_paginated_initial.png',
        );

        // Switch to Continuous Scrolling
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reflowableLayoutModeProvider(
                'suspect-x',
              ).overrideWith((ref) => ReflowableLayoutMode.scrolling),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: const Color(0xFF1C1C1E),
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 1000,
                      height: 700,
                      color: const Color(0xFF1C1C1E),
                      child: ReflowableReaderContainer(
                        key: containerKey,
                        bookId: 'suspect-x',
                        document: suspectXDoc,
                        initialChapterIndex: 1,
                        initialPosition: 2,
                        theme: ReadingThemeType.black,
                        typography: const TypographySettings(
                          fontSize: 16.0,
                          twoPageSpread: true,
                        ),
                        onTapContent: () {},
                        onProgressChanged: (_, __, ___, ____, _____) {},
                      ),
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
          'phase_2_8_4_regression_scrolling_mode.png',
        );

        // Switch Back to Paginated
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reflowableLayoutModeProvider(
                'suspect-x',
              ).overrideWith((ref) => ReflowableLayoutMode.paginated),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: const Color(0xFF1C1C1E),
                body: Center(
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 1000,
                      height: 700,
                      color: const Color(0xFF1C1C1E),
                      child: ReflowableReaderContainer(
                        key: containerKey,
                        bookId: 'suspect-x',
                        document: suspectXDoc,
                        initialChapterIndex: 1,
                        initialPosition: 2,
                        theme: ReadingThemeType.black,
                        typography: const TypographySettings(
                          fontSize: 16.0,
                          twoPageSpread: true,
                        ),
                        onTapContent: () {},
                        onProgressChanged: (_, __, ___, ____, _____) {},
                      ),
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
          'phase_2_8_4_regression_paginated_restored.png',
        );
      },
    );
  });
}
