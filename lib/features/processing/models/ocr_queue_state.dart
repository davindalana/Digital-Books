enum OcrQueueStatus {
  idle,
  running,
  paused,
  completed,
  cancelled,
  error,
}

/// Represents the live status of the background OCR processing queue for a book.
class OcrQueueProgress {
  final String bookId;
  final OcrQueueStatus status;
  final int currentPageIndex;
  final int totalPages;
  final int completedPages;
  final double averagePageDurationMs;
  final String? errorMessage;

  const OcrQueueProgress({
    required this.bookId,
    required this.status,
    required this.currentPageIndex,
    required this.totalPages,
    required this.completedPages,
    this.averagePageDurationMs = 0.0,
    this.errorMessage,
  });

  factory OcrQueueProgress.idle([String bookId = '']) => OcrQueueProgress(
        bookId: bookId,
        status: OcrQueueStatus.idle,
        currentPageIndex: 0,
        totalPages: 0,
        completedPages: 0,
        averagePageDurationMs: 0.0,
      );

  bool get isRunning => status == OcrQueueStatus.running;
  bool get isPaused => status == OcrQueueStatus.paused;
  bool get isCompleted => status == OcrQueueStatus.completed;
  bool get hasError => errorMessage != null || status == OcrQueueStatus.error;

  double get progressPercentage =>
      totalPages > 0 ? (completedPages / totalPages).clamp(0.0, 1.0) : 0.0;

  double get estimatedRemainingSeconds {
    final remainingPages = totalPages - completedPages;
    if (remainingPages <= 0 || averagePageDurationMs <= 0) return 0.0;
    return (remainingPages * averagePageDurationMs) / 1000.0;
  }

  OcrQueueProgress copyWith({
    String? bookId,
    OcrQueueStatus? status,
    int? currentPageIndex,
    int? totalPages,
    int? completedPages,
    double? averagePageDurationMs,
    String? errorMessage,
  }) {
    return OcrQueueProgress(
      bookId: bookId ?? this.bookId,
      status: status ?? this.status,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      totalPages: totalPages ?? this.totalPages,
      completedPages: completedPages ?? this.completedPages,
      averagePageDurationMs:
          averagePageDurationMs ?? this.averagePageDurationMs,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'OcrQueueProgress(bookId: $bookId, status: $status, page: $currentPageIndex/$totalPages, completed: $completedPages, avgMs: ${averagePageDurationMs.toStringAsFixed(1)})';
  }
}
