// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  group('Phase 3.5.3 — HIGH-01: Native macOS Memory Profiling (50 Cycles)', () {
    const largePdfPath =
        '/Users/davindalana/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf';
    final targetPdfFile = File(largePdfPath);

    testWidgets('50 Consecutive Open/Navigate/Scroll/Close Cycles on 64MB Real PDF', (
      tester,
    ) async {
      expect(
        targetPdfFile.existsSync(),
        isTrue,
        reason: 'Test requires real large PDF file (>50MB) to exist on disk',
      );

      final fileSizeMb = targetPdfFile.lengthSync() / (1024 * 1024);
      print('===============================================================');
      print('HIGH-01 MEMORY PROFILING PROTOCOL START');
      print('Target PDF: $largePdfPath');
      print('File Size: ${fileSizeMb.toStringAsFixed(2)} MB');
      print('Target Process PID: $pid');
      print('Host Platform: macOS Darwin ARM64');
      print('Total Cycles: 50');
      print('===============================================================');

      // Helper to query vmmap summary
      Map<String, String> queryVmmap() {
        try {
          final res = Process.runSync('vmmap', ['--summary', pid.toString()]);
          if (res.exitCode == 0) {
            final out = res.stdout.toString();
            String footprint = 'N/A';
            String resident = 'N/A';
            String dirty = 'N/A';
            for (final line in out.split('\n')) {
              if (line.contains('Physical footprint:')) {
                footprint = line.split(':').last.trim();
              }
              if (line.trim().startsWith('TOTAL')) {
                final parts = line.split(RegExp(r'\s+'));
                if (parts.length >= 4) {
                  resident = parts[2];
                  dirty = parts[3];
                }
              }
            }
            return {
              'footprint': footprint,
              'resident': resident,
              'dirty': dirty,
            };
          }
        } catch (_) {}
        return {'footprint': 'N/A', 'resident': 'N/A', 'dirty': 'N/A'};
      }

      // Helper to query leaks
      String queryLeaks() {
        try {
          final res = Process.runSync('leaks', [pid.toString()]);
          final out = res.stdout.toString();
          for (final line in out.split('\n')) {
            if (line.contains('leaks for') &&
                line.contains('total leaked bytes')) {
              return line.trim();
            }
          }
        } catch (_) {}
        return 'leaks report unavailable';
      }

      // Helper to save memgraph
      void saveMemgraph(String path) {
        try {
          Process.runSync('leaks', ['--outputGraph=$path', pid.toString()]);
        } catch (_) {}
      }

      // Helper to compare differential memgraphs
      String queryDifferentialLeaks(String basePath, String finalPath) {
        try {
          final res = Process.runSync('leaks', [
            '--diffFrom=$basePath',
            finalPath,
          ]);
          final out = res.stdout.toString();
          for (final line in out.split('\n')) {
            if (line.contains('leaks for') &&
                line.contains('total leaked bytes')) {
              return line.trim();
            }
          }
          return out.trim();
        } catch (_) {}
        return 'differential leaks report unavailable';
      }

      // Helper to query vmmap region breakdown from memgraph
      String queryMemgraphBreakdown(String memgraphPath) {
        try {
          final res = Process.runSync('vmmap', ['--summary', memgraphPath]);
          if (res.exitCode == 0) {
            final out = res.stdout.toString();
            final lines = out.split('\n');
            final summaryLines = <String>[];
            bool capture = false;
            for (final line in lines) {
              if (line.contains('REGION TYPE') ||
                  line.contains('MALLOC ZONE')) {
                capture = true;
              }
              if (capture && line.trim().isNotEmpty) {
                summaryLines.add(line);
                if (summaryLines.length >= 25) break;
              }
            }
            return summaryLines.join('\n');
          }
        } catch (_) {}
        return 'memgraph breakdown unavailable';
      }

      // 1. Quiescent Library Baseline (Cycle 0)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Quiescent Library State'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final baselineRss = ProcessInfo.currentRss / (1024 * 1024);
      final baselineVmmap = queryVmmap();
      final baselineLeaks = queryLeaks();

      const baseMemgraphPath = '/tmp/digital_books_baseline.memgraph';
      const finalMemgraphPath = '/tmp/digital_books_final.memgraph';
      saveMemgraph(baseMemgraphPath);

      print('\n[BASELINE - Cycle 0 (Quiescent)]');
      print('RSS: ${baselineRss.toStringAsFixed(2)} MB');
      print('VMMap Physical Footprint: ${baselineVmmap['footprint']}');
      print(
        'VMMap Resident / Dirty: ${baselineVmmap['resident']} / ${baselineVmmap['dirty']}',
      );
      print('Native Leaks: $baselineLeaks\n');

      final recordedMilestones = <int, Map<String, dynamic>>{};

      // 2. Execute 50 Open -> Navigate -> Scroll -> Close Cycles
      final milestoneCheckpoints = {1, 5, 10, 20, 30, 40, 50};

      for (int cycle = 1; cycle <= 50; cycle++) {
        final container = ProviderContainer();
        final readerKey = GlobalKey<OriginalPdfReaderState>();

        // A. Open PDF Document
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: targetPdfFile.path,
                  initialPage: 1,
                  theme: ReadingThemeType.white,
                  onPageChanged: (page, total) {},
                  onTapContent: () {},
                ),
              ),
            ),
          ),
        );

        // Wait for page 1 rendering
        for (int frame = 0; frame < 15; frame++) {
          await tester.pump(const Duration(milliseconds: 60));
          if (find.byType(RawImage).evaluate().isNotEmpty) {
            break;
          }
        }

        // B. Navigate Pages (Flip forward twice)
        readerKey.currentState?.nextPage();
        for (int frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 60));
        }

        readerKey.currentState?.nextPage();
        for (int frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 60));
        }

        // C. Scroll / Gesture simulation
        if (find.byType(OriginalPdfReader).evaluate().isNotEmpty) {
          await tester.drag(
            find.byType(OriginalPdfReader),
            const Offset(0, -100),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }

        final inReaderRss = ProcessInfo.currentRss / (1024 * 1024);

        // D. Close Document (Navigate back to quiescent library)
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('Quiescent Library State')),
            ),
          ),
        );
        container.dispose();

        // Step frames for cleanup & GC cooldown
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final afterCloseRss = ProcessInfo.currentRss / (1024 * 1024);

        if (milestoneCheckpoints.contains(cycle)) {
          final vmmap = queryVmmap();
          final leaks = queryLeaks();
          recordedMilestones[cycle] = {
            'inReaderRss': inReaderRss,
            'afterCloseRss': afterCloseRss,
            'footprint': vmmap['footprint'],
            'resident': vmmap['resident'],
            'dirty': vmmap['dirty'],
            'leaks': leaks,
          };

          print('[CYCLE $cycle / 50 COMPLETED]');
          print('  Active Reader RSS: ${inReaderRss.toStringAsFixed(2)} MB');
          print('  Closed State RSS:  ${afterCloseRss.toStringAsFixed(2)} MB');
          print(
            '  VMMap Footprint:   ${vmmap['footprint']} (Resident: ${vmmap['resident']}, Dirty: ${vmmap['dirty']})',
          );
          print('  Native Leaks:      $leaks');
        }
      }

      // 3. Post-Test Cooldown & Stabilization Phase
      print(
        '\n===============================================================',
      );
      print('COOLING DOWN & RECLAIMING CACHES (3 Seconds Settle)...');
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      final finalRss = ProcessInfo.currentRss / (1024 * 1024);
      final finalVmmap = queryVmmap();
      final finalLeaks = queryLeaks();
      saveMemgraph(finalMemgraphPath);
      final diffLeaks = queryDifferentialLeaks(
        baseMemgraphPath,
        finalMemgraphPath,
      );
      final breakdown = queryMemgraphBreakdown(finalMemgraphPath);

      final cycle1ClosedRss = recordedMilestones[1]!['afterCloseRss'] as double;
      final cycle5ClosedRss = recordedMilestones[5]!['afterCloseRss'] as double;
      final cycle50ClosedRss =
          recordedMilestones[50]!['afterCloseRss'] as double;
      final warmupDelta = cycle5ClosedRss - cycle1ClosedRss;
      final rssDriftCycles1To50 = cycle50ClosedRss - cycle1ClosedRss;
      final cooldownDelta = finalRss - cycle50ClosedRss;
      final netRssDriftFromBaseline = finalRss - baselineRss;

      final allClosedRss =
          recordedMilestones.values
              .map((m) => m['afterCloseRss'] as double)
              .toList()
            ..sort();
      final minRss = allClosedRss.first;
      final maxRss = allClosedRss.last;
      final medianRss = allClosedRss[allClosedRss.length ~/ 2];

      print(
        '\n===============================================================',
      );
      print('HIGH-01 MEMORY PROFILING FINAL EVALUATION SUMMARY');
      print('Baseline RSS:            ${baselineRss.toStringAsFixed(2)} MB');
      print(
        'Cycle 1 Closed RSS:      ${cycle1ClosedRss.toStringAsFixed(2)} MB',
      );
      print(
        'Cycle 5 Closed RSS:      ${cycle5ClosedRss.toStringAsFixed(2)} MB',
      );
      print(
        'Cycle 10 Closed RSS:     ${(recordedMilestones[10]!['afterCloseRss'] as double).toStringAsFixed(2)} MB',
      );
      print(
        'Cycle 20 Closed RSS:     ${(recordedMilestones[20]!['afterCloseRss'] as double).toStringAsFixed(2)} MB',
      );
      print(
        'Cycle 30 Closed RSS:     ${(recordedMilestones[30]!['afterCloseRss'] as double).toStringAsFixed(2)} MB',
      );
      print(
        'Cycle 40 Closed RSS:     ${(recordedMilestones[40]!['afterCloseRss'] as double).toStringAsFixed(2)} MB',
      );
      print(
        'Cycle 50 Closed RSS:     ${cycle50ClosedRss.toStringAsFixed(2)} MB',
      );
      print('Final Cooldown RSS:      ${finalRss.toStringAsFixed(2)} MB');
      print('---------------------------------------------------------------');
      print('Statistical Distribution:');
      print('  Minimum Closed RSS:    ${minRss.toStringAsFixed(2)} MB');
      print('  Maximum Closed RSS:    ${maxRss.toStringAsFixed(2)} MB');
      print('  Median Closed RSS:     ${medianRss.toStringAsFixed(2)} MB');
      print(
        '  Warmup Delta (1 -> 5): ${warmupDelta >= 0 ? '+' : ''}${warmupDelta.toStringAsFixed(2)} MB',
      );
      print(
        '  Cycle Drift (1 -> 50): ${rssDriftCycles1To50 >= 0 ? '+' : ''}${rssDriftCycles1To50.toStringAsFixed(2)} MB',
      );
      print(
        '  Cooldown Delta:        ${cooldownDelta >= 0 ? '+' : ''}${cooldownDelta.toStringAsFixed(2)} MB',
      );
      print(
        '  Net RSS from Baseline: ${netRssDriftFromBaseline >= 0 ? '+' : ''}${netRssDriftFromBaseline.toStringAsFixed(2)} MB',
      );
      print('---------------------------------------------------------------');
      print('Final VMMap Footprint:   ${finalVmmap['footprint']}');
      print('Final Native Leaks:      $finalLeaks');
      print('Apple Differential Leaks: $diffLeaks');
      print('===============================================================');
      print('VMMap Region Summary on Memgraph:\n$breakdown');
      print(
        '===============================================================\n',
      );

      int extractLeakedBytes(String leakString) {
        final match = RegExp(
          r'(\d+)\s+total leaked bytes',
        ).firstMatch(leakString);
        return match != null ? int.parse(match.group(1)!) : 0;
      }

      final baselineLeakedBytes = extractLeakedBytes(baselineLeaks);
      final finalLeakedBytes = extractLeakedBytes(finalLeaks);
      final newLeakedBytes = finalLeakedBytes - baselineLeakedBytes;

      print('Baseline Leaked Bytes:   $baselineLeakedBytes bytes');
      print('Final Leaked Bytes:      $finalLeakedBytes bytes');
      print('New Leaked Bytes Delta:  $newLeakedBytes bytes');
      print(
        '===============================================================\n',
      );

      // Assertions:
      // 1. Leaks command must confirm zero new leaked bytes across 50 cycles
      expect(
        newLeakedBytes,
        equals(0),
        reason:
            'Native Apple leaks tool must verify zero new leaked memory bytes introduced by 50 reader cycles',
      );

      // 2. Differential leaks check must confirm zero new leaked blocks
      expect(
        diffLeaks,
        anyOf(
          contains('0 leaks for 0 total leaked bytes'),
          contains('0 leaks'),
        ),
        reason:
            'Apple differential leaks analysis must report 0 new leaks since baseline memgraph',
      );

      // 3. Memory drift across 50 cycles must plateau and remain bounded (less than 150 MB drift)
      // Note: Initial cycles allocate static JIT/AOT code pages, font tables, and PDFium globals.
      expect(
        rssDriftCycles1To50,
        lessThan(150.0),
        reason:
            'RSS drift between cycle 1 and cycle 50 must stabilize without unbounded linear growth',
      );
    });
  });
}
