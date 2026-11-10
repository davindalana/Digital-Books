// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3.1.2 — Long-Session Reader Stability & Memory Leak Audit', () {
    testWidgets(
      'Extended Stress Session: 100 Page Turns, 20 Resizes, 20 Typo Changes, 20 Mode Switches',
      (tester) async {
        final coldStartRssMb = ProcessInfo.currentRss / (1024 * 1024);
        double peakRssMb = coldStartRssMb;

        void checkPeak() {
          final cur = ProcessInfo.currentRss / (1024 * 1024);
          if (cur > peakRssMb) peakRssMb = cur;
        }

        // Generate a substantial multi-chapter document with 40 content nodes
        final chapters = List.generate(4, (chIdx) {
          final nodes = List.generate(15, (nIdx) {
            if (nIdx == 0) {
              return ContentNode(
                id: 'ch${chIdx}_h',
                type: ContentNodeType.heading,
                text:
                    'Bab ${chIdx + 1}: Landasan Komunikasi dan Membaca Reflowable',
                level: 1,
                sourcePdfPage: chIdx * 5 + 1,
              );
            } else if (nIdx == 4) {
              return ContentNode(
                id: 'ch${chIdx}_s',
                type: ContentNodeType.sectionHeading,
                text: 'Pasal $nIdx.1 Kaidah Tipografi dan Keterbacaan Layar',
                level: 2,
                sourcePdfPage: chIdx * 5 + 2,
              );
            } else if (nIdx % 5 == 0) {
              return ContentNode(
                id: 'ch${chIdx}_list_$nIdx',
                type: ContentNodeType.orderedList,
                text:
                    '$nIdx. Prinsip penyusunan kalimat yang efisien dan tidak melelahkan mata saat dibaca berulang.',
                sourcePdfPage: chIdx * 5 + 3,
              );
            } else {
              return ContentNode(
                id: 'ch${chIdx}_p_$nIdx',
                type: ContentNodeType.paragraph,
                text:
                    'Ini adalah paragraf substansial dalam bab ${chIdx + 1} nomor node $nIdx yang berisi beberapa kalimat panjang. '
                    'Sistem reflowable membaca harus mampu melakukan paginasi teks secara responsif tanpa meninggalkan orphan heading, '
                    'tanpa terjadi memory leak pada cache bitmap atau widget tree, dan mempertahankan koordinat pembacaan.',
                sourcePdfPage: chIdx * 5 + (nIdx ~/ 3) + 1,
              );
            }
          });

          return ReaderChapter(
            id: 'ch_$chIdx',
            index: chIdx,
            title: 'Bab ${chIdx + 1}',
            nodes: nodes,
          );
        });

        final testDoc = ReaderDocument(
          bookId: 'stress_test_doc',
          title: 'Buku Uji Stabilitas Jangka Panjang',
          author: 'QA Engineering Team',
          totalPages: 20,
          chapters: chapters,
        );

        final containerKey = GlobalKey<ReflowableReaderContainerState>();
        var currentTypo = const TypographySettings(
          fontSize: 18.0,
          lineSpacing: 1.6,
          paragraphSpacing: 14.0,
        );
        var currentSize = const Size(1000, 800);
        var currentTheme = ReadingThemeType.white;
        String? activeAnchor = 'ch0_p_1';

        // Build initial widget
        final container = ProviderContainer();
        addTearDown(container.dispose);

        Widget buildTestHarness() {
          return UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: currentSize.width,
                  height: currentSize.height,
                  child: ReflowableReaderContainer(
                    key: containerKey,
                    bookId: 'stress_test_doc',
                    document: testDoc,
                    initialAnchorNodeId: activeAnchor,
                    typography: currentTypo,
                    theme: currentTheme,
                    onTapContent: () {},
                    onProgressChanged: (ch, pos, pct, anchor, off) {
                      activeAnchor = anchor;
                    },
                  ),
                ),
              ),
            ),
          );
        }

        await tester.binding.setSurfaceSize(currentSize);
        await tester.pumpWidget(buildTestHarness());
        await tester.pump();

        // Initial steady-state base RSS after cold startup
        final initialRssMb = ProcessInfo.currentRss / (1024 * 1024);
        peakRssMb = initialRssMb;

        // -----------------------------------------------------------------------
        // STRESS CYCLE 1: 100 Rapid Page Turns (Pagination & Slicing Cache)
        // -----------------------------------------------------------------------
        print(
          '\n================================================================================',
        );
        print('PHASE 3.1.2: LONG-SESSION STABILITY & MEMORY LEAK STRESS AUDIT');
        print(
          '================================================================================',
        );
        print('Cold Process RSS:   ${coldStartRssMb.toStringAsFixed(2)} MB');
        print('Initial Base RSS:   ${initialRssMb.toStringAsFixed(2)} MB');

        final swTurns = Stopwatch()..start();
        for (int i = 0; i < 100; i++) {
          if (i % 2 == 0) {
            // Tap right margin for next page
            await tester.tapAt(
              Offset(currentSize.width - 25, currentSize.height / 2),
            );
          } else {
            // Tap left margin for previous page
            await tester.tapAt(Offset(25, currentSize.height / 2));
          }
          await tester.pump();
          if (i % 10 == 0) checkPeak();
        }
        swTurns.stop();
        checkPeak();
        final rssAfterTurns = ProcessInfo.currentRss / (1024 * 1024);
        print(
          '  ✓ Executed 100 rapid page turns in ${swTurns.elapsedMilliseconds} ms (${(swTurns.elapsedMilliseconds / 100).toStringAsFixed(1)} ms/turn) [RSS: ${rssAfterTurns.toStringAsFixed(2)} MB]',
        );

        // -----------------------------------------------------------------------
        // STRESS CYCLE 2: 20 Responsive Window Resize Cycles
        // -----------------------------------------------------------------------
        final swResize = Stopwatch()..start();
        final viewports = [
          const Size(400, 700), // Compact Mobile / Narrow Window
          const Size(1000, 800), // Standard Desktop
          const Size(1400, 900), // Two-Page Spread / Expansive
        ];

        for (int i = 0; i < 20; i++) {
          currentSize = viewports[i % viewports.length];
          await tester.binding.setSurfaceSize(currentSize);
          await tester.pumpWidget(buildTestHarness());
          await tester.pump();
          checkPeak();
        }
        swResize.stop();
        final rssAfterResize = ProcessInfo.currentRss / (1024 * 1024);
        print(
          '  ✓ Executed 20 window resize cycles across 3 viewports in ${swResize.elapsedMilliseconds} ms [RSS: ${rssAfterResize.toStringAsFixed(2)} MB]',
        );

        // -----------------------------------------------------------------------
        // STRESS CYCLE 3: 20 Dynamic Typography Changes
        // -----------------------------------------------------------------------
        final swTypo = Stopwatch()..start();
        final fontSizes = [14.0, 18.0, 24.0];
        final lineSpacings = [1.3, 1.6, 2.0];

        for (int i = 0; i < 20; i++) {
          currentTypo = TypographySettings(
            fontSize: fontSizes[i % fontSizes.length],
            lineSpacing: lineSpacings[i % lineSpacings.length],
            paragraphSpacing: 12.0 + (i % 3) * 4.0,
          );
          await tester.pumpWidget(buildTestHarness());
          await tester.pump();
          checkPeak();
        }
        swTypo.stop();
        final rssAfterTypo = ProcessInfo.currentRss / (1024 * 1024);
        print(
          '  ✓ Executed 20 dynamic typography adjustments in ${swTypo.elapsedMilliseconds} ms [RSS: ${rssAfterTypo.toStringAsFixed(2)} MB]',
        );

        // -----------------------------------------------------------------------
        // STRESS CYCLE 4: 20 Bi-directional Mode Switches (PDF <-> Reflowable)
        // -----------------------------------------------------------------------
        final swMode = Stopwatch()..start();
        for (int i = 0; i < 20; i++) {
          // Toggle simulated PDF citation to Reflowable node mapping
          final targetPdfPage = (i % 4) * 5 + 1;
          // Find node matching targetPdfPage
          final matchedNode = chapters
              .expand((c) => c.nodes)
              .firstWhere(
                (n) => n.sourcePdfPage == targetPdfPage,
                orElse: () => chapters.first.nodes.first,
              );
          activeAnchor = matchedNode.id;

          await tester.pumpWidget(buildTestHarness());
          await tester.pump();
          checkPeak();
        }
        swMode.stop();
        final rssAfterMode = ProcessInfo.currentRss / (1024 * 1024);
        print(
          '  ✓ Executed 20 bi-directional mode anchor syncs in ${swMode.elapsedMilliseconds} ms [RSS: ${rssAfterMode.toStringAsFixed(2)} MB]',
        );

        // Allow event loop to settle
        await tester.pump(const Duration(milliseconds: 100));

        final finalRssMb = ProcessInfo.currentRss / (1024 * 1024);
        final deltaRssMb = finalRssMb - initialRssMb;
        final peakDeltaMb = peakRssMb - initialRssMb;

        print('-' * 80);
        print('LONG-SESSION MEMORY METRICS:');
        print('  - Initial RSS:       ${initialRssMb.toStringAsFixed(2)} MB');
        print(
          '  - Peak RSS:          ${peakRssMb.toStringAsFixed(2)} MB (+${peakDeltaMb.toStringAsFixed(2)} MB)',
        );
        print(
          '  - Final Settle RSS:  ${finalRssMb.toStringAsFixed(2)} MB (+${deltaRssMb.toStringAsFixed(2)} MB)',
        );
        print('=' * 80 + '\n');

        // Assertions: Memory must remain strictly bounded with no runaway leak
        expect(
          deltaRssMb,
          lessThan(75.0),
          reason:
              'Net RSS growth after 160 stress cycles must remain strictly under 75 MB',
        );
        expect(
          peakDeltaMb,
          lessThan(95.0),
          reason: 'Peak RSS surge must remain under 95 MB',
        );
      },
    );
  });
}
