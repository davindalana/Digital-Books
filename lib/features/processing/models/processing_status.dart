enum ProcessingStage {
  idle('Ready'),
  validating('Validating PDF...'),
  extractingMetadata('Reading Document Metadata...'),
  extractingText('Extracting Text & Content...'),
  detectingChapters('Analyzing Structure & Chapters...'),
  generatingCover('Creating Book Cover...'),
  generatingBook('Generating Digital Book...'),
  completed('Book Ready'),
  failed('Processing Failed');

  final String label;
  const ProcessingStage(this.label);
}

class ProcessingProgress {
  final ProcessingStage stage;
  final double progress; // 0.0 to 1.0
  final String message;
  final String? error;

  const ProcessingProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.error,
  });

  factory ProcessingProgress.initial() => const ProcessingProgress(
        stage: ProcessingStage.idle,
        progress: 0.0,
        message: 'Waiting to start...',
      );

  factory ProcessingProgress.failed(String error) => ProcessingProgress(
        stage: ProcessingStage.failed,
        progress: 0.0,
        message: 'An error occurred during processing',
        error: error,
      );

  factory ProcessingProgress.completed() => const ProcessingProgress(
        stage: ProcessingStage.completed,
        progress: 1.0,
        message: 'Book successfully imported and converted!',
      );

  ProcessingProgress copyWith({
    ProcessingStage? stage,
    double? progress,
    String? message,
    String? error,
  }) {
    return ProcessingProgress(
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: error ?? this.error,
    );
  }
}

