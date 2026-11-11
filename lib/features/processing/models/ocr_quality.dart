/// Explicit OCR readiness for Book Mode.
///
/// "OCR has run" is not the same as "OCR output is reliable". These states keep
/// the reader, library UI, and release tests from presenting unverified OCR as
/// a finished reflowable book.
enum OcrReadiness {
  /// The source already has a usable text layer; OCR is not needed.
  notRequired,

  /// No OCR page has been processed yet.
  pending,

  /// OCR is queued or currently running.
  inProgress,

  /// At least one page failed and needs retry/repair.
  failed,

  /// OCR completed but did not meet the measurable quality bar.
  insufficientQuality,

  /// Coverage, confidence, and text density meet the Book Mode bar.
  ready,
}

class OcrQualityAssessment {
  final OcrReadiness readiness;
  final int totalPages;
  final int completedPages;
  final int failedPages;
  final int processingPages;
  final int pendingPages;
  final double averageConfidence;
  final double charactersPerPage;
  final double coverage;
  final List<String> reasons;

  const OcrQualityAssessment({
    required this.readiness,
    required this.totalPages,
    required this.completedPages,
    required this.failedPages,
    required this.processingPages,
    required this.pendingPages,
    required this.averageConfidence,
    required this.charactersPerPage,
    required this.coverage,
    required this.reasons,
  });

  bool get isReliableForBookMode =>
      readiness == OcrReadiness.ready || readiness == OcrReadiness.notRequired;

  Map<String, dynamic> toJson() => {
    'readiness': readiness.name,
    'totalPages': totalPages,
    'completedPages': completedPages,
    'failedPages': failedPages,
    'processingPages': processingPages,
    'pendingPages': pendingPages,
    'averageConfidence': averageConfidence,
    'charactersPerPage': charactersPerPage,
    'coverage': coverage,
    'reliableForBookMode': isReliableForBookMode,
    'reasons': reasons,
  };
}
