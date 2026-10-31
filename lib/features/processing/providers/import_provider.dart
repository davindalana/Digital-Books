import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../models/processing_status.dart';
import '../services/pdf_processing_pipeline.dart';

class ImportState {
  final bool isProcessing;
  final ProcessingProgress progress;
  final Book? completedBook;
  final String? errorMessage;

  const ImportState({
    this.isProcessing = false,
    required this.progress,
    this.completedBook,
    this.errorMessage,
  });

  factory ImportState.idle() =>
      ImportState(isProcessing: false, progress: ProcessingProgress.initial());

  ImportState copyWith({
    bool? isProcessing,
    ProcessingProgress? progress,
    Book? completedBook,
    String? errorMessage,
  }) {
    return ImportState(
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      completedBook: completedBook ?? this.completedBook,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ImportNotifier extends StateNotifier<ImportState> {
  final PdfProcessingPipeline _pipeline;

  ImportNotifier(this._pipeline) : super(ImportState.idle());

  void cancel() {
    _pipeline.cancel();
    state = state.copyWith(
      isProcessing: false,
      progress: ProcessingProgress.initial(),
      errorMessage: 'Import cancelled',
    );
  }

  Future<Book?> importFile(
    File file, {
    String? customTitle,
    String? customAuthor,
  }) async {
    state = ImportState(
      isProcessing: true,
      progress: const ProcessingProgress(
        stage: ProcessingStage.validating,
        progress: 0.05,
        message: 'Validating file...',
      ),
    );

    try {
      final book = await _pipeline.processAndImportPdf(
        pdfFile: file,
        customTitle: customTitle,
        customAuthor: customAuthor,
        onProgress: (p) {
          state = state.copyWith(progress: p);
        },
      );

      state = ImportState(
        isProcessing: false,
        progress: ProcessingProgress.completed(),
        completedBook: book,
      );
      return book;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: ProcessingProgress.failed(e.toString()),
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void reset() {
    state = ImportState.idle();
  }
}

final pdfProcessingPipelineProvider = Provider<PdfProcessingPipeline>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return PdfProcessingPipeline(dbService);
});

final importNotifierProvider =
    StateNotifierProvider<ImportNotifier, ImportState>((ref) {
      final pipeline = ref.watch(pdfProcessingPipelineProvider);
      return ImportNotifier(pipeline);
    });
