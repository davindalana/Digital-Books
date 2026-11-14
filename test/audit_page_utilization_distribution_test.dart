// ignore_for_file: avoid_print, unused_import
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';
import 'package:path/path.dart' as p;
import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.8.4 — Comprehensive Page Utilization Audit', () {
    ReaderDocument? suspectXDoc;
    ReaderDocument? letThemDoc;

    final suspectXFile = File(
      p.join(RealBookFixtures.booksDir, '67141617-5a74-4f9b-a9fa-45b28366e27d.json'),
    );
    final letThemFile = File(
      p.join(RealBookFixtures.booksDir, '8cda23f0-bf42-4a4d-a1fd-30d2943835c9.json'),
    );

    setUpAll(() async {
      if (!checkFixtureOrSkip(suspectXFile) || !checkFixtureOrSkip(letThemFile)) return;
      if (suspectXFile.existsSync()) {
        final json =
            jsonDecode(await suspectXFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        suspectXDoc = ReflowableEngine.normalizeDocument(normDoc);
      }

      if (letThemFile.existsSync()) {
        final json =
            jsonDecode(await letThemFile.readAsString())
                as Map<String, dynamic>;
        final rawDoc = BookDocument.fromJson(json);
        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        letThemDoc = ReflowableEngine.normalizeDocument(normDoc);
      }
    });

    test('Audit Page Utilization Distribution Across Categories and Books', () {
      if (!checkFixtureOrSkip(suspectXFile) || !checkFixtureOrSkip(letThemFile)) return;
      final books = [suspectXDoc, letThemDoc].whereType<ReaderDocument>().toList();
      if (books.length < 2) return;
      const typo = TypographySettings(twoPageSpread: true);
      const viewportWidth = 1000.0;
      const viewportHeight = 600.0;
      const availableHeight = 500.0; // 600 - 48 - 28 - 24
      const contentWidth = 380.0; // (1000 - 48)/2 = 476; 476 - 96 = 380

      for (final bookDoc in books) {
        print(
          '\n===============================================================',
        );
        print('PAGE UTILIZATION AUDIT: ${bookDoc.title}');
        print(
          '===============================================================',
        );

        final pages = PaginationEngine.paginateDocument(
          document: bookDoc,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
          typography: typo,
        );

        // Buckets for different page categories
        final Map<String, List<double>> categoryUtilizations = {
          'Ordinary Prose': [],
          'Chapter Openings': [],
          'Pages with Headings': [],
          'Dialogue-Heavy': [],
          'Pages with Images': [],
          'Pages with Footnotes': [],
          'Intentional Breaks / Terminal': [],
        };

        final Map<String, List<double>> widgetHeightUtilizations = {
          'Ordinary Prose': [],
          'Chapter Openings': [],
          'Pages with Headings': [],
          'Dialogue-Heavy': [],
          'Pages with Images': [],
          'Pages with Footnotes': [],
          'Intentional Breaks / Terminal': [],
        };

        // Classify each page
        for (int i = 0; i < pages.length; i++) {
          final p = pages[i];
          final isChapterOpening = p.pageIndexInChapter == 0;
          final isTerminalPage =
              i == pages.length - 1 ||
              (i < pages.length - 1 && pages[i + 1].pageIndexInChapter == 0);

          bool hasHeading = false;
          bool hasImage = false;
          bool hasFootnote = false;
          int dialogueLines = 0;
          int totalLines = 0;

          double engineEstimatedHeight = 0;
          double widgetRenderedHeight = 0;

          for (final s in p.slices) {
            if (s.node.type == ContentNodeType.heading) hasHeading = true;
            if (s.node.type == ContentNodeType.image) hasImage = true;
            if (s.node.type == ContentNodeType.footnote) hasFootnote = true;

            final style = s.node.type == ContentNodeType.heading
                ? typo.headingStyle(level: s.node.level)
                : (s.node.type == ContentNodeType.quote
                      ? typo.quoteStyle()
                      : (s.node.type == ContentNodeType.footnote
                            ? typo.bodyStyle().copyWith(
                                fontSize: typo.fontSize * 0.85,
                              )
                            : typo.bodyStyle()));

            final nodePadding = s.node.type == ContentNodeType.footnote
                ? (4.0 + (typo.paragraphSpacing * 0.6))
                : (s.node.type == ContentNodeType.quote
                      ? (8.0 + typo.paragraphSpacing)
                      : (s.node.type == ContentNodeType.heading
                            ? (8.0 + (typo.paragraphSpacing * 1.2))
                            : typo.paragraphSpacing));

            if (s.node.type == ContentNodeType.image) {
              const imgH = 220.0 + 28.0 + 12.0;
              engineEstimatedHeight += imgH;
              widgetRenderedHeight += imgH;
            } else {
              final tp = TextPainter(
                text: TextSpan(text: s.textSlice, style: style),
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: contentWidth);

              final lines = tp.computeLineMetrics();
              totalLines += lines.length;

              // Check dialogue lines
              final text = s.textSlice.trim();
              if (text.startsWith('"') ||
                  text.startsWith('“') ||
                  text.startsWith('”') ||
                  text.startsWith('-') ||
                  text.startsWith('「')) {
                dialogueLines += lines.length;
              }

              engineEstimatedHeight += tp.height + nodePadding;
              widgetRenderedHeight += tp.height + nodePadding;
              tp.dispose();
            }
          }

          final isDialogueHeavy =
              totalLines > 0 && (dialogueLines / totalLines) >= 0.5;

          final engineUtil = engineEstimatedHeight / availableHeight;
          final widgetUtil = widgetRenderedHeight / availableHeight;

          // Categorize page (mutually exclusive primary category for clean breakdown)
          String cat;
          if (isTerminalPage) {
            cat = 'Intentional Breaks / Terminal';
          } else if (isChapterOpening) {
            cat = 'Chapter Openings';
          } else if (hasHeading) {
            cat = 'Pages with Headings';
          } else if (hasImage) {
            cat = 'Pages with Images';
          } else if (hasFootnote) {
            cat = 'Pages with Footnotes';
          } else if (isDialogueHeavy) {
            cat = 'Dialogue-Heavy';
          } else {
            cat = 'Ordinary Prose';
          }

          categoryUtilizations[cat]!.add(engineUtil);
          widgetHeightUtilizations[cat]!.add(widgetUtil);
        }

        print(
          'Total Pages: ${pages.length} | Available Height: ${availableHeight.toStringAsFixed(1)} pt | Content Width: ${contentWidth.toStringAsFixed(1)} pt\n',
        );
        print(
          String.fromCharCodes(Iterable.generate(95, (_) => 45)),
        ); // '-' * 95
        print(
          'Category                        | Count | Min    | P10    | Median | P90    | Max    | Mean  ',
        );
        print(String.fromCharCodes(Iterable.generate(95, (_) => 45)));

        for (final entry in categoryUtilizations.entries) {
          final cat = entry.key;
          final values = entry.value;
          if (values.isEmpty) {
            print(
              '${cat.padRight(31)} |     0 |    N/A |    N/A |    N/A |    N/A |    N/A |    N/A',
            );
            continue;
          }

          values.sort();
          final count = values.length;
          final min = values.first * 100;
          final max = values.last * 100;
          final p10 = values[(count * 0.10).floor().clamp(0, count - 1)] * 100;
          final median =
              values[(count * 0.50).floor().clamp(0, count - 1)] * 100;
          final p90 = values[(count * 0.90).floor().clamp(0, count - 1)] * 100;
          final mean = (values.reduce((a, b) => a + b) / count) * 100;

          print(
            '${cat.padRight(31)} | ${count.toString().padLeft(5)} | ${min.toStringAsFixed(1).padLeft(5)}% | ${p10.toStringAsFixed(1).padLeft(5)}% | ${median.toStringAsFixed(1).padLeft(5)}% | ${p90.toStringAsFixed(1).padLeft(5)}% | ${max.toStringAsFixed(1).padLeft(5)}% | ${mean.toStringAsFixed(1).padLeft(5)}%',
          );
        }
        print(String.fromCharCodes(Iterable.generate(95, (_) => 45)));

        // Overall across non-terminal vs terminal
        final allNonTerminal =
            categoryUtilizations.entries
                .where((e) => e.key != 'Intentional Breaks / Terminal')
                .expand((e) => e.value)
                .toList()
              ..sort();

        if (allNonTerminal.isNotEmpty) {
          final count = allNonTerminal.length;
          final min = allNonTerminal.first * 100;
          final max = allNonTerminal.last * 100;
          final p10 =
              allNonTerminal[(count * 0.10).floor().clamp(0, count - 1)] * 100;
          final median =
              allNonTerminal[(count * 0.50).floor().clamp(0, count - 1)] * 100;
          final p90 =
              allNonTerminal[(count * 0.90).floor().clamp(0, count - 1)] * 100;
          final mean = (allNonTerminal.reduce((a, b) => a + b) / count) * 100;
          print(
            '${"ALL NON-TERMINAL PAGES".padRight(31)} | ${count.toString().padLeft(5)} | ${min.toStringAsFixed(1).padLeft(5)}% | ${p10.toStringAsFixed(1).padLeft(5)}% | ${median.toStringAsFixed(1).padLeft(5)}% | ${p90.toStringAsFixed(1).padLeft(5)}% | ${max.toStringAsFixed(1).padLeft(5)}% | ${mean.toStringAsFixed(1).padLeft(5)}%',
          );
        }

        final allPages = categoryUtilizations.values.expand((e) => e).toList()
          ..sort();
        if (allPages.isNotEmpty) {
          final count = allPages.length;
          final min = allPages.first * 100;
          final max = allPages.last * 100;
          final p10 =
              allPages[(count * 0.10).floor().clamp(0, count - 1)] * 100;
          final median =
              allPages[(count * 0.50).floor().clamp(0, count - 1)] * 100;
          final p90 =
              allPages[(count * 0.90).floor().clamp(0, count - 1)] * 100;
          final mean = (allPages.reduce((a, b) => a + b) / count) * 100;
          print(
            '${"ALL PAGES (INCL. TERMINAL)".padRight(31)} | ${count.toString().padLeft(5)} | ${min.toStringAsFixed(1).padLeft(5)}% | ${p10.toStringAsFixed(1).padLeft(5)}% | ${median.toStringAsFixed(1).padLeft(5)}% | ${p90.toStringAsFixed(1).padLeft(5)}% | ${max.toStringAsFixed(1).padLeft(5)}% | ${mean.toStringAsFixed(1).padLeft(5)}%',
          );
        }
        print(String.fromCharCodes(Iterable.generate(95, (_) => 45)));
      }
    });
  });
}
