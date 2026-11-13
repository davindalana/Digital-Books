import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/file_storage_service.dart';
import '../../reader/domain/models/book_document.dart';
import '../models/processing_manifest.dart';
import 'annotation_remapper.dart';
import 'processed_artifact_inspector.dart';

typedef ProcessedDocumentBuilder = Future<BookDocument?> Function();

enum ReprocessStatus {
  reprocessed,
  alreadyCurrent,
  rejectedIncompleteOutput,
  failed,
  missingSource,
}

class ReprocessOutcome {
  final ReprocessStatus status;
  final String? message;
  final ProcessedArtifactStatus? before;
  final ProcessedArtifactStatus? after;
  final int relocatedBookmarks;
  final int relocatedHighlights;
  final int unresolvedBookmarks;
  final int unresolvedHighlights;
  final bool progressMapped;
  final bool rolledBack;

  const ReprocessOutcome({
    required this.status,
    this.message,
    this.before,
    this.after,
    this.relocatedBookmarks = 0,
    this.relocatedHighlights = 0,
    this.unresolvedBookmarks = 0,
    this.unresolvedHighlights = 0,
    this.progressMapped = false,
    this.rolledBack = false,
  });

  bool get succeeded => status == ReprocessStatus.reprocessed;
}

/// Reprocesses a saved Book Mode artifact while preserving the immutable
/// original PDF and all user annotations.
///
/// The new document is validated before anything is replaced. A `.bak` file and
/// an in-progress marker make the file swap recoverable if the process is
/// interrupted; any database failure restores the previous artifact.
class BookReprocessor {
  final DatabaseService dbService;

  const BookReprocessor(this.dbService);

  Future<ReprocessOutcome> reprocess({
    required Book book,
    required ProcessedDocumentBuilder buildDocument,
    bool force = false,
    bool verifySourceHash = false,
  }) async {
    // A marker or backup left by an interrupted reprocess is resolved before
    // any freshness decision is made.
    if (book.processedBookPath != null) {
      await ProcessedArtifactInspector.recoverInterrupted(
        book.processedBookPath,
      );
    }

    final before = await ProcessedArtifactInspector.inspectPath(
      book.processedBookPath,
      currentSourcePath: book.originalPdfPath,
      verifySourceHash: verifySourceHash,
    );

    if (before.state == ProcessedArtifactState.current && !force) {
      return ReprocessOutcome(
        status: ReprocessStatus.alreadyCurrent,
        before: before,
        after: before,
        message: 'Processed document is already current.',
      );
    }

    final source = File(book.originalPdfPath);
    if (!await source.exists()) {
      return ReprocessOutcome(
        status: ReprocessStatus.missingSource,
        before: before,
        message: 'Original PDF is missing: ${book.originalPdfPath}',
      );
    }

    BookDocument? rebuilt;
    try {
      rebuilt = await buildDocument();
    } catch (error) {
      return ReprocessOutcome(
        status: ReprocessStatus.failed,
        before: before,
        message: 'Reconstruction failed: $error',
      );
    }

    if (rebuilt == null) {
      return ReprocessOutcome(
        status: ReprocessStatus.failed,
        before: before,
        message: 'Reconstruction produced no document.',
      );
    }

    final stamped = await _stamp(rebuilt, book, before);

    final previous = await _readDocument(book.processedBookPath);
    final validationError = validateCandidate(
      candidate: stamped,
      previous: previous,
      force: force,
    );
    if (validationError != null) {
      return ReprocessOutcome(
        status: ReprocessStatus.rejectedIncompleteOutput,
        before: before,
        message: validationError,
      );
    }

    final targetPath = await _targetPath(book);
    final target = File(targetPath);
    final oldBytes = await target.exists() ? await target.readAsBytes() : null;

    final bookmarks = await dbService.getBookmarksForBook(book.id);
    final highlights = await dbService.getHighlightsForBook(book.id);
    final progress = await dbService.getProgress(book.id);

    final remap = AnnotationRemapper.remap(
      oldDocument: previous ?? stamped,
      newDocument: stamped,
      bookmarks: bookmarks,
      highlights: highlights,
      progress: progress,
    );

    final backup = File('$targetPath.bak');
    final marker = File('$targetPath.reprocess');

    Map<String, Object?> markerPayload(String phase) => {
      'bookId': book.id,
      'phase': phase,
      'from': before.manifest?.pipelineVersion,
      'to': ProcessingManifest.currentPipelineVersion,
      'startedAt': DateTime.now().toIso8601String(),
    };

    try {
      await marker.writeAsString(
        jsonEncode(markerPayload('prepared')),
        flush: true,
      );
      if (oldBytes != null) {
        await backup.writeAsBytes(oldBytes, flush: true);
      }

      await FileStorageService.writeFileAtomic(target, stamped.toJsonString());

      await dbService.applyReprocessingUpdates(
        bookId: book.id,
        chapters: _chapterCompanions(stamped, book.id),
        bookmarks: remap.bookmarkUpdates,
        highlights: remap.highlightUpdates,
        progress: remap.progressUpdate,
      );

      if (book.processedBookPath != targetPath) {
        await dbService.updateBookProcessedPath(book.id, targetPath);
      }

      // The artifact and the database now agree. Record that fact before
      // cleanup so an interruption at this point keeps the new file instead of
      // restoring an artifact whose anchors no longer match the database.
      await marker.writeAsString(
        jsonEncode(markerPayload('committed')),
        flush: true,
      );

      if (await marker.exists()) await marker.delete();
      if (await backup.exists()) await backup.delete();
    } catch (error) {
      final rolledBack = await _rollback(target, backup, oldBytes);
      if (await marker.exists()) {
        try {
          await marker.delete();
        } catch (_) {}
      }
      return ReprocessOutcome(
        status: ReprocessStatus.failed,
        before: before,
        message: 'Reprocessing failed and was rolled back: $error',
        rolledBack: rolledBack,
      );
    }

    final after = await ProcessedArtifactInspector.inspectPath(
      targetPath,
      currentSourcePath: book.originalPdfPath,
      verifySourceHash: verifySourceHash,
    );

    return ReprocessOutcome(
      status: ReprocessStatus.reprocessed,
      before: before,
      after: after,
      relocatedBookmarks: remap.relocatedBookmarks,
      relocatedHighlights: remap.relocatedHighlights,
      unresolvedBookmarks: remap.unresolvedBookmarks,
      unresolvedHighlights: remap.unresolvedHighlights,
      progressMapped: remap.progressMapped,
    );
  }

  /// Validates that a candidate is complete enough to replace an existing
  /// artifact. Returns `null` when the candidate is acceptable.
  static String? validateCandidate({
    required BookDocument candidate,
    BookDocument? previous,
    bool force = false,
  }) {
    if (candidate.chapters.isEmpty) {
      return 'Candidate has no chapters.';
    }

    final textBlocks = candidate.chapters
        .expand((c) => c.blocks)
        .where((b) => b.text.trim().isNotEmpty)
        .toList();
    if (textBlocks.isEmpty) {
      return 'Candidate has no readable text.';
    }

    final status = candidate.metadata['processingStatus'];
    if (status == 'requiresOcr' || status == 'reconstructionFailed') {
      return 'Candidate is incomplete ($status).';
    }

    if (!force && previous != null) {
      final previousText = previous.chapters
          .expand((c) => c.blocks)
          .where((b) => b.text.trim().isNotEmpty)
          .length;
      if (previousText > 20 && textBlocks.length * 2 < previousText) {
        return 'Candidate contains less than half of the previous text '
            '(${textBlocks.length} vs $previousText blocks).';
      }
    }

    return null;
  }

  Future<BookDocument> _stamp(
    BookDocument document,
    Book book,
    ProcessedArtifactStatus before,
  ) async {
    final metadata = Map<String, dynamic>.of(document.metadata);
    final manifest = ProcessingManifest(
      pipelineVersion: ProcessingManifest.currentPipelineVersion,
      artifactSchemaVersion: ProcessingManifest.currentArtifactSchemaVersion,
      processedAt: DateTime.now().toIso8601String(),
      source: document.isScanned ? 'ocr' : 'nativeText',
      sourceFileSize: await File(book.originalPdfPath).length(),
      sourceTotalPages: document.totalPages,
      ocrCompletedPages: (metadata['ocrCompletedPages'] as num?)?.toInt(),
    );
    metadata
      ..addAll(manifest.toMetadata())
      ..['reprocessedAt'] = DateTime.now().toIso8601String()
      ..['reprocessedFrom'] = before.manifest?.pipelineVersion ?? 'unversioned';

    return document.copyWith(metadata: metadata);
  }

  Future<BookDocument?> _readDocument(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return BookDocument.fromJsonString(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<String> _targetPath(Book book) async {
    if (book.processedBookPath != null &&
        book.processedBookPath!.trim().isNotEmpty) {
      return book.processedBookPath!;
    }
    final dir = await FileStorageService.getBooksDirectory();
    return p.join(dir.path, '${book.id}.json');
  }

  static List<ChaptersCompanion> _chapterCompanions(
    BookDocument document,
    String bookId,
  ) => document.chapters.asMap().entries.map((entry) {
    return ChaptersCompanion(
      id: Value(entry.value.id),
      bookId: Value(bookId),
      title: Value(entry.value.title),
      chapterIndex: Value(entry.key),
      startPosition: const Value(0),
      endPosition: Value(entry.value.blocks.length),
    );
  }).toList();

  static Future<bool> _rollback(
    File target,
    File backup,
    List<int>? oldBytes,
  ) async {
    try {
      if (oldBytes != null) {
        final temp = File('${target.path}.restore');
        await temp.writeAsBytes(oldBytes, flush: true);
        await temp.rename(target.path);
      } else if (await target.exists()) {
        await target.delete();
      }
      if (await backup.exists()) await backup.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
