import '../../../core/database/app_database.dart';
import '../models/ocr_quality.dart';

/// Evaluates OCR coverage and text quality before Book Mode is presented as
/// reliable.
///
/// Thresholds are deliberately explicit and conservative:
/// * at least 95% of pages completed,
/// * no failed pages,
/// * average confidence >= 0.70,
/// * at least 40 characters per completed page.
///
/// They are product guidance, not an OCR engine benchmark. Original PDF remains
/// the authoritative view whenever the gate is not `ready`.
class OcrQualityGate {
  static const double minCoverage = 0.95;
  static const double minAverageConfidence = 0.70;
  static const double minCharactersPerPage = 40.0;

  static OcrQualityAssessment assess({
    required int totalPages,
    required List<OcrPage> pages,
    required bool hasSelectableTextLayer,
    required bool isScannedSource,
  }) {
    final safeTotal = totalPages > 0 ? totalPages : pages.length;
    final completed = pages.where((p) => p.status == 'completed').toList();
    final failed = pages.where((p) => p.status == 'failed').length;
    final processing = pages.where((p) => p.status == 'processing').length;
    final pending = pages.where((p) => p.status == 'pending').length;
    final coverage = safeTotal == 0 ? 0.0 : completed.length / safeTotal;

    final averageConfidence = completed.isEmpty
        ? 0.0
        : completed.fold<double>(0, (sum, p) => sum + p.confidence) /
              completed.length;
    final totalCharacters = completed.fold<int>(
      0,
      (sum, p) => sum + p.charCount,
    );
    final charactersPerPage = completed.isEmpty
        ? 0.0
        : totalCharacters / completed.length;

    final reasons = <String>[];

    // A native text layer is the best source. OCR is supplementary for hybrid
    // documents and irrelevant for fully digital ones.
    if (hasSelectableTextLayer && !isScannedSource) {
      if (pending > 0 || processing > 0) {
        reasons.add(
          'The source already has selectable text; OCR is optional and still '
          'in progress for $pending/$processing page(s).',
        );
      }
      return OcrQualityAssessment(
        readiness: OcrReadiness.notRequired,
        totalPages: safeTotal,
        completedPages: completed.length,
        failedPages: failed,
        processingPages: processing,
        pendingPages: pending,
        averageConfidence: averageConfidence,
        charactersPerPage: charactersPerPage,
        coverage: coverage,
        reasons: reasons,
      );
    }

    if (failed > 0) {
      reasons.add('$failed page(s) failed OCR and must be retried.');
      return _result(
        OcrReadiness.failed,
        safeTotal,
        completed.length,
        failed,
        processing,
        pending,
        averageConfidence,
        charactersPerPage,
        coverage,
        reasons,
      );
    }

    if (completed.isEmpty) {
      final readiness = processing > 0
          ? OcrReadiness.inProgress
          : OcrReadiness.pending;
      reasons.add(
        readiness == OcrReadiness.inProgress
            ? 'OCR is currently running; no completed page is available yet.'
            : 'No OCR page has been processed for this scanned document.',
      );
      return _result(
        readiness,
        safeTotal,
        completed.length,
        failed,
        processing,
        pending,
        averageConfidence,
        charactersPerPage,
        coverage,
        reasons,
      );
    }

    if (coverage < minCoverage) {
      reasons.add(
        'Only ${(coverage * 100).toStringAsFixed(1)}% of pages are OCR-complete '
        '(minimum ${(minCoverage * 100).toStringAsFixed(0)}%).',
      );
      final readiness = processing > 0 || pending > 0
          ? OcrReadiness.inProgress
          : OcrReadiness.pending;
      return _result(
        readiness,
        safeTotal,
        completed.length,
        failed,
        processing,
        pending,
        averageConfidence,
        charactersPerPage,
        coverage,
        reasons,
      );
    }

    if (averageConfidence < minAverageConfidence) {
      reasons.add(
        'Average OCR confidence ${averageConfidence.toStringAsFixed(2)} is '
        'below the ${minAverageConfidence.toStringAsFixed(2)} threshold.',
      );
    }
    if (charactersPerPage < minCharactersPerPage) {
      reasons.add(
        'Only ${charactersPerPage.toStringAsFixed(1)} characters per completed '
        'page (minimum ${minCharactersPerPage.toStringAsFixed(0)}).',
      );
    }

    if (averageConfidence < minAverageConfidence ||
        charactersPerPage < minCharactersPerPage) {
      return _result(
        OcrReadiness.insufficientQuality,
        safeTotal,
        completed.length,
        failed,
        processing,
        pending,
        averageConfidence,
        charactersPerPage,
        coverage,
        reasons,
      );
    }

    reasons.add(
      'OCR passed the Book Mode gate: ${(coverage * 100).toStringAsFixed(1)}% '
      'coverage, confidence ${averageConfidence.toStringAsFixed(2)}, '
      '${charactersPerPage.toStringAsFixed(0)} characters/page.',
    );
    return _result(
      OcrReadiness.ready,
      safeTotal,
      completed.length,
      failed,
      processing,
      pending,
      averageConfidence,
      charactersPerPage,
      coverage,
      reasons,
    );
  }

  static OcrQualityAssessment _result(
    OcrReadiness readiness,
    int totalPages,
    int completedPages,
    int failedPages,
    int processingPages,
    int pendingPages,
    double averageConfidence,
    double charactersPerPage,
    double coverage,
    List<String> reasons,
  ) => OcrQualityAssessment(
    readiness: readiness,
    totalPages: totalPages,
    completedPages: completedPages,
    failedPages: failedPages,
    processingPages: processingPages,
    pendingPages: pendingPages,
    averageConfidence: averageConfidence,
    charactersPerPage: charactersPerPage,
    coverage: coverage,
    reasons: reasons,
  );
}
