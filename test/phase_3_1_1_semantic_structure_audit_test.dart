// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings, unused_import

import 'dart:ui' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfFontStyle;
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';

class SemanticEvaluationStats {
  int truePositives = 0;
  int falsePositives = 0;
  int falseNegatives = 0;

  void recordTP() => truePositives++;
  void recordFP() => falsePositives++;
  void recordFN() => falseNegatives++;

  double get precision {
    final total = truePositives + falsePositives;
    return total == 0 ? 1.0 : truePositives / total;
  }

  double get recall {
    final total = truePositives + falseNegatives;
    return total == 0 ? 1.0 : truePositives / total;
  }

  double get f1Score {
    final p = precision;
    final r = recall;
    return (p + r) == 0 ? 0.0 : (2 * p * r) / (p + r);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3.1.1 — Semantic Structure & Hierarchy Classification Audit', () {
    final categoryStats = <String, SemanticEvaluationStats>{
      'Heading (H1/H2/Title)': SemanticEvaluationStats(),
      'Body Paragraph': SemanticEvaluationStats(),
      'Dialogue / Quote': SemanticEvaluationStats(),
      'Ordered List': SemanticEvaluationStats(),
      'Unordered List': SemanticEvaluationStats(),
      'Footnote': SemanticEvaluationStats(),
      'Caption': SemanticEvaluationStats(),
      'Copyright Block': SemanticEvaluationStats(),
      'Running Chrome / Footer': SemanticEvaluationStats(),
    };

    void evaluateBlock({
      required String expectedCategory,
      required SemanticBlockType actualType,
      required String textSample,
    }) {
      String resolvedActualCategory;
      switch (actualType) {
        case SemanticBlockType.heading1:
        case SemanticBlockType.heading2:
        case SemanticBlockType.heading3:
        case SemanticBlockType.documentTitle:
          resolvedActualCategory = 'Heading (H1/H2/Title)';
          break;
        case SemanticBlockType.bodyParagraph:
          resolvedActualCategory = 'Body Paragraph';
          break;
        case SemanticBlockType.quote:
          resolvedActualCategory = 'Dialogue / Quote';
          break;
        case SemanticBlockType.orderedListItem:
          resolvedActualCategory = 'Ordered List';
          break;
        case SemanticBlockType.unorderedListItem:
          resolvedActualCategory = 'Unordered List';
          break;
        case SemanticBlockType.footnote:
          resolvedActualCategory = 'Footnote';
          break;
        case SemanticBlockType.caption:
          resolvedActualCategory = 'Caption';
          break;
        case SemanticBlockType.copyrightBlock:
          resolvedActualCategory = 'Copyright Block';
          break;
        case SemanticBlockType.runningHeader:
        case SemanticBlockType.runningFooter:
        case SemanticBlockType.pageNumber:
          resolvedActualCategory = 'Running Chrome / Footer';
          break;
        default:
          resolvedActualCategory = 'Body Paragraph';
      }

      if (resolvedActualCategory == expectedCategory) {
        categoryStats[expectedCategory]?.recordTP();
      } else {
        categoryStats[expectedCategory]?.recordFN();
        categoryStats[resolvedActualCategory]?.recordFP();
      }
    }

    test('1. Structure Audit: Complex Multi-Role Document Geometry', () async {
      final mockLines = <ExtractedTextLine>[
        // Top running header
        ExtractedTextLine(
          lineIndex: 0,
          text: 'BICARA ITU ADA SENINYA',
          bounds: const Rect.fromLTWH(180, 45, 200, 12),
          fontSize: 10.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        // H1 Chapter Heading
        ExtractedTextLine(
          lineIndex: 1,
          text: 'BAB 1: KESAN PERTAMA SANGAT MENENTUKAN',
          bounds: const Rect.fromLTWH(50, 110, 350, 24),
          fontSize: 18.0,
          fontStyle: const [PdfFontStyle.bold],
          pageIndex: 0,
        ),
        // H2 Section Subheading
        ExtractedTextLine(
          lineIndex: 2,
          text: '1. Mengapa Kesan Pertama Sulit Diubah?',
          bounds: const Rect.fromLTWH(50, 150, 280, 16),
          fontSize: 14.0,
          fontStyle: const [PdfFontStyle.bold],
          pageIndex: 0,
        ),
        // Body Paragraph 1 (2 lines)
        ExtractedTextLine(
          lineIndex: 3,
          text:
              'Kesan pertama seseorang terhadap kita terbentuk dalam hitungan detik.',
          bounds: const Rect.fromLTWH(50, 180, 450, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        ExtractedTextLine(
          lineIndex: 4,
          text:
              'Sekali terbentuk, otak manusia cenderung mencari konfirmasi atas kesan tersebut.',
          bounds: const Rect.fromLTWH(50, 196, 470, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        // Dialogue Block
        ExtractedTextLine(
          lineIndex: 5,
          text:
              '"Bagaimana cara kita mengubah kesan buruk itu?" tanya seorang peserta seminar.',
          bounds: const Rect.fromLTWH(70, 225, 430, 12),
          fontSize: 11.0,
          fontStyle: const [PdfFontStyle.italic],
          pageIndex: 0,
        ),
        // Ordered List Items
        ExtractedTextLine(
          lineIndex: 6,
          text: '1. Perhatikan kontak mata saat pertama kali berjabat tangan.',
          bounds: const Rect.fromLTWH(50, 255, 400, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        ExtractedTextLine(
          lineIndex: 7,
          text: '2. Gunakan nada suara yang tenang, hangat, dan jelas.',
          bounds: const Rect.fromLTWH(50, 275, 380, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        ExtractedTextLine(
          lineIndex: 8,
          text: '3. Dengarkan lawan bicara sebelum mulai menimpali ucapannya.',
          bounds: const Rect.fromLTWH(50, 295, 420, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        // Unordered List Items
        ExtractedTextLine(
          lineIndex: 9,
          text: '• Jangan menyilangkan lengan di dada selama berbicara.',
          bounds: const Rect.fromLTWH(50, 325, 390, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        ExtractedTextLine(
          lineIndex: 10,
          text: '• Berikan senyum tulus yang tidak dipaksakan.',
          bounds: const Rect.fromLTWH(50, 345, 350, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        // Caption
        ExtractedTextLine(
          lineIndex: 11,
          text: 'Gambar 1.2 Bahasa Tubuh yang Membangun Rasa Percaya',
          bounds: const Rect.fromLTWH(100, 480, 320, 11),
          fontSize: 10.0,
          fontStyle: const [PdfFontStyle.italic],
          pageIndex: 0,
        ),
        // Body Paragraph 2
        ExtractedTextLine(
          lineIndex: 12,
          text:
              'Komunikasi bukan sekadar kata-kata yang keluar dari bibir, melainkan seluruh gestur tubuh kita.',
          bounds: const Rect.fromLTWH(50, 520, 480, 12),
          fontSize: 11.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        // Footnote at bottom
        ExtractedTextLine(
          lineIndex: 13,
          text:
              '1. Penelitian Albert Mehrabian tentang komunikasi non-verbal (1971).',
          bounds: const Rect.fromLTWH(50, 720, 420, 9),
          fontSize: 9.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
        // Bottom page number
        ExtractedTextLine(
          lineIndex: 14,
          text: '33',
          bounds: const Rect.fromLTWH(245, 755, 20, 11),
          fontSize: 10.0,
          fontStyle: const [],
          pageIndex: 0,
        ),
      ];

      final extraction = DocumentExtractionResult(
        bookId: 'test-book-structure-01',
        totalPages: 1,
        totalTextLines: mockLines.length,
        totalImages: 0,
        layerBreakdown: const {PageLayerType.nativeText: 1},
        hasUsableTextLayer: true,
        warnings: const [],
        durationMs: 1.0,
        pages: [
          ExtractedPageGeometry(
            pageIndex: 0,
            pageSize: const Size(500, 792),
            lines: mockLines,
            images: [],
            layerType: PageLayerType.nativeText,
            charCount: mockLines.fold(0, (acc, l) => acc + l.text.length),
          ),
        ],
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Bicara Itu Ada Seninya',
        author: 'Oh Su Hyang',
      );

      expect(reconstructed.chapters, isNotEmpty);
      expect(reconstructed.blocks, isNotEmpty);

      // Map blocks back to ground truth expectations
      final expectedLabels = [
        'Running Chrome / Footer', // BICARA ITU ADA SENINYA
        'Heading (H1/H2/Title)', // BAB 1
        'Heading (H1/H2/Title)', // 1. Mengapa Kesan
        'Body Paragraph', // Kesan pertama...
        'Dialogue / Quote', // "Bagaimana cara kita...
        'Ordered List', // 1. Perhatikan...
        'Ordered List', // 2. Gunakan...
        'Ordered List', // 3. Dengarkan...
        'Unordered List', // • Jangan...
        'Unordered List', // • Berikan...
        'Caption', // Gambar 1.2...
        'Body Paragraph', // Komunikasi bukan...
        'Footnote', // 1. Penelitian...
        'Running Chrome / Footer', // 33
      ];

      expect(
        reconstructed.blocks.length,
        equals(expectedLabels.length),
        reason:
            'Every ground truth block should be reconstructed without merging or dropping',
      );

      for (int i = 0; i < reconstructed.blocks.length; i++) {
        final block = reconstructed.blocks[i];
        final expected = expectedLabels[i];
        print(
          'Block $i: expected "$expected" | actual "${block.type.name}" | text: "${block.text.length > 30 ? block.text.substring(0, 30) + '...' : block.text}"',
        );
        evaluateBlock(
          expectedCategory: expected,
          actualType: block.type,
          textSample: block.text,
        );
      }
    });

    test('2. Structure Audit: Publishing & Copyright Metadata Isolation', () async {
      final copyrightLines = <ExtractedTextLine>[
        ExtractedTextLine(
          lineIndex: 0,
          text: 'LAUT BERCERITA',
          bounds: const Rect.fromLTWH(180, 200, 200, 24),
          fontSize: 20.0,
          fontStyle: const [PdfFontStyle.bold],
          pageIndex: 1,
        ),
        ExtractedTextLine(
          lineIndex: 1,
          text: 'Hak cipta dilindungi undang-undang.',
          bounds: const Rect.fromLTWH(80, 260, 300, 11),
          fontSize: 10.0,
          fontStyle: const [],
          pageIndex: 1,
        ),
        ExtractedTextLine(
          lineIndex: 2,
          text:
              'Dilarang memfotokopi atau memperbanyak sebagian atau seluruh buku ini.',
          bounds: const Rect.fromLTWH(80, 275, 380, 11),
          fontSize: 10.0,
          fontStyle: const [],
          pageIndex: 1,
        ),
        ExtractedTextLine(
          lineIndex: 3,
          text: 'Katalog Dalam Terbitan (KDT)',
          bounds: const Rect.fromLTWH(80, 310, 220, 11),
          fontSize: 10.0,
          fontStyle: const [PdfFontStyle.bold],
          pageIndex: 1,
        ),
        ExtractedTextLine(
          lineIndex: 4,
          text: 'ISBN 978-602-424-694-5',
          bounds: const Rect.fromLTWH(80, 330, 180, 11),
          fontSize: 10.0,
          fontStyle: const [],
          pageIndex: 1,
        ),
        ExtractedTextLine(
          lineIndex: 5,
          text: 'Diterbitkan oleh Penerbit Kepustakaan Populer Gramedia (KPG)',
          bounds: const Rect.fromLTWH(80, 360, 360, 11),
          fontSize: 10.0,
          fontStyle: const [],
          pageIndex: 1,
        ),
      ];

      final extraction = DocumentExtractionResult(
        bookId: 'test-book-copyright',
        totalPages: 2,
        totalTextLines: copyrightLines.length,
        totalImages: 0,
        layerBreakdown: const {PageLayerType.nativeText: 1},
        hasUsableTextLayer: true,
        warnings: const [],
        durationMs: 1.0,
        pages: [
          ExtractedPageGeometry(
            pageIndex: 1,
            pageSize: const Size(500, 792),
            lines: copyrightLines,
            images: [],
            layerType: PageLayerType.nativeText,
            charCount: copyrightLines.fold(0, (acc, l) => acc + l.text.length),
          ),
        ],
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Laut Bercerita',
      );

      // Verify copyright blocks are isolated and not fused into body paragraphs
      for (final block in reconstructed.blocks) {
        if (block.text.contains('Hak cipta') ||
            block.text.contains('Dilarang memfotokopi') ||
            block.text.contains('KDT') ||
            block.text.contains('ISBN') ||
            block.text.contains('Diterbitkan oleh')) {
          evaluateBlock(
            expectedCategory: 'Copyright Block',
            actualType: block.type,
            textSample: block.text,
          );
        } else if (block.text == 'LAUT BERCERITA') {
          evaluateBlock(
            expectedCategory: 'Heading (H1/H2/Title)',
            actualType: block.type,
            textSample: block.text,
          );
        }
      }
    });

    test('3. Compute Confusion Matrix, Precision, Recall, and F1 per Structure', () {
      print('\n' + '=' * 75);
      print(
        'SEMANTIC STRUCTURE CLASSIFICATION AUDIT RESULTS (PRECISION / RECALL / F1)',
      );
      print('=' * 75);
      print(
        'Category'.padRight(28) +
            '| TP'.padRight(6) +
            '| FP'.padRight(6) +
            '| FN'.padRight(6) +
            '| Precision'.padRight(12) +
            '| Recall'.padRight(10) +
            '| F1-Score',
      );
      print('-' * 75);

      double totalF1 = 0;
      int activeCategories = 0;

      categoryStats.forEach((category, stats) {
        final p = stats.precision * 100.0;
        final r = stats.recall * 100.0;
        final f1 = stats.f1Score * 100.0;

        print(
          category.padRight(28) +
              '| ${stats.truePositives}'.padRight(6) +
              '| ${stats.falsePositives}'.padRight(6) +
              '| ${stats.falseNegatives}'.padRight(6) +
              '| ${p.toStringAsFixed(1)}%'.padRight(12) +
              '| ${r.toStringAsFixed(1)}%'.padRight(10) +
              '| ${f1.toStringAsFixed(1)}%',
        );

        if (stats.truePositives + stats.falseNegatives > 0) {
          totalF1 += stats.f1Score;
          activeCategories++;
        }

        // Precision & Recall threshold assertions: No semantic structure should fall below 80% F1
        expect(
          stats.f1Score,
          greaterThanOrEqualTo(0.80),
          reason:
              '$category F1-score should be >= 0.80 for high-quality reading experience',
        );
      });

      final macroF1 = (totalF1 / activeCategories) * 100.0;
      print('-' * 75);
      print('MACRO-AVERAGED F1-SCORE: ${macroF1.toStringAsFixed(2)}%');
      print('=' * 75 + '\n');

      expect(
        macroF1,
        greaterThanOrEqualTo(90.0),
        reason:
            'Macro-averaged F1 across all semantic structures must be >= 90%',
      );
    });
  });
}
