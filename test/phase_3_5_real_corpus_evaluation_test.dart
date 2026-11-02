// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';

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

double calculateCer(String groundTruth, String ocrText) {
  if (groundTruth.isEmpty) return ocrText.isEmpty ? 0.0 : 100.0;
  final dist = levenshteinDistance(groundTruth.runes.toList(), ocrText.runes.toList());
  return (dist / groundTruth.runes.length) * 100.0;
}

double calculateWer(String groundTruth, String ocrText) {
  final gtWords = groundTruth.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final ocrWords = ocrText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (gtWords.isEmpty) return ocrWords.isEmpty ? 0.0 : 100.0;
  final dist = levenshteinDistance(gtWords, ocrWords);
  return (dist / gtWords.length) * 100.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ocrService = AppleVisionOcrService();
  const visualDir = 'docs/visual_evidence/phase_3_5';

  final lautFile = File('/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf');
  final bicaraFile = File('/Users/davindalana/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf');
  final filosofiFile = File('/Users/davindalana/Downloads/filosofi-teraspdf.pdf');
  final powerFile = File('/Users/davindalana/Downloads/The 48 Laws Of Power (Robert Greene).pdf');
  final suspectXFile = File('/Users/davindalana/Downloads/Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf');
  final jurnalFile = File('/Users/davindalana/Downloads/1259-Article Text-5284-1-10-20231024.pdf');
  final letThemFile = File('/Users/davindalana/Downloads/The Let Them Theory (Mel Robbins).pdf');

  setUpAll(() async {
    Directory(visualDir).createSync(recursive: true);
    expect(lautFile.existsSync(), isTrue);
    expect(bicaraFile.existsSync(), isTrue);
    expect(filosofiFile.existsSync(), isTrue);
    expect(powerFile.existsSync(), isTrue);
    expect(suspectXFile.existsSync(), isTrue);
    expect(jurnalFile.existsSync(), isTrue);
    expect(letThemFile.existsSync(), isTrue);
    expect(ocrService.isAvailable, isTrue);
  });

  Future<void> renderPageToDisk(File pdfFile, int pageIndex, String outputPath) async {
    final doc = await PdfDocument.openFile(pdfFile.path);
    final page = doc.pages[pageIndex];
    final img = await page.render(
      width: (page.width * 1.5).round(),
      height: (page.height * 1.5).round(),
    );
    final uiImg = await img?.createImage();
    final byteData = await uiImg?.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      File(outputPath).writeAsBytesSync(byteData.buffer.asUint8List());
    }
    await doc.dispose();
  }

  group('Phase 3.5 — Real-World Multi-Corpus OCR & Reconstruction Validation', () {
    // -------------------------------------------------------------------------
    // Category A: Indonesian Fiction Prose (Laut Bercerita P.15)
    // -------------------------------------------------------------------------
    test('Category A: Indonesian Fiction Prose (Laut Bercerita P.15)', () async {
      await renderPageToDisk(lautFile, 14, '$visualDir/category_a_laut_bercerita_p15.png');

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
mereberteriak agar aku menaiki sebuah speedboat. Bau asin
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

      final doc = await PdfDocument.openFile(lautFile.path);
      final page = doc.pages[14];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY A: FICTION PROSE (LAUT BERCERITA P.15)');
      print('===============================================================');
      print('Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}');
      print('OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_a_laut_bercerita_p15.png');

      expect(cer, lessThan(5.0));
      expect(wer, lessThan(8.0));
    });

    // -------------------------------------------------------------------------
    // Category B: Indonesian Non-Fiction (Bicara Itu Ada Seninya P.33)
    // -------------------------------------------------------------------------
    test('Category B: Indonesian Non-Fiction (Bicara Itu Ada Seninya P.33)', () async {
      await renderPageToDisk(bicaraFile, 32, '$visualDir/category_b_bicara_seninya_p33.png');

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

      final doc = await PdfDocument.openFile(bicaraFile.path);
      final page = doc.pages[32];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final filteredLines = ocrResult.lines.where((l) => !RegExp(r'^\d+$').hasMatch(l.text.trim())).map((l) => l.text).toList();
      final ocrText = filteredLines.join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY B: NON-FICTION (BICARA ITU ADA SENINYA P.33)');
      print('===============================================================');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_b_bicara_seninya_p33.png');

      expect(cer, lessThan(2.0));
      expect(wer, lessThan(4.0));
    });

    // -------------------------------------------------------------------------
    // Category C: Indonesian Philosophy / Self-Help (Filosofi Teras P.21)
    // -------------------------------------------------------------------------
    test('Category C: Indonesian Philosophy (Filosofi Teras P.21)', () async {
      await renderPageToDisk(filosofiFile, 20, '$visualDir/category_c_filosofi_teras_p21.png');

      final doc = await PdfDocument.openFile(filosofiFile.path);
      final page = doc.pages[20];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');

      print('\n===============================================================');
      print('CATEGORY C: PHILOSOPHY ESSAY (FILOSOFI TERAS P.21)');
      print('===============================================================');
      print('OCR Extracted Lines: ${ocrResult.lines.length}');
      print('OCR Sample (first 3 lines):');
      for (final l in ocrResult.lines.take(3)) {
        print('  "${l.text}"');
      }

      // Check key technical philosophy concepts
      expect(ocrText, contains('emosi negatif'));
      expect(ocrText, contains('Stoa'));
      expect(ocrResult.lines.length, greaterThanOrEqualTo(25));
    });

    // -------------------------------------------------------------------------
    // Category D: Multi-Style / Heading & Marginalia (48 Laws Of Power P.13)
    // -------------------------------------------------------------------------
    test('Category D: Multi-Style & Heading Structure (The 48 Laws Of Power P.13)', () async {
      await renderPageToDisk(powerFile, 12, '$visualDir/category_d_48_laws_p13.png');

      final doc = await PdfDocument.openFile(powerFile.path);
      final page = doc.pages[12];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');

      print('\n===============================================================');
      print('CATEGORY D: MULTI-HEADING STRUCTURE (48 LAWS OF POWER P.13)');
      print('===============================================================');
      print('OCR Extracted Lines: ${ocrResult.lines.length}');
      print('Title Heading Recognized: ${ocrText.contains('HUKUM 48')}');

      expect(ocrText, contains('HUKUM 48'));
      expect(ocrText, contains('BERBENTUK'));
      expect(ocrResult.lines.length, greaterThanOrEqualTo(20));
    });

    // -------------------------------------------------------------------------
    // Category E: Translated Novel Dialogue & Japanese Names (Suspect X P.11)
    // -------------------------------------------------------------------------
    test('Category E: Translated Dialogue & Transliteration (Suspect X P.11)', () async {
      await renderPageToDisk(suspectXFile, 10, '$visualDir/category_e_suspect_x_p11.png');

      final doc = await PdfDocument.openFile(suspectXFile.path);
      final page = doc.pages[10];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');

      print('\n===============================================================');
      print('CATEGORY E: TRANSLATED NOVEL DIALOGUE (SUSPECT X P.11)');
      print('===============================================================');
      print('OCR Extracted Lines: ${ocrResult.lines.length}');
      print('Contains Dialogue Store: ${ocrText.contains('Benten-tei')}');

      expect(ocrText, contains('Benten-tei'));
      expect(ocrText, contains('Ishigami'));
      expect(ocrResult.lines.length, greaterThanOrEqualTo(25));
    });

    // -------------------------------------------------------------------------
    // Category F: Two-Column Academic Paper Structure (Jurnal P.2)
    // -------------------------------------------------------------------------
    test('Category F: Two-Column Academic Paper Structure (Jurnal P.2)', () async {
      await renderPageToDisk(jurnalFile, 1, '$visualDir/category_f_jurnal_p2.png');

      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: jurnalFile,
        bookId: 'jurnal_test',
        extractImagesToDisk: false,
      );

      final page2 = extraction.pages.length >= 2 ? extraction.pages[1] : extraction.pages.first;
      final resolved = ReadingOrderResolver.resolvePage(page2);

      print('\n===============================================================');
      print('CATEGORY F: TWO-COLUMN ACADEMIC PAPER (JURNAL P.2)');
      print('===============================================================');
      print('Total Lines Extracted: ${resolved.orderedLines.length}');
      print('Detected Layout: ${resolved.layoutStructure}');

      // Group into left and right columns (page width center split)
      final midX = page2.pageSize.width / 2.0;
      final col1 = resolved.orderedLines.where((l) => l.bounds.center.dx < midX).toList();
      final col2 = resolved.orderedLines.where((l) => l.bounds.center.dx >= midX).toList();

      print('Column 1 Lines: ${col1.length}');
      print('Column 2 Lines: ${col2.length}');

      expect(resolved.orderedLines.length, greaterThanOrEqualTo(20));
    });

    // -------------------------------------------------------------------------
    // Category G: Native Selectable Digital PDF (The Let Them Theory P.12)
    // -------------------------------------------------------------------------
    test('Category G: Native Selectable Digital PDF (The Let Them Theory P.12)', () async {
      await renderPageToDisk(letThemFile, 11, '$visualDir/category_g_let_them_theory_p12.png');

      final docResult = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: letThemFile,
        bookId: 'let_them_digital_test',
        extractImagesToDisk: false,
      );

      final page12 = docResult.pages.length >= 12 ? docResult.pages[11] : docResult.pages.first;
      final extractedText = page12.lines.map((l) => l.text).join('\n');

      print('\n===============================================================');
      print('CATEGORY G: NATIVE SELECTABLE DIGITAL PDF (LET THEM THEORY P.12)');
      print('===============================================================');
      print('Digital Text Lines Extracted: ${page12.lines.length}');
      print('Contains Title/Heading: ${extractedText.contains('Bibliography') || extractedText.contains('About Mel')}');

      expect(page12.lines.length, greaterThanOrEqualTo(2));
      expect(page12.lines.any((l) => l.text.contains('Mel') || l.text.contains('Bibliography')), isTrue);
    });
  });
}
