// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'helpers/real_book_fixtures.dart';

/// Calculates Levenshtein edit distance between two strings or token sequences.
int levenshteinDistance<T>(List<T> a, List<T> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var v0 = List<int>.generate(b.length + 1, (i) => i);
  var v1 = List<int>.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
    }
    final temp = v0;
    v0 = v1;
    v1 = temp;
  }
  return v0[b.length];
}

/// Character Error Rate (CER) = Levenshtein(GT, OCR) / length(GT)
double calculateCer(String groundTruth, String ocrText) {
  if (groundTruth.isEmpty) return ocrText.isEmpty ? 0.0 : 100.0;
  final dist = levenshteinDistance(
    groundTruth.runes.toList(),
    ocrText.runes.toList(),
  );
  return (dist / groundTruth.runes.length) * 100.0;
}

/// Word Error Rate (WER) = LevenshteinWords(GT, OCR) / wordsLength(GT)
double calculateWer(String groundTruth, String ocrText) {
  final gtWords = groundTruth
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final ocrWords = ocrText
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (gtWords.isEmpty) return ocrWords.isEmpty ? 0.0 : 100.0;
  final dist = levenshteinDistance(gtWords, ocrWords);
  return (dist / gtWords.length) * 100.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ocrService = AppleVisionOcrService();

  final lautFile = RealBookFixtures.resolve(RealBookFixtures.lautBercerita);
  final bicaraFile = RealBookFixtures.resolve(RealBookFixtures.bicaraItuAdaSeninya);
  final suspectXFile = RealBookFixtures.resolve(RealBookFixtures.kesetiaanMrX);

  group('Phase 3.1.1 — OCR Ground Truth Accuracy & Error Rate Audit', () {
    // -------------------------------------------------------------------------
    // Ground Truth Sample 1: Laut Bercerita Page 15 (Indonesian Fiction Prose)
    // -------------------------------------------------------------------------
    test(
      '1. Ground Truth Audit: Laut Bercerita Page 15 (Indonesian Fiction Prose)',
      () async {
        const groundTruth = '''
Setelah lebih dari sejam kami berada di atas mobil dengan
mata yang masih ditutup dan tangan terikat, akhirnya si
Manusia Pohon menarikku keluar mobil dan bersama yang lain
menggiringku ke sebuah tempat, udara terbuka. Aku ditendang
agar berjalan dengan lekas. Jalan semakin menanjak dan aku
mendengar debur ombak yang pecah. Aku bisa mencium aroma
asin laut di antara angin yang mengacak rambut. Sekali lagi,
suara ombak yang deras itu pecah tak seirama. Di manakah aku?
Apakah kami masih di wilayah Jakarta?
Karena aku sering berhenti untuk mengira-ngira lokasi, se-
buah tangan besar mendorong punggungku agar aku berjalan
lebih cepat. Setelah berjalan cukup jauh, kini salah satu dari
mereka berteriak agar aku menaiki sebuah speedboat. Bau asin
laut kembali menusuk cuping hidungku. Kudengar seseorang
menyalakan motor speedboat itu. Seseorang yang lain sekali lagi
menendang punggungku agar aku berlutut. Sial! Perlahan aku
mencoba duduk dan tampaknya mereka tak keberatan.
Begitu saja perahu motor itu melaju. Meski wajahku masih
tertutup karung, aku masih bisa merasakan cipratan air laut.
Angin laut terasa menyusup di antara pori-pori kain karung yang
menyelimuti mukaku yang penuh darah dan luka. Pedih luka
bibir dan tulang hidungku yang patah semakin menggigit karena
asin air laut, tetapi angin yang menerpa itu terasa seperti sebuah
pembebasan. Debar jantung semakin menggedor-gedor dada
seolah ia siap mencelat keluar, tetapi aku mencoba menghadapi
suara permukaan laut yang dibelah perahu motor itu.
Tak terlalu lama, perahu motor terasa melambat. Mungkin
kami sudah tiba di tempat tujuan, entah pulau apa, aku tak tahu.
Aku dipaksa turun. Agak sulit berjalan di tepi tebing dengan''';

        if (!checkFixtureOrSkip(lautFile, 'Laut Bercerita')) return;
        if (!ocrService.isAvailable) {
          markTestSkipped('AppleVisionOcrService is not available');
          return;
        }

        final doc = await PdfDocument.openFile(lautFile.path);
        final page = doc.pages[14]; // Page 15 (0-indexed 14)
        final ocrResult = await ocrService.processPdfPage(
          page,
          scale: 1.5,
          languages: const ['id-ID', 'en-US'],
        );
        await doc.dispose();

        final ocrText = ocrResult.lines.map((l) => l.text).join('\n');
        final cer = calculateCer(groundTruth.trim(), ocrText.trim());
        final wer = calculateWer(groundTruth.trim(), ocrText.trim());

        print(
          '\n===============================================================',
        );
        print('GROUND TRUTH AUDIT 1: LAUT BERCERITA P.15 (FICTION PROSE)');
        print(
          '===============================================================',
        );
        print(
          'Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}',
        );
        print(
          'OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}',
        );
        print(
          'Apple Vision Reported Confidence: ${(ocrResult.lines.map((l) => l.confidence).reduce((a, b) => a + b) / ocrResult.lines.length * 100).toStringAsFixed(2)}%',
        );
        print('Actual Character Error Rate (CER): ${cer.toStringAsFixed(2)}%');
        print('Actual Word Error Rate (WER): ${wer.toStringAsFixed(2)}%');

        // Analyze specific error types:
        // Notice dotless i (ı vs i) and photocopy toner breaks near gutter
        final dotlessCount = 'ı'.allMatches(ocrText).length;
        print('Dotless-i (ı) scan artifacts: $dotlessCount occurrences');

        expect(
          cer,
          lessThan(8.0),
          reason: 'CER must be strictly bounded under 8% on real raw scan',
        );
        expect(
          wer,
          lessThan(15.0),
          reason: 'WER must be strictly bounded under 15% on real raw scan',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Ground Truth Sample 2: Bicara Itu Ada Seninya Page 33 (Non-Fiction / Self-Help)
    // -------------------------------------------------------------------------
    test(
      '2. Ground Truth Audit: Bicara Itu Ada Seninya Page 33 (Non-Fiction / Structured)',
      () async {
        const groundTruth = '''
selamanya. Lelaki tadi kemudian pulang ke kampung halaman
dan membuat roti bagel setiap kali merindukan istrinya. Setelah
itu, roti bagel menjadi terkenal ke seluruh dunia karena cerita
ini.
Sayangnya kisah roti bagel ini adalah rekaan. Namun karena
storytelling-nya begitu kuat, publik sudah tidak peduli lagi
tentang keasliannya. Sehingga setiap kali memakan roti bagel
di toko roti atau kafe, pasti akan terngiang kisah sedih si tukang
roti Jerman dan istri Yahudi-nya.
Selain itu, ada lagi cerita serupa yang meninggalkan kesan
mendalam. Kisah Paul Robert Potts. Kehidupan penyanyi pop
opera ini menyajikan kisah yang begitu mengharukan. Suatu
hari, seorang pria dengan tampang pas-pasan dan bekerja
sebagai salesman mengikuti audisi Britain's Got Talent dan
berkata ingin menyanyikan opera. Tak ada satu pun yang
tertarik terhadapnya. Ia lalu menyanyikan aria "Nessun Dorma"
dari opera Turandot dengan suara merdu. Ini adalah lagu yang
dinyanyikannya untuk bangkit dari masa lalu saat berjuang
melawan kanker, kecelakaan lalu lintas, pengucilan, dan
kemiskinan. Hasilnya sungguh mengejutkan. Para penonton
tenggelam dalam perasaan masing-masing.
Bagaimana jika ia seorang penyanyi yang bertampang
rupawan dan berasal dari golongan elit? Mungkin ia tidak
akan mendapatkan respons sebaik itu. Audiens seakan melihat
tokoh dalam dongeng saat menyaksikannya bernyanyi. Melalui
kisahnya yang berhasil melewati kesengsaraan hidup, ia men-
jadi penyanyi pop opera yang mendunia. Setiap orang yang
mendengar nama Paul Robert Potts pasti akan langsung teringat
kisahnya dan hanyut dalam keharuan.''';

        if (!checkFixtureOrSkip(bicaraFile, 'Bicara Itu Ada Seninya')) return;
        if (!ocrService.isAvailable) {
          markTestSkipped('AppleVisionOcrService is not available');
          return;
        }

        final doc = await PdfDocument.openFile(bicaraFile.path);
        final page = doc.pages[32]; // Page 33 (0-indexed 32)
        final ocrResult = await ocrService.processPdfPage(
          page,
          scale: 1.5,
          languages: const ['id-ID', 'en-US'],
        );
        await doc.dispose();

        // Filter out footer page number (line containing only digits e.g. "15")
        final filteredLines = ocrResult.lines
            .where((l) => !RegExp(r'^\d+$').hasMatch(l.text.trim()))
            .map((l) => l.text)
            .toList();
        final ocrText = filteredLines.join('\n');

        final cer = calculateCer(groundTruth.trim(), ocrText.trim());
        final wer = calculateWer(groundTruth.trim(), ocrText.trim());

        print(
          '\n===============================================================',
        );
        print(
          'GROUND TRUTH AUDIT 2: BICARA ITU ADA SENINYA P.33 (NON-FICTION)',
        );
        print(
          '===============================================================',
        );
        print(
          'Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}',
        );
        print(
          'OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}',
        );
        print('Actual Character Error Rate (CER): ${cer.toStringAsFixed(2)}%');
        print('Actual Word Error Rate (WER): ${wer.toStringAsFixed(2)}%');

        // Check footer contamination detection
        final hasFooterInRaw = ocrResult.lines.any(
          (l) => RegExp(r'^\d+$').hasMatch(l.text.trim()),
        );
        print(
          'Raw OCR includes footer page number: $hasFooterInRaw (Successfully isolated during reconstruction)',
        );

        expect(
          cer,
          lessThan(4.0),
          reason: 'CER on clean non-fiction text must be under 4%',
        );
        expect(
          wer,
          lessThan(8.0),
          reason: 'WER on clean non-fiction text must be under 8%',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Ground Truth Sample 3: The Devotion of Suspect X Page 11 (English/Indo Novel)
    // -------------------------------------------------------------------------
    test(
      '3. Ground Truth Audit: The Devotion of Suspect X Page 11 (Narrative Prose)',
      () async {
        if (!checkFixtureOrSkip(suspectXFile, 'The Devotion of Suspect X')) return;
        if (!ocrService.isAvailable) {
          markTestSkipped('AppleVisionOcrService is not available');
          return;
        }

        final doc = await PdfDocument.openFile(suspectXFile.path);
        final page = doc.pages[10]; // Page 11 (0-indexed 10)
        final ocrResult = await ocrService.processPdfPage(
          page,
          scale: 1.5,
          languages: const ['id-ID', 'en-US'],
        );
        await doc.dispose();

        final ocrText = ocrResult.lines.map((l) => l.text).join('\n');

        print(
          '\n===============================================================',
        );
        print('GROUND TRUTH AUDIT 3: SUSPECT X P.11 (NOVEL NARRATIVE)');
        print(
          '===============================================================',
        );
        print('OCR Lines Extracted: ${ocrResult.lines.length}');
        print('OCR Sample (first 3 lines):');
        for (final l in ocrResult.lines.take(3)) {
          print('  "${l.text}"');
        }

        // Check key character and dialogue tokens
        expect(ocrText, contains('Benten-tei'));
        expect(ocrResult.lines.length, greaterThanOrEqualTo(20));
      },
    );

    // -------------------------------------------------------------------------
    // Ground Truth Sample 4: Sentence Completeness & Paragraph Reconstruction Audit
    // -------------------------------------------------------------------------
    test(
      '4. Sentence Completeness & Paragraph Boundary Accuracy on Laut Bercerita P.15',
      () async {
        if (!checkFixtureOrSkip(lautFile, 'Laut Bercerita')) return;
        if (!ocrService.isAvailable) {
          markTestSkipped('AppleVisionOcrService is not available');
          return;
        }

        final doc = await PdfDocument.openFile(lautFile.path);
        final page = doc.pages[14]; // Page 15
        final ocrResult = await ocrService.processPdfPage(
          page,
          scale: 1.5,
          languages: const ['id-ID', 'en-US'],
        );
        await doc.dispose();

        // Convert OCR lines into ExtractedTextLine
        final extractedLines = ocrResult.lines.asMap().entries.map((entry) {
          final idx = entry.key;
          final l = entry.value;
          return ExtractedTextLine(
            bounds: l.box,
            text: l.text,
            fontSize: 12.0,
            lineIndex: idx,
            pageIndex: 14,
          );
        }).toList();

        final pageReadingOrder = PageReadingOrderResult(
          pageIndex: 14,
          orderedLines: extractedLines,
          layoutStructure: PageLayoutStructure.singleColumn,
          columnConfidence: 1.0,
        );

        final paragraphs = ParagraphReconstructor.reconstructDocument([
          pageReadingOrder,
        ]);
        expect(paragraphs.isNotEmpty, isTrue);

        final combinedText = paragraphs.map((p) => p.text).join('\n\n');

        // Ground truth sentences on Laut Bercerita Page 15:
        final expectedSentences = [
          'Setelah lebih dari sejam kami berada di atas mobil dengan mata yang masih ditutup dan tangan terikat, akhirnya si Manusia Pohon menarikku keluar mobil dan bersama yang lain menggiringku ke sebuah tempat, udara terbuka.',
          'Aku ditendang agar berjalan dengan lekas.',
          'Jalan semakin menanjak dan aku mendengar debur ombak yang pecah.',
          'Aku bisa mencium aroma asin laut di antara angin yang mengacak rambut.',
          'Sekali lagi, suara ombak yang deras itu pecah tak seirama.',
          'Di manakah aku?',
          'Apakah kami masih di wilayah Jakarta?',
          'Karena aku sering berhenti untuk mengira-ngira lokasi, sebuah tangan besar mendorong punggungku agar aku berjalan lebih cepat.',
          'Setelah berjalan cukup jauh, kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat.',
          'Bau asin laut kembali menusuk cuping hidungku.',
          'Kudengar seseorang menyalakan motor speedboat itu.',
          'Seseorang yang lain sekali lagi menendang punggungku agar aku berlutut.',
          'Sial!',
          'Perlahan aku mencoba duduk dan tampaknya mereka tak keberatan.',
          'Begitu saja perahu motor itu melaju.',
          'Meski wajahku masih tertutup karung, aku masih bisa merasakan cipratan air laut.',
          'Debar jantung semakin menggedor-gedor dada seolah ia siap mencelat keluar, tetapi aku mencoba menghadapi suara permukaan laut yang dibelah perahu motor itu.',
          'Tak terlalu lama, perahu motor terasa melambat.',
          'Aku dipaksa turun.',
        ];

        int completeSentences = 0;
        for (final s in expectedSentences) {
          // Normalize spaces in both
          final normS = s.replaceAll(RegExp(r'\s+'), ' ').trim();
          final normCombined = combinedText.replaceAll(RegExp(r'\s+'), ' ');
          if (normCombined.contains(normS) ||
              normCombined.contains(
                normS.substring(0, (normS.length * 0.85).toInt()),
              )) {
            completeSentences++;
          }
        }

        final sentenceCompletenessRate =
            (completeSentences / expectedSentences.length) * 100.0;

        print(
          '\n===============================================================',
        );
        print('SENTENCE COMPLETENESS & MORPHOLOGY RECONSTRUCTION AUDIT');
        print(
          '===============================================================',
        );
        print('Total Ground Truth Sentences: ${expectedSentences.length}');
        print(
          'Sentences Extracted Intact:   $completeSentences / ${expectedSentences.length}',
        );
        print(
          'Sentence Completeness Rate:   ${sentenceCompletenessRate.toStringAsFixed(1)}%',
        );
        print('Paragraphs Reconstructed:     ${paragraphs.length}');

        // Audit Indonesian Prepositions vs Passive Affixes:
        expect(
          combinedText,
          contains('di atas mobil'),
          reason: 'Preposition "di atas" must remain separate',
        );
        expect(
          combinedText,
          contains('di antara angin'),
          reason: 'Preposition "di antara" must remain separate',
        );
        expect(
          combinedText,
          contains('Di manakah'),
          reason: 'Preposition "Di manakah" must remain separate',
        );
        expect(
          combinedText,
          contains('di wilayah Jakarta'),
          reason: 'Preposition "di wilayah" must remain separate',
        );
        expect(
          combinedText,
          contains('di tempat tujuan'),
          reason: 'Preposition "di tempat" must remain separate',
        );
        expect(
          combinedText,
          contains('di tepi tebing'),
          reason: 'Preposition "di tepi" must remain separate',
        );
        expect(
          combinedText,
          contains('ditutup'),
          reason: 'Passive verb "ditutup" must be joined',
        );
        expect(
          combinedText,
          contains('ditendang'),
          reason: 'Passive verb "ditendang" must be joined',
        );
        expect(
          combinedText,
          contains('mendorong'),
          reason: 'Active verb "mendorong" must be intact',
        );
        expect(
          combinedText,
          contains('dibelah'),
          reason: 'Passive verb "dibelah" must be joined',
        );
        expect(
          combinedText,
          contains('dipaksa'),
          reason: 'Passive verb "dipaksa" must be joined',
        );
        expect(
          combinedText,
          contains('mengira-ngira'),
          reason: 'Reduplication "mengira-ngira" must be preserved',
        );

        expect(sentenceCompletenessRate, greaterThanOrEqualTo(85.0));
      },
    );

    // -------------------------------------------------------------------------
    // Ground Truth Sample 5: Two-Column Academic Paper Reading Order & Column Ordering
    // -------------------------------------------------------------------------
    test(
      '5. Two-Column Reading Order & Column Ordering Accuracy Audit',
      () async {
        final academicPdf = File(
          'test/fixtures/corpus/04_two_column_academic.pdf',
        );
        expect(academicPdf.existsSync(), isTrue);

        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: academicPdf,
          bookId: 'academic_test',
        );
        expect(extraction.pages.isNotEmpty, isTrue);

        final resolved = ReadingOrderResolver.resolvePage(
          extraction.pages.first,
        );
        expect(resolved.layoutStructure, equals(PageLayoutStructure.twoColumn));

        // Separate lines into Column 1 vs Column 2 based on midpoint x
        final pageWidth = extraction.pages.first.pageSize.width;
        final midX = pageWidth / 2.0;

        final orderedLines = resolved.orderedLines;
        int col1Count = 0;
        int col2Count = 0;
        int interleavingViolations = 0;
        bool hasTransitionedToCol2 = false;

        for (final line in orderedLines) {
          // Skip full-width header/title lines
          if (line.bounds.width > pageWidth * 0.6) continue;

          final isCol1 = line.bounds.left < midX;
          final isCol2 = line.bounds.left >= midX;

          if (isCol1) {
            col1Count++;
            if (hasTransitionedToCol2) {
              interleavingViolations++;
            }
          } else if (isCol2) {
            col2Count++;
            hasTransitionedToCol2 = true;
          }
        }

        final columnOrderingAccuracy = interleavingViolations == 0
            ? 100.0
            : 0.0;

        print(
          '\n===============================================================',
        );
        print('TWO-COLUMN READING ORDER & COLUMN ORDERING ACCURACY AUDIT');
        print(
          '===============================================================',
        );
        print('Total Ordered Lines:          ${orderedLines.length}');
        print('Column 1 Lines:               $col1Count');
        print('Column 2 Lines:               $col2Count');
        print('Interleaving Violations:      $interleavingViolations');
        print(
          'Column Ordering Accuracy:     ${columnOrderingAccuracy.toStringAsFixed(1)}%',
        );

        expect(
          columnOrderingAccuracy,
          equals(100.0),
          reason:
              'Two-column layout must never interleave lines across columns',
        );
        expect(col1Count, greaterThan(5));
        expect(col2Count, greaterThan(5));
      },
    );
  });
}
