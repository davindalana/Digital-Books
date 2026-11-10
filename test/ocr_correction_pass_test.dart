import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/ocr_correction_pass.dart';

void main() {
  group('OcrCorrectionPass.correct', () {
    test('repairs verified exact tokens and records provenance', () {
      final result = OcrCorrectionPass.correct(
        'Negosiasi memiliki makna iproses perundingan yang menentukan.',
      );

      expect(
        result.text,
        'Negosiasi memiliki makna proses perundingan yang menentukan.',
      );
      expect(result.corrections, hasLength(1));
      expect(result.corrections.single, {
        'rule': 'token',
        'original': 'iproses',
        'corrected': 'proses',
      });
    });

    test('does not touch a correct word that contains a correction token', () {
      final result = OcrCorrectionPass.correct(
        'Pidato itu diungkapkan secara ringkas.',
      );

      expect(result.text, 'Pidato itu diungkapkan secara ringkas.');
      expect(result.changed, isFalse);
    });

    test('removes repeated-letter artefacts without eating real words', () {
      final result = OcrCorrectionPass.correct(
        'Mental sayaii terganggu. Ia diperbaikii. Muka bumiii. '
        'Kompetisii. Latihan memujii. Wisata akan dimulaii.',
      );

      expect(
        result.text,
        'Mental saya terganggu. Ia diperbaiki. Muka bumi. '
        'Kompetisi. Latihan memuji. Wisata akan dimulai.',
      );
      expect(result.corrections, hasLength(6));
      expect(result.corrections.every((c) => c['rule'] == 'token'), isTrue);
    });

    test('removes italic markers before quoted speech', () {
      final result = OcrCorrectionPass.correct(
        'Ia menatapku. iAku hanya tahu. Mereka berkata, iBetul, kami butuh itu!i',
      );

      expect(
        result.text,
        'Ia menatapku. Aku hanya tahu. Mereka berkata, Betul, kami butuh itu!',
      );
      expect(
        result.corrections.where((c) => c['rule'] == 'italicMarker'),
        hasLength(3),
      );
    });

    test('removes markers that trail a closing quote or question mark', () {
      final result = OcrCorrectionPass.correct(
        'Lebih baik kami tidak berbicarai"i dan "sekolah di mana?i',
      );

      expect(
        result.text,
        'Lebih baik kami tidak berbicara" dan "sekolah di mana?',
      );
      expect(result.changed, isTrue);
    });

    test('preserves product names that legitimately start with i', () {
      const text =
          'Steve Jobs mengeluarkan iPod, iPhone, iPad, iMac, iTunes, iCloud, '
          'iOS, dan Radio Podcast iViva My Life dari kantong.';
      final result = OcrCorrectionPass.correct(text);

      expect(result.text, text);
      expect(result.changed, isFalse);
    });

    test('repairs the observed word-level OCR errors', () {
      final result = OcrCorrectionPass.correct(
        'Seteve Jobs memakai iPod. Ia mengggunakan istilah yang salah.',
      );

      expect(
        result.text,
        'Steve Jobs memakai iPod. Ia menggunakan istilah yang salah.',
      );
      expect(result.corrections.map((c) => c['original']), [
        'Seteve',
        'mengggunakan',
      ]);
    });

    test('repairs heading tokens without touching words that contain them', () {
      final result = OcrCorrectionPass.correct(
        'Kcepatan\nGema Suara yanga Menarik Orang',
      );

      expect(result.text, 'Kecepatan\nGema Suara yang Menarik Orang');
      expect(result.corrections.map((c) => c['original']), [
        'Kcepatan',
        'yanga',
      ]);

      // `yanga` must only match as a standalone token, not inside `Goyangan`.
      final guarded = OcrCorrectionPass.correct('Goyangan tubuhnya lembut.');
      expect(guarded.text, 'Goyangan tubuhnya lembut.');
      expect(guarded.changed, isFalse);
    });

    test('repairs the verified MEMHAK heading token exactly', () {
      final result = OcrCorrectionPass.correct(
        'Ucapan yang Membuat Lawan Bicara MEMHAK Kita',
      );

      expect(result.text, 'Ucapan yang Membuat Lawan Bicara MEMIHAK Kita');
      expect(result.corrections, [
        {'rule': 'token', 'original': 'MEMHAK', 'corrected': 'MEMIHAK'},
      ]);
      expect(
        OcrCorrectionPass.correct('MEMHAKAN bukan token yang sama').changed,
        isFalse,
      );
    });

    test('repairs Sentuha TOC token truncated by dot leader overlap', () {
      final result = OcrCorrectionPass.correct(
        'Dimulai dengan Pukulan, Diakhiri dengan Sentuha',
      );

      expect(result.text, 'Dimulai dengan Pukulan, Diakhiri dengan Sentuhan');
      expect(result.corrections, [
        {'rule': 'token', 'original': 'Sentuha', 'corrected': 'Sentuhan'},
      ]);
    });
  });

  group('OcrCorrectionPass.apply', () {
    test('records audit trail for MEMHAK in block metadata via apply', () {
      final headingBlock = SemanticReconstructedBlock(
        id: 'heading-bab3',
        type: SemanticBlockType.heading1,
        text: 'BAB III: UCAPAN YANG MEMBUAT LAWAN BICARA MEMHAK KITA',
        sourcePageIndex: 114,
        sourceBounds: const Rect.fromLTWH(50, 50, 400, 30),
        confidence: 0.95,
        metadata: const {'role': 'chapterHeading'},
      );

      final applied = OcrCorrectionPass.apply([headingBlock]);

      expect(applied, hasLength(1));
      expect(
        applied.single.text,
        'BAB III: UCAPAN YANG MEMBUAT LAWAN BICARA MEMIHAK KITA',
      );
      expect(applied.single.metadata['ocrCorrections'], [
        {'rule': 'token', 'original': 'MEMHAK', 'corrected': 'MEMIHAK'},
      ]);
      expect(applied.single.metadata['role'], 'chapterHeading');
    });
    test('attaches corrections to metadata and preserves block identity', () {
      final block = SemanticReconstructedBlock(
        id: 'block-1',
        type: SemanticBlockType.bodyParagraph,
        text: 'Ia diperbaikii setelah berlatih.',
        sourcePageIndex: 10,
        sourceBounds: const Rect.fromLTWH(10, 10, 100, 20),
        confidence: 0.93,
        metadata: const {'kind': 'body'},
      );

      final result = OcrCorrectionPass.apply([block]);

      expect(result, hasLength(1));
      expect(result.single.id, 'block-1');
      expect(result.single.type, SemanticBlockType.bodyParagraph);
      expect(result.single.sourcePageIndex, 10);
      expect(result.single.confidence, 0.93);
      expect(result.single.text, 'Ia diperbaiki setelah berlatih.');
      expect(result.single.metadata['kind'], 'body');
      expect(result.single.metadata['ocrCorrections'], [
        {'rule': 'token', 'original': 'diperbaikii', 'corrected': 'diperbaiki'},
      ]);
    });

    test('returns the original block when no correction is needed', () {
      final block = SemanticReconstructedBlock(
        id: 'block-2',
        type: SemanticBlockType.bodyParagraph,
        text: 'Kalimat ini sudah benar.',
        sourcePageIndex: 2,
      );

      final result = OcrCorrectionPass.apply([block]);

      expect(identical(result.single, block), isTrue);
      expect(result.single.metadata.containsKey('ocrCorrections'), isFalse);
    });

    test('does not rewrite structural or empty blocks', () {
      final pageBreak = SemanticReconstructedBlock(
        id: 'break-1',
        type: SemanticBlockType.pageBreak,
        sourcePageIndex: 3,
      );

      final result = OcrCorrectionPass.apply([pageBreak]);

      expect(identical(result.single, pageBreak), isTrue);
    });
  });
}
