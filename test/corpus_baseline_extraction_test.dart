// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('Phase 2.7 Baseline Extraction on Representative Corpus', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final corpusDir = Directory('test/fixtures/corpus');
    expect(corpusDir.existsSync(), isTrue);

    final files = corpusDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    print('\n===============================================================');
    print('PHASE 2.7 BASELINE EXTRACTION REPORT (CURRENT IMPLEMENTATION)');
    print('Method: PdfTextExtractor.extractText() [Flattened Plain Text]');
    print('===============================================================\n');

    final baselineResults = <String, Map<String, dynamic>>{};

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final bytes = await file.readAsBytes();

      final sw = Stopwatch()..start();
      final doc = PdfDocument(inputBytes: bytes);
      final totalPages = doc.pages.count;
      final extractor = PdfTextExtractor(doc);

      final List<String> pageTexts = [];
      for (int i = 0; i < totalPages; i++) {
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        pageTexts.add(text);
      }
      sw.stop();

      final totalChars = pageTexts.fold(0, (sum, t) => sum + t.length);
      final hasText = totalChars > 20;

      // Check specific baseline failure modes:
      // 1. Two-column reading order: Does "Abstract" interleave with "II. METHODOLOGY"?
      bool readingOrderCorrupted = false;
      if (name.contains('04_two_column')) {
        final fullText = pageTexts.join('\n');
        final abstractIdx = fullText.indexOf('Abstract');
        final introIdx = fullText.indexOf('I. INTRODUCTION');
        final methodIdx = fullText.indexOf('II. METHODOLOGY');
        // Correct reading order: Abstract -> Intro -> Methodology -> Results
        // Corrupted order: Abstract -> Methodology -> Intro -> Results (top-to-bottom horizontal interleaving)
        if (abstractIdx != -1 && methodIdx != -1 && introIdx != -1) {
          if (methodIdx < introIdx) {
            readingOrderCorrupted = true;
          }
        }
      }

      // 2. Images missing? (Current pipeline extracts 0 images)
      bool imagesMissing = false;
      if (name.contains('illustrated') ||
          name.contains('diagrams') ||
          name.contains('hybrid') ||
          name.contains('scanned')) {
        imagesMissing = true; // Current pipeline does not extract images
      }

      // 3. Headers and footers stripped?
      bool headersContaminating = false;
      if (name.contains('05_headers_footers')) {
        final fullText = pageTexts.join('\n');
        if (fullText.contains('THE ADVENTURES OF SHERLOCK HOLMES') ||
            fullText.contains('Page 1 of 3')) {
          headersContaminating = true;
        }
      }

      print('[$name]');
      print(
        '• Pages: $totalPages | Total Chars: $totalChars | Duration: ${sw.elapsedMicroseconds / 1000.0} ms',
      );
      print('• Reading order corrupted: $readingOrderCorrupted');
      print('• Images missing: $imagesMissing');
      print('• Header/Footer contaminated: $headersContaminating');
      print(
        '• Sample text snippet: ${pageTexts.first.replaceAll('\n', ' ').trim().take(80)}...',
      );
      print('---------------------------------------------------------------');

      baselineResults[name] = {
        'pages': totalPages,
        'chars': totalChars,
        'hasText': hasText,
        'durationMs': sw.elapsedMicroseconds / 1000.0,
        'readingOrderCorrupted': readingOrderCorrupted,
        'imagesMissing': imagesMissing,
        'headersContaminating': headersContaminating,
      };

      doc.dispose();
    }

    expect(baselineResults.length, equals(10));
    print(
      '\nBaseline measurement completed across all 10 corpus categories.\n',
    );
  });
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
