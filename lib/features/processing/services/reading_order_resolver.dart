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
      final sorted = _sortLinesSingleColumn(page.lines);
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
    final pageHeight = page.pageSize.height > 0
        ? page.pageSize.height
        : page.lines.map((l) => l.bounds.bottom).reduce(math.max) + 50.0;

    // 1. Separate running chrome (top header & bottom footer/page number)
    final headerLines = <ExtractedTextLine>[];
    final footerLines = <ExtractedTextLine>[];
    final nonChromeLines = <ExtractedTextLine>[];

    final topHeaderThreshold = math.min(65.0, pageHeight * 0.10);
    final bottomFooterThreshold = math.max(pageHeight - 65.0, pageHeight * 0.90);

    for (final line in page.lines) {
      if (line.bounds.bottom <= topHeaderThreshold && line.bounds.height < 25.0) {
        headerLines.add(line);
      } else if (line.bounds.top >= bottomFooterThreshold && line.bounds.height < 25.0) {
        footerLines.add(line);
      } else {
        nonChromeLines.add(line);
      }
    }

    // 2. Separate full-width banners / titles that span across columns
    final fullWidthLines = <ExtractedTextLine>[];
    final candidateBodyLines = <ExtractedTextLine>[];

    for (final line in nonChromeLines) {
      final width = line.bounds.width;
      final spansCenter = line.bounds.left < pageWidth * 0.40 &&
          line.bounds.right > pageWidth * 0.60;
      final isWide = width >= pageWidth * 0.68;

      if (spansCenter || isWide) {
        fullWidthLines.add(line);
      } else {
        candidateBodyLines.add(line);
      }
    }

    // 3. Attempt two-column partitioning on candidate body lines
    if (candidateBodyLines.length >= 4) {
      final twoColResult = _tryPartitionTwoColumns(
        candidateBodyLines,
        pageWidth,
      );

      if (twoColResult != null) {
        final col1Lines = _sortLinesSingleColumn(twoColResult.col1);
        final col2Lines = _sortLinesSingleColumn(twoColResult.col2);

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
            topBanners.add(banner);
          }
        }

        final sortedTopBanners = _sortLinesSingleColumn(topBanners);
        final sortedBottomBanners = _sortLinesSingleColumn(bottomBanners);
        final sortedHeaders = _sortLinesSingleColumn(headerLines);
        final sortedFooters = _sortLinesSingleColumn(footerLines);

        // Sequence: Running Headers -> Top Banners -> Column 1 (top to bottom) -> Column 2 (top to bottom) -> Bottom Banners -> Running Footers
        final combined = <ExtractedTextLine>[
          ...sortedHeaders,
          ...sortedTopBanners,
          ...col1Lines,
          ...col2Lines,
          ...sortedBottomBanners,
          ...sortedFooters,
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

    // 4. Single-column ordering (Robust baseline clustering)
    final allSorted = _sortLinesSingleColumn(page.lines);

    return PageReadingOrderResult(
      pageIndex: page.pageIndex,
      layoutStructure: PageLayoutStructure.singleColumn,
      orderedLines: allSorted,
      columnConfidence: 0.95,
    );
  }

  /// Sorts lines in single-column mode using baseline clustering.
  /// Lines that share a common vertical band (vertical overlap >= 45% of height)
  /// are grouped together and sorted left-to-right.
  /// Visual bands are sorted top-to-bottom.
  static List<ExtractedTextLine> _sortLinesSingleColumn(
    List<ExtractedTextLine> lines,
  ) {
    if (lines.length <= 1) return List.from(lines);

    // Initial sort by top Y coordinate
    final rawList = List<ExtractedTextLine>.from(lines)
      ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));

    final bands = <List<ExtractedTextLine>>[];

    for (final line in rawList) {
      bool placedInBand = false;
      for (final band in bands) {
        final refLine = band.first;
        final overlapTop = math.max(line.bounds.top, refLine.bounds.top);
        final overlapBottom = math.min(line.bounds.bottom, refLine.bounds.bottom);
        final overlapHeight = overlapBottom - overlapTop;

        final minHeight = math.min(line.bounds.height, refLine.bounds.height);
        if (minHeight > 0 && overlapHeight >= minHeight * 0.45) {
          band.add(line);
          placedInBand = true;
          break;
        }
      }

      if (!placedInBand) {
        bands.add([line]);
      }
    }

    // Sort bands top-to-bottom by average top coordinate
    bands.sort((a, b) {
      final aAvg = a.map((l) => l.bounds.top).reduce((v, e) => v + e) / a.length;
      final bAvg = b.map((l) => l.bounds.top).reduce((v, e) => v + e) / b.length;
      return aAvg.compareTo(bAvg);
    });

    // Within each band, sort lines strictly left-to-right
    final sortedLines = <ExtractedTextLine>[];
    for (final band in bands) {
      band.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      sortedLines.addAll(band);
    }

    return sortedLines;
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

