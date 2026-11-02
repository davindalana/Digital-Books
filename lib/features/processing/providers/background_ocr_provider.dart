import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../models/ocr_queue_state.dart';
import '../services/apple_vision_ocr_service.dart';
import '../services/background_ocr_queue.dart';
import '../services/ocr_semantic_pipeline.dart';

final appleVisionOcrServiceProvider = Provider<AppleVisionOcrService>((ref) {
  return const AppleVisionOcrService();
});

final ocrSemanticPipelineProvider = Provider<OcrSemanticPipeline>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return OcrSemanticPipeline(dbService);
});

final backgroundOcrQueueProvider = Provider<BackgroundOcrQueue>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final ocrService = ref.watch(appleVisionOcrServiceProvider);
  final semanticPipeline = ref.watch(ocrSemanticPipelineProvider);
  final queue = BackgroundOcrQueue(
    dbService: dbService,
    ocrService: ocrService,
    semanticPipeline: semanticPipeline,
  );
  ref.onDispose(() => queue.dispose());
  return queue;
});

final ocrQueueProgressStreamProvider = StreamProvider<OcrQueueProgress>((ref) {
  final queue = ref.watch(backgroundOcrQueueProvider);
  return queue.progressStream;
});

final bookOcrPagesStreamProvider = StreamProvider.family<List<OcrPage>, String>(
  (ref, bookId) {
    final dbService = ref.watch(databaseServiceProvider);
    return dbService.watchOcrPagesForBook(bookId);
  },
);
