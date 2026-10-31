import 'dart:io';
import 'package:flutter/material.dart' show Offset, Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Programmatic generator for the Phase 2.7 Representative PDF Corpus.
/// Generates deterministic, legally unencumbered test PDF documents across 10 structural categories.
class CorpusPdfGenerator {
  static const dummyJpegHeader = [
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x01,
    0x00,
    0x48,
    0x00,
    0x48,
    0x00,
    0x00,
    0xFF,
    0xDB,
    0x00,
    0x43,
    0x00,
    0x08,
    0x06,
    0x06,
    0x07,
    0x06,
    0x05,
    0x08,
    0x07,
    0x07,
    0x07,
    0x09,
    0x09,
    0x08,
    0x0A,
    0x0C,
    0x14,
    0x0D,
    0x0C,
    0x0B,
    0x0B,
    0x0C,
    0x19,
    0x12,
    0x13,
    0x0F,
    0x14,
    0x1D,
    0x1A,
    0x1F,
    0x1E,
    0x1D,
    0x1A,
    0x1C,
    0x1C,
    0x20,
    0x24,
    0x2E,
    0x27,
    0x20,
    0x22,
    0x2C,
    0x23,
    0x1C,
    0x1C,
    0x28,
    0x37,
    0x29,
    0x2C,
    0x30,
    0x31,
    0x34,
    0x34,
    0x34,
    0x1F,
    0x27,
    0x39,
    0x3D,
    0x38,
    0x32,
    0x3C,
    0x2E,
    0x33,
    0x34,
    0x32,
    0xFF,
    0xC0,
    0x00,
    0x0B,
    0x08,
    0x00,
    0x10,
    0x00,
    0x10,
    0x01,
    0x01,
    0x11,
    0x00,
    0xFF,
    0xC4,
    0x00,
    0x1F,
    0x00,
    0x00,
    0x01,
    0x05,
    0x01,
    0x01,
    0x01,
    0x01,
    0x01,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0xFF,
    0xDA,
    0x00,
    0x08,
    0x01,
    0x01,
    0x00,
    0x00,
    0x3F,
    0x00,
    0xBF,
    0xFF,
    0xD9,
  ];

  static Future<void> generateAllCorpusFiles(Directory outputDir) async {
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    await generate01SingleColumnNovel(
      File('${outputDir.path}/01_single_column_novel.pdf'),
    );
    await generate02IllustratedNovel(
      File('${outputDir.path}/02_illustrated_novel.pdf'),
    );
    await generate03DiagramsAndMaps(
      File('${outputDir.path}/03_diagrams_maps.pdf'),
    );
    await generate04TwoColumnAcademic(
      File('${outputDir.path}/04_two_column_academic.pdf'),
    );
    await generate05HeadersFooters(
      File('${outputDir.path}/05_headers_footers.pdf'),
    );
    await generate06Footnotes(File('${outputDir.path}/06_footnotes.pdf'));
    await generate07TablesFigures(
      File('${outputDir.path}/07_tables_figures.pdf'),
    );
    await generate08ScannedImageOnly(
      File('${outputDir.path}/08_scanned_image_only.pdf'),
    );
    await generate09HybridMixed(File('${outputDir.path}/09_hybrid_mixed.pdf'));
    await generate10MultiHeadingStyles(
      File('${outputDir.path}/10_multi_heading_styles.pdf'),
    );
  }

  // 1. Single Column Novel
  static Future<void> generate01SingleColumnNovel(File file) async {
    final doc = PdfDocument();
    final h1Font = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

    final page = doc.pages.add();
    page.graphics.drawString(
      'Chapter 1: The Beginning',
      h1Font,
      bounds: const Rect.fromLTWH(50, 60, 490, 30),
    );
    page.graphics.drawString(
      'It was a dark and stormy night when the messenger finally arrived at the gates of the ancient estate. '
      'He carried news that would change the destiny of the kingdom forever.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 100, 490, 50),
    );
    page.graphics.drawString(
      '"Open the gates!" cried the guard from the watchtower. '
      'The heavy iron hinges groaned as the barrier swung outward into the tempest.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 160, 490, 50),
    );
    page.graphics.drawString(
      'Inside the great hall, a roaring fire crackled within the stone hearth, casting long dancing shadows across '
      'the oak dining table. Lord Gerald sat silently, examining an old parchment map.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 220, 490, 60),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 2. Illustrated Novel
  static Future<void> generate02IllustratedNovel(File file) async {
    final doc = PdfDocument();
    final h1Font = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

    final page1 = doc.pages.add();
    page1.graphics.drawString(
      'Chapter 2: The Forest Dweller',
      h1Font,
      bounds: const Rect.fromLTWH(50, 60, 490, 30),
    );
    page1.graphics.drawString(
      'Deep within the Whispering Woods lived an alchemist whose remedies were known across three kingdoms.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 100, 490, 40),
    );

    // Embedded illustration
    final img = PdfBitmap(dummyJpegHeader);
    page1.graphics.drawImage(img, const Rect.fromLTWH(50, 150, 240, 160));
    page1.graphics.drawString(
      'Figure 2.1: The cottage in the forest.',
      PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.italic),
      bounds: const Rect.fromLTWH(50, 315, 240, 20),
    );

    page1.graphics.drawString(
      'Visitors rarely found the trail without the aid of a magical guide.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 345, 490, 40),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 3. Diagrams and Maps
  static Future<void> generate03DiagramsAndMaps(File file) async {
    final doc = PdfDocument();
    final h1Font = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

    final page = doc.pages.add();
    page.graphics.drawString(
      'The Mansion Blueprint',
      h1Font,
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );
    page.graphics.drawString(
      'Examine the layout of the first floor before proceeding.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 85, 490, 25),
    );

    final mapImg = PdfBitmap(dummyJpegHeader);
    page.graphics.drawImage(mapImg, const Rect.fromLTWH(50, 120, 400, 250));

    page.graphics.drawString(
      'Diagram 1: First floor plan with hidden chambers.',
      PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.italic),
      bounds: const Rect.fromLTWH(50, 375, 400, 20),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 4. Two-Column Academic Document
  static Future<void> generate04TwoColumnAcademic(File file) async {
    final doc = PdfDocument();
    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      16,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final page = doc.pages.add();

    page.graphics.drawString(
      'A Comparative Study of Document Layout Models',
      titleFont,
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );

    // Left column: X=50..280 (width 230)
    page.graphics.drawString(
      'Abstract—This paper evaluates text extraction algorithms applied to fixed-layout documents. '
      'We examine spatial heuristics, bounding box clustering, and font size analysis to reconstruct natural reading sequences.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 90, 230, 80),
    );
    page.graphics.drawString(
      'I. INTRODUCTION\nDigital reading software must distinguish multi-column structures from sidebars. '
      'When two columns share the same vertical band, a naive horizontal scan interleaves independent paragraphs.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 180, 230, 120),
    );

    // Right column: X=310..540 (width 230)
    page.graphics.drawString(
      'II. METHODOLOGY\nOur dataset comprises 500 academic articles with diverse typographical conventions. '
      'We measure precision, recall, and column-transition boundary preservation across reading engines.',
      bodyFont,
      bounds: const Rect.fromLTWH(310, 90, 230, 100),
    );
    page.graphics.drawString(
      'III. RESULTS\nSpatial clustering achieves 98.4% accuracy on standard two-column grids with gutter widths exceeding 18 points.',
      bodyFont,
      bounds: const Rect.fromLTWH(310, 200, 230, 100),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 5. Headers and Footers
  static Future<void> generate05HeadersFooters(File file) async {
    final doc = PdfDocument();
    final headerFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      8,
      style: PdfFontStyle.italic,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

    for (int p = 1; p <= 3; p++) {
      final page = doc.pages.add();
      // Running Header at top (Y=25)
      page.graphics.drawString(
        'THE ADVENTURES OF SHERLOCK HOLMES',
        headerFont,
        bounds: const Rect.fromLTWH(50, 25, 490, 15),
      );
      page.graphics.drawLine(
        PdfPen(PdfColor(180, 180, 180)),
        const Offset(50, 42),
        const Offset(540, 42),
      );

      // Main Content
      page.graphics.drawString(
        'Section $p: The Investigation Continues',
        PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold),
        bounds: const Rect.fromLTWH(50, 60, 490, 25),
      );
      page.graphics.drawString(
        'Holmes took the violin from its corner and began to play a low, melancholy tune as he pondered the case.',
        bodyFont,
        bounds: const Rect.fromLTWH(50, 95, 490, 50),
      );

      // Running Footer at bottom (Y=800)
      page.graphics.drawLine(
        PdfPen(PdfColor(180, 180, 180)),
        const Offset(50, 795),
        const Offset(540, 795),
      );
      page.graphics.drawString(
        'Page $p of 3',
        headerFont,
        bounds: const Rect.fromLTWH(260, 805, 100, 15),
      );
    }

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 6. Footnotes
  static Future<void> generate06Footnotes(File file) async {
    final doc = PdfDocument();
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final fnFont = PdfStandardFont(PdfFontFamily.helvetica, 8);
    final page = doc.pages.add();

    page.graphics.drawString(
      'Chapter 3: Philosophical Inquiries',
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );
    page.graphics.drawString(
      'The concept of duration as articulated by Bergson[1] suggests that conscious time is fundamentally indivisible, '
      'differing in kind from spatialized time measured by clocks[2].',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 90, 490, 60),
    );

    // Footnote separator line
    page.graphics.drawLine(
      PdfPen(PdfColor(120, 120, 120)),
      const Offset(50, 740),
      const Offset(150, 740),
    );
    page.graphics.drawString(
      '[1] Henri Bergson, Time and Free Will, 1889, Chapter 2.',
      fnFont,
      bounds: const Rect.fromLTWH(50, 750, 490, 15),
    );
    page.graphics.drawString(
      '[2] Compare with Kant\'s transcendental aesthetic on the pure intuition of time.',
      fnFont,
      bounds: const Rect.fromLTWH(50, 768, 490, 15),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 7. Tables and Figures
  static Future<void> generate07TablesFigures(File file) async {
    final doc = PdfDocument();
    final page = doc.pages.add();

    page.graphics.drawString(
      'Quarterly Financial Summary',
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );

    // Simple table using lines and text
    final tableFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final headerFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );

    // Header row
    page.graphics.drawString(
      'Quarter',
      headerFont,
      bounds: const Rect.fromLTWH(50, 90, 100, 20),
    );
    page.graphics.drawString(
      'Revenue',
      headerFont,
      bounds: const Rect.fromLTWH(180, 90, 100, 20),
    );
    page.graphics.drawString(
      'Net Profit',
      headerFont,
      bounds: const Rect.fromLTWH(310, 90, 100, 20),
    );
    page.graphics.drawString(
      'Margin',
      headerFont,
      bounds: const Rect.fromLTWH(440, 90, 80, 20),
    );
    page.graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0)),
      const Offset(50, 110),
      const Offset(520, 110),
    );

    // Data rows
    page.graphics.drawString(
      'Q1 2026',
      tableFont,
      bounds: const Rect.fromLTWH(50, 118, 100, 18),
    );
    page.graphics.drawString(
      '\$12.4M',
      tableFont,
      bounds: const Rect.fromLTWH(180, 118, 100, 18),
    );
    page.graphics.drawString(
      '\$3.1M',
      tableFont,
      bounds: const Rect.fromLTWH(310, 118, 100, 18),
    );
    page.graphics.drawString(
      '25.0%',
      tableFont,
      bounds: const Rect.fromLTWH(440, 118, 80, 18),
    );

    page.graphics.drawString(
      'Q2 2026',
      tableFont,
      bounds: const Rect.fromLTWH(50, 138, 100, 18),
    );
    page.graphics.drawString(
      '\$14.8M',
      tableFont,
      bounds: const Rect.fromLTWH(180, 138, 100, 18),
    );
    page.graphics.drawString(
      '\$4.2M',
      tableFont,
      bounds: const Rect.fromLTWH(310, 138, 100, 18),
    );
    page.graphics.drawString(
      '28.4%',
      tableFont,
      bounds: const Rect.fromLTWH(440, 138, 80, 18),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 8. Scanned Image Only PDF (Zero native text characters)
  static Future<void> generate08ScannedImageOnly(File file) async {
    final doc = PdfDocument();
    // Add page with ONLY a bitmap image, 0 text calls
    final page = doc.pages.add();
    final img = PdfBitmap(dummyJpegHeader);
    // Covers page
    page.graphics.drawImage(img, const Rect.fromLTWH(0, 0, 595, 842));

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 9. Hybrid Mixed PDF (Page 1 has text, Page 2 has only a scan image, Page 3 has both)
  static Future<void> generate09HybridMixed(File file) async {
    final doc = PdfDocument();

    // Page 1: Native Text Only
    final p1 = doc.pages.add();
    p1.graphics.drawString(
      'Hybrid Document - Page 1 Native Text',
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );
    p1.graphics.drawString(
      'This page contains regular vector text.',
      PdfStandardFont(PdfFontFamily.helvetica, 11),
      bounds: const Rect.fromLTWH(50, 90, 490, 30),
    );

    // Page 2: Pure Scanned Image Only
    final p2 = doc.pages.add();
    final img = PdfBitmap(dummyJpegHeader);
    p2.graphics.drawImage(img, const Rect.fromLTWH(0, 0, 595, 842));

    // Page 3: Mixed (Text + Embedded Figure)
    final p3 = doc.pages.add();
    p3.graphics.drawString(
      'Page 3: Text and Embedded Chart',
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );
    p3.graphics.drawImage(img, const Rect.fromLTWH(50, 90, 300, 180));
    p3.graphics.drawString(
      'Caption for the chart above.',
      PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.italic),
      bounds: const Rect.fromLTWH(50, 275, 490, 20),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }

  // 10. Multi-Heading Styles
  static Future<void> generate10MultiHeadingStyles(File file) async {
    final doc = PdfDocument();
    final page = doc.pages.add();

    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);

    // Style A: Roman Numeral
    page.graphics.drawString(
      'III',
      PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 50, 490, 30),
    );
    page.graphics.drawString(
      'The first section under Roman numeral notation.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 85, 490, 30),
    );

    // Style B: Literary Quote Heading
    page.graphics.drawString(
      '"All happy families are alike..."',
      PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.italic),
      bounds: const Rect.fromLTWH(50, 130, 490, 25),
    );
    page.graphics.drawString(
      'Text under literary opening quotation.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 160, 490, 30),
    );

    // Style C: Date-based Journal Heading
    page.graphics.drawString(
      '14 July 1789 — Bastille Day',
      PdfStandardFont(PdfFontFamily.helvetica, 13, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 210, 490, 25),
    );
    page.graphics.drawString(
      'Entry from the historical diary.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 240, 490, 30),
    );

    // Style D: Plain Number Heading
    page.graphics.drawString(
      '4',
      PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold),
      bounds: const Rect.fromLTWH(50, 290, 490, 35),
    );
    page.graphics.drawString(
      'Plain numeral heading without word Chapter.',
      bodyFont,
      bounds: const Rect.fromLTWH(50, 330, 490, 30),
    );

    final bytes = await doc.save();
    doc.dispose();
    await file.writeAsBytes(bytes);
  }
}
