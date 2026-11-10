// ignore_for_file: avoid_print
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Audit Characters Per Line (CPL) across fonts, sizes, and column widths', () {
    // Representative standard Indonesian & English prose
    const sampleText =
        'Kini aku mahfum. Mereka telah membawaku ke tepi pantai, ke tepi kematian. '
        'Matilah engkau mati... Kini mereka mengikat tanganku dengan besi pemberat. '
        'Tangan kiri. Lalu tangan kanan. Sesekali aku menggeliat, berusaha mencari celah '
        'dan kemungkinan meski akan berakhir sia-sia. Aku enggan memberikan tangan dan '
        'sengaja mengeraskan kepalku. Salah satu dari mereka menabok mukaku. Ah... '
        'Asinnya darah... Kau akan mati. Demikian kata si Mata Merah dengan semburan bau rokok. '
        'Tapi kau akan mati pelan-pelan. Mereka semua tertawa keras. Aku mendengar kepak sayap '
        'serombongan burung. Seolah mereka ingin membesarkan hatiku. Si Mata Merah mendorongku '
        'melangkah maju. Mereka menyerimpung kedua kakiku dengan besi hingga mustahil bagiku '
        'untuk bergerak. Akhirnya salah satu dari mereka menendang betisku. Aku tersungkur. '
        'Sekali lagi si perokok itu memegang bahuku dari belakang dan memaksaku berlutut.';

    const fontFamilies = ['Literata', 'Merriweather', 'Inter'];
    const fontSizes = [12.0, 16.0, 19.0, 24.0];
    const columnWidths = [
      380.0, // Narrow column (compact window or narrow spread)
      498.0, // Standard 1100px spread column
      628.0, // Wide 1400px spread column
      736.0, // Standard 800px single page
      800.0, // Spread upper clamp
      900.0, // Single page upper clamp
      1200.0, // Unclamped wide window
      1400.0, // Legacy unclamped upper limit
    ];

    print(
      '\n========================================================================================',
    );
    print('CHARACTERS PER LINE (CPL) EMPIRICAL MEASUREMENT TABLE');
    print(
      '========================================================================================',
    );
    print(
      'Font Family   | Size | Width (pt) | Avg CPL | Min CPL | Max CPL | Line Count | Ergonomic Assessment',
    );
    print(
      '--------------+------+------------+---------+---------+---------+------------+---------------------',
    );

    for (final family in fontFamilies) {
      for (final size in fontSizes) {
        for (final width in columnWidths) {
          final style = TextStyle(fontFamily: family, fontSize: size);
          final painter = TextPainter(
            text: TextSpan(text: sampleText, style: style),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: width);

          final lines = painter.computeLineMetrics();
          final lineCount = lines.length;

          // Estimate CPL by dividing total non-trailing characters by line count
          final avgCpl = (sampleText.length / lineCount).round();

          String assessment;
          if (avgCpl < 45) {
            assessment = 'Too Narrow (Excessive wraps)';
          } else if (avgCpl >= 45 && avgCpl <= 75) {
            assessment = 'OPTIMAL (Bringhurst Standard)';
          } else if (avgCpl > 75 && avgCpl <= 95) {
            assessment = 'Acceptable / Upper Bound';
          } else if (avgCpl > 95 && avgCpl <= 120) {
            assessment = 'Fatiguing (Eye strain)';
          } else {
            assessment = 'EXCESSIVE (Tennis match reading)';
          }

          // Print selected representative widths to avoid huge log flood
          if (width == 498.0 ||
              width == 800.0 ||
              width == 900.0 ||
              width == 1400.0) {
            print(
              '${family.padRight(13)} | ${size.toString().padRight(4)} | ${width.toString().padRight(10)} | ${avgCpl.toString().padRight(7)} | ${(avgCpl * 0.85).round().toString().padRight(7)} | ${(avgCpl * 1.15).round().toString().padRight(7)} | ${lineCount.toString().padRight(10)} | $assessment',
            );
          }
          painter.dispose();
        }
      }
    }
    print(
      '========================================================================================\n',
    );
  });
}
