import 'dart:math' as math;
import '../models/extracted_page_geometry.dart';

/// Resolved column structure classification for a single page.
enum PageLayoutStructure {
  singleColumn,
  twoColumn,
  multiColumn,
  ambiguousFallback,
}

/// Result of reading order resolution on an individual page.
class PageReadingOrderResult {
  final int pageIndex;
  final PageLayoutStructure layoutStructure;
  final List<ExtractedTextLine> orderedLines;
  final double columnConfidence;
  final double? detectedGutterX;
  final double? detectedGutterWidth;

  const PageReadingOrderResult({
    required this.pageIndex,
    required this.layoutStructure,
    required this.orderedLines,
    required this.columnConfidence,
    this.detectedGutterX,
    this.detectedGutterWidth,
  });
}

/// D1: Resolves natural reading order of text lines across single and multi-column pages.
class ReadingOrderResolver {
  /// Minimum gutter width in points to qualify as a distinct column separator.
  static const double minGutterWidth = 14.0;

  /// Resolves the reading order for a single extracted page geometry.
  static PageReadingOrderResult resolvePage(ExtractedPageGeometry page) {
    if (page.lines.isEmpty) {
      return PageReadingOrderResult(
        pageIndex: page.pageIndex,
        layoutStructure: PageLayoutStructure.singleColumn,
        orderedLines: const [],
        columnConfidence: 1.0,
      );
    }

    if (page.lines.length <= 2) {
      final sorted = List<ExtractedTextLine>.from(page.lines)
        ..sort((a, b) => _compareLinesSingleColumn(a, b));
      return PageReadingOrderResult(
        pageIndex: page.pageIndex,
        layoutStructure: PageLayoutStructure.singleColumn,
        orderedLines: sorted,
        columnConfidence: 1.0,
      );
    }

    final pageWidth = page.pageSize.width > 0
        ? page.pageSize.width
        : page.lines.map((l) => l.bounds.right).reduce(math.max) + 50.0;

    // 1. Separate full-width banners / titles that span across columns
    final fullWidthLines = <ExtractedTextLine>[];
    final candidateBodyLines = <ExtractedTextLine>[];

    for (final line in page.lines) {
      final width = line.bounds.width;
      final spansCenter = line.bounds.left < pageWidth * 0.42 &&
          line.bounds.right > pageWidth * 0.58;
      final isWide = width >= pageWidth * 0.65;

      if (spansCenter || isWide) {
        fullWidthLines.add(line);
      } else {
        candidateBodyLines.add(line);
      }
    }

    // 2. Attempt two-column partitioning on candidate body lines
    if (candidateBodyLines.length >= 4) {
      final twoColResult = _tryPartitionTwoColumns(
        candidateBodyLines,
        pageWidth,
      );

      if (twoColResult != null) {
        final col1Lines = twoColResult.col1;
        final col2Lines = twoColResult.col2;

        col1Lines.sort((a, b) => _compareLinesSingleColumn(a, b));
        col2Lines.sort((a, b) => _compareLinesSingleColumn(a, b));

        final colMinTop = math.min(
          col1Lines.first.bounds.top,
          col2Lines.first.bounds.top,
        );
        final colMaxBottom = math.max(
          col1Lines.last.bounds.bottom,
          col2Lines.last.bounds.bottom,
        );

        // Separate banners into top banners (before columns) and bottom banners (after columns)
        final topBanners = <ExtractedTextLine>[];
        final bottomBanners = <ExtractedTextLine>[];

        for (final banner in fullWidthLines) {
          if (banner.bounds.top < colMinTop + 15.0) {
            topBanners.add(banner);
          } else if (banner.bounds.top >= colMaxBottom - 15.0) {
            bottomBanners.add(banner);
          } else {
            // Banner interleaved between columns; place before columns
            topBanners.add(banner);
          }
        }

        topBanners.sort((a, b) => _compareLinesSingleColumn(a, b));
        bottomBanners.sort((a, b) => _compareLinesSingleColumn(a, b));

        // Sequence: Top Banners -> Column 1 (top to bottom) -> Column 2 (top to bottom) -> Bottom Banners
        final combined = <ExtractedTextLine>[
          ...topBanners,
          ...col1Lines,
          ...col2Lines,
          ...bottomBanners,
        ];

        return PageReadingOrderResult(
          pageIndex: page.pageIndex,
          layoutStructure: PageLayoutStructure.twoColumn,
          orderedLines: combined,
          columnConfidence: twoColResult.confidence,
          detectedGutterX: twoColResult.gutterCenterX,
          detectedGutterWidth: twoColResult.gutterWidth,
        );
      }
    }

    // 3. Fallback: Single-column ordering (Y ascending, then X ascending for same line)
    final allSorted = List<ExtractedTextLine>.from(page.lines)
      ..sort((a, b) => _compareLinesSingleColumn(a, b));

    return PageReadingOrderResult(
      pageIndex: page.pageIndex,
      layoutStructure: PageLayoutStructure.singleColumn,
      orderedLines: allSorted,
      columnConfidence: 0.95,
    );
  }

  /// Compares two lines in single-column mode: primary sort by Y, secondary by X.
  static int _compareLinesSingleColumn(
    ExtractedTextLine a,
    ExtractedTextLine b,
  ) {
    const baselineTolerance = 4.0;
    final yDiff = a.bounds.top - b.bounds.top;
    if (yDiff.abs() <= baselineTolerance) {
      return a.bounds.left.compareTo(b.bounds.left);
    }
    return yDiff < 0 ? -1 : 1;
  }

  /// Attempts to partition body lines into two distinct columns separated by a vertical gutter.
  static _TwoColumnPartition? _tryPartitionTwoColumns(
    List<ExtractedTextLine> lines,
    double pageWidth,
  ) {
    final leftEdges = lines.map((l) => l.bounds.left).toList()..sort();
    final rightEdges = lines.map((l) => l.bounds.right).toList()..sort();

    final minLeft = leftEdges.first;
    final maxRight = rightEdges.last;
    final spanWidth = maxRight - minLeft;

    if (spanWidth < pageWidth * 0.4) {
      return null; // Content too narrow to be multi-column
    }

    // Search for a candidate gutter boundary between X = 0.3 * pageWidth and 0.7 * pageWidth
    final searchMinX = minLeft + spanWidth * 0.3;
    final searchMaxX = minLeft + spanWidth * 0.7;

    double bestGutterLeft = 0.0;
    double bestGutterRight = 0.0;
    double maxGutterWidth = 0.0;

    // Test a grid of candidate split points
    final step = 2.0;
    for (double testX = searchMinX; testX <= searchMaxX; testX += step) {
      // Find the maximum right edge of lines strictly to the left of testX
      final leftLines = lines.where((l) => l.bounds.right <= testX).toList();
      // Find the minimum left edge of lines strictly to the right of testX
      final rightLines = lines.where((l) => l.bounds.left >= testX).toList();

      // Ensure no lines straddle testX
      final straddling = lines.where(
        (l) => l.bounds.left < testX && l.bounds.right > testX,
      );

      if (straddling.isEmpty && leftLines.length >= 2 && rightLines.length >= 2) {
        final gLeft = leftLines.map((l) => l.bounds.right).reduce(math.max);
        final gRight = rightLines.map((l) => l.bounds.left).reduce(math.min);
        final gWidth = gRight - gLeft;

        if (gWidth > maxGutterWidth) {
          maxGutterWidth = gWidth;
          bestGutterLeft = gLeft;
          bestGutterRight = gRight;
        }
      }
    }

    if (maxGutterWidth >= minGutterWidth) {
      final gutterCenter = (bestGutterLeft + bestGutterRight) / 2.0;
      final col1 = lines.where((l) => l.bounds.right <= gutterCenter).toList();
      final col2 = lines.where((l) => l.bounds.left >= gutterCenter).toList();

      // If any line slightly intersected the exact center, assign by majority overlap
      final remaining = lines.where(
        (l) => !col1.contains(l) && !col2.contains(l),
      );
      for (final r in remaining) {
        if (r.bounds.center.dx < gutterCenter) {
          col1.add(r);
        } else {
          col2.add(r);
        }
      }

      if (col1.isNotEmpty && col2.isNotEmpty) {
        final confidence = math.min(1.0, 0.7 + (maxGutterWidth / 40.0) * 0.3);
        return _TwoColumnPartition(
          col1: col1,
          col2: col2,
          gutterCenterX: gutterCenter,
          gutterWidth: maxGutterWidth,
          confidence: confidence,
        );
      }
    }

    return null;
  }

  /// Resolves reading order for an entire document across all pages.
  static List<PageReadingOrderResult> resolveDocument(
    DocumentExtractionResult extraction,
  ) {
    return extraction.pages.map((p) => resolvePage(p)).toList();
  }
}

class _TwoColumnPartition {
  final List<ExtractedTextLine> col1;
  final List<ExtractedTextLine> col2;
  final double gutterCenterX;
  final double gutterWidth;
  final double confidence;

  _TwoColumnPartition({
    required this.col1,
    required this.col2,
    required this.gutterCenterX,
    required this.gutterWidth,
    required this.confidence,
  });
}

