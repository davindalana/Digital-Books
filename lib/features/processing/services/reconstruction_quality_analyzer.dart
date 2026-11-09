import '../models/extracted_page_geometry.dart';
import '../models/semantic_reconstruction_models.dart';
import 'reading_order_resolver.dart';

/// D5: Evaluates semantic reconstruction fidelity and produces actionable quality scores and tier recommendations.
class ReconstructionQualityAnalyzer {
  /// Evaluates an extracted and reconstructed document.
  static ReconstructionQuality analyze({
    required DocumentExtractionResult extraction,
    required List<PageReadingOrderResult> readingOrders,
    required List<SemanticReconstructedBlock> blocks,
  }) {
    final reasons = <String>[];
    final metrics = <String, dynamic>{};

    // 1. Text Layer Analysis
    final totalPages = extraction.totalPages;
    final safeTotalPages = totalPages > 0 ? totalPages : 1;
    final scannedPages =
        extraction.layerBreakdown[PageLayerType.scannedImage] ?? 0;
    final hybridPages = extraction.layerBreakdown[PageLayerType.hybrid] ?? 0;
    final nativePages =
        extraction.layerBreakdown[PageLayerType.nativeText] ?? 0;
    final emptyPages =
        extraction.layerBreakdown[PageLayerType.emptyOrUnsupported] ?? 0;

    metrics['totalPages'] = totalPages;
    metrics['scannedPages'] = scannedPages;
    metrics['hybridPages'] = hybridPages;
    metrics['nativePages'] = nativePages;
    metrics['emptyPages'] = emptyPages;
    metrics['totalTextLines'] = extraction.totalTextLines;
    metrics['totalBlocks'] = blocks.length;

    // A. Extreme case: Scanned document without selectable text layer
    if (!extraction.hasUsableTextLayer ||
        (totalPages > 0 && scannedPages == totalPages)) {
      reasons.add(
        'Document contains 0 selectable vector text lines across all $totalPages scanned pages.',
      );
      reasons.add(
        'OCR layer is absent. High-fidelity rendering is only possible via rasterized original pages.',
      );

      return ReconstructionQuality(
        status: QualityStatus.poor,
        score: 0.1,
        reasons: reasons,
        metrics: metrics,
        recommendedTier:
            'Original PDF Reader (Scanned book without text layer)',
      );
    }

    // B. Hybrid document check
    if (scannedPages > 0) {
      final ratio = scannedPages / safeTotalPages;
      if (ratio > 0.3) {
        reasons.add(
          '$scannedPages of $totalPages pages (${(ratio * 100).toStringAsFixed(1)}%) are image scans without selectable text.',
        );
      } else {
        reasons.add(
          'Document contains $scannedPages isolated scanned page(s).',
        );
      }
    }

    // 2. Reading Order & Column Confidence Analysis
    double totalColumnConfidence = 0.0;
    int multiColumnPages = 0;
    for (final ro in readingOrders) {
      totalColumnConfidence += ro.columnConfidence;
      if (ro.layoutStructure == PageLayoutStructure.twoColumn ||
          ro.layoutStructure == PageLayoutStructure.multiColumn) {
        multiColumnPages++;
      }
    }
    final avgColumnConfidence = readingOrders.isNotEmpty
        ? totalColumnConfidence / readingOrders.length
        : 1.0;
    metrics['avgColumnConfidence'] = avgColumnConfidence;
    metrics['multiColumnPages'] = multiColumnPages;

    if (avgColumnConfidence < 0.75) {
      reasons.add(
        'Column boundaries on some pages exhibited ambiguous horizontal gutters.',
      );
    }

    // 3. Semantic Classification Quality
    int unknownCount = 0;
    int headingCount = 0;
    int bodyCount = 0;
    int imageCount = 0;
    int captionBoundCount = 0;

    for (final b in blocks) {
      if (b.type == SemanticBlockType.unknown) unknownCount++;
      if (b.isHeading) headingCount++;
      if (b.type == SemanticBlockType.bodyParagraph) bodyCount++;
      if (b.type == SemanticBlockType.image) {
        imageCount++;
        if (b.captionText != null && b.captionText!.isNotEmpty) {
          captionBoundCount++;
        }
      }
    }

    final unknownRatio = blocks.isNotEmpty ? unknownCount / blocks.length : 0.0;
    metrics['unknownCount'] = unknownCount;
    metrics['unknownRatio'] = unknownRatio;
    metrics['headingCount'] = headingCount;
    metrics['bodyCount'] = bodyCount;
    metrics['imageCount'] = imageCount;
    metrics['captionBoundCount'] = captionBoundCount;

    if (unknownRatio > 0.25) {
      reasons.add(
        '${(unknownRatio * 100).toStringAsFixed(1)}% of content blocks could not be confidently classified.',
      );
    }

    // 4. Image Extraction Completeness
    if (extraction.totalImages > 0) {
      metrics['extractedImages'] = extraction.totalImages;
      if (captionBoundCount > 0) {
        reasons.add(
          '$captionBoundCount of $imageCount embedded image(s) successfully bound to captions.',
        );
      }
    }

    // 5. Compute Consolidated Quality Score
    double score = 1.0;

    // Penalty for scanned pages
    score -= (scannedPages / safeTotalPages) * 0.6;
    // Penalty for low column confidence
    score -= (1.0 - avgColumnConfidence) * 0.2;
    // Penalty for unknown blocks
    score -= unknownRatio * 0.25;

    score = score.clamp(0.0, 1.0);
    metrics['score'] = score;

    // 6. Assign Tier & Quality Status
    QualityStatus status;
    String recommendedTier;

    if (score >= 0.80 && scannedPages == 0) {
      status = QualityStatus.good;
      recommendedTier = 'Smart Reflowable Reader';
      reasons.add(
        'High structural fidelity verified with clean vector text and consistent reading flow.',
      );
    } else if (score >= 0.50) {
      status = QualityStatus.partial;
      recommendedTier = scannedPages > 0
          ? 'Original PDF Reader (Contains mixed scanned pages)'
          : 'Smart Reflowable Reader (Minor layout ambiguities)';
      reasons.add(
        'Partial reconstruction fidelity. Reflowable available but Original PDF recommended for complex pages.',
      );
    } else {
      status = QualityStatus.poor;
      recommendedTier = 'Original PDF Reader (Low reconstruction fidelity)';
      reasons.add(
        'Reconstruction confidence below acceptable threshold. Original PDF view strongly recommended.',
      );
    }

    return ReconstructionQuality(
      status: status,
      score: score,
      reasons: reasons,
      metrics: metrics,
      recommendedTier: recommendedTier,
    );
  }
}
