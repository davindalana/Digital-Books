import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../reader/models/book_document.dart';
import '../models/processing_manifest.dart';

/// Freshness of a persisted Book Mode artifact.
enum ProcessedArtifactState {
  /// Written by the current pipeline and artifact schema.
  current,

  /// Written by an older pipeline/schema and worth reprocessing.
  stale,

  /// No processed document exists yet.
  missing,

  /// The file exists but cannot be parsed as a Book Mode document.
  unreadable,

  /// Written by a newer version of the application than the running one.
  newer,

  /// Structurally valid but incomplete (OCR required or reconstruction failed).
  incomplete,
}

enum ArtifactRecoveryResult { none, restoredBackup, cleanedBackup, cleanedTemp }

class ProcessedArtifactStatus {
  final ProcessedArtifactState state;
  final ProcessingManifest? manifest;
  final String? path;
  final String? message;
  final String? processingStatus;
  final int chapterCount;
  final int blockCount;

  const ProcessedArtifactStatus({
    required this.state,
    this.manifest,
    this.path,
    this.message,
    this.processingStatus,
    this.chapterCount = 0,
    this.blockCount = 0,
  });

  bool get needsReprocessing =>
      state == ProcessedArtifactState.stale ||
      state == ProcessedArtifactState.incomplete ||
      state == ProcessedArtifactState.unreadable;

  bool get isUsable =>
      state == ProcessedArtifactState.current ||
      state == ProcessedArtifactState.stale ||
      state == ProcessedArtifactState.newer;

  String get label {
    switch (state) {
      case ProcessedArtifactState.current:
        return 'Mode Buku v${manifest?.pipelineVersion ?? '?'} (terbaru)';
      case ProcessedArtifactState.stale:
        return 'Mode Buku perlu diperbarui';
      case ProcessedArtifactState.missing:
        return 'Mode Buku belum tersedia';
      case ProcessedArtifactState.unreadable:
        return 'Mode Buku rusak';
      case ProcessedArtifactState.newer:
        return 'Mode Buku dibuat aplikasi versi lebih baru';
      case ProcessedArtifactState.incomplete:
        return 'Mode Buku belum lengkap';
    }
  }
}

/// Inspects saved Book Mode artifacts without mutating them.
class ProcessedArtifactInspector {
  /// Reads [path] and classifies its freshness.
  ///
  /// [currentSourcePath] is optional. When supplied together with
  /// [verifySourceHash], a changed source PDF marks the artifact stale.
  static Future<ProcessedArtifactStatus> inspectPath(
    String? path, {
    String? currentSourcePath,
    bool verifySourceHash = false,
  }) async {
    if (path == null || path.trim().isEmpty) {
      return const ProcessedArtifactStatus(
        state: ProcessedArtifactState.missing,
        message: 'No processed document has been generated for this book.',
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      return ProcessedArtifactStatus(
        state: ProcessedArtifactState.missing,
        path: path,
        message: 'Processed document file is missing: $path',
      );
    }

    final String raw;
    try {
      raw = await file.readAsString();
    } catch (error) {
      return ProcessedArtifactStatus(
        state: ProcessedArtifactState.unreadable,
        path: path,
        message: 'Processed document could not be read: $error',
      );
    }

    final status = await inspectJson(raw, path: path);
    if (status.manifest?.sourceFileSize != null && currentSourcePath != null) {
      try {
        final source = File(currentSourcePath);
        if (await source.exists() &&
            await source.length() != status.manifest!.sourceFileSize) {
          return _withState(
            status,
            ProcessedArtifactState.stale,
            'Original PDF size changed since this document was processed.',
          );
        }
      } catch (_) {
        // Size verification is best-effort; never make an artifact unreadable
        // because the source file could not be stat'ed.
      }
    }

    final manifest = status.manifest;
    if (verifySourceHash &&
        manifest?.sourceFileHash != null &&
        currentSourcePath != null) {
      try {
        final source = File(currentSourcePath);
        if (await source.exists()) {
          final actual = await _sha256(source);
          if (actual != manifest!.sourceFileHash) {
            return _withState(
              status,
              ProcessedArtifactState.stale,
              'Original PDF content changed since this document was processed.',
            );
          }
        }
      } catch (_) {}
    }

    return status;
  }

  /// Classifies already-loaded JSON. Exposed for tests and callers that have
  /// the artifact bytes in memory.
  static Future<ProcessedArtifactStatus> inspectJson(
    String raw, {
    String? path,
  }) async {
    try {
      final doc = BookDocument.fromJsonString(raw);
      final manifest = ProcessingManifest.fromMetadata(doc.metadata);
      final status = doc.metadata['processingStatus'] as String?;
      final blockCount = doc.chapters.fold<int>(
        0,
        (sum, chapter) => sum + chapter.blocks.length,
      );
      final base = ProcessedArtifactStatus(
        state: ProcessedArtifactState.current,
        manifest: manifest,
        path: path,
        processingStatus: status,
        chapterCount: doc.chapters.length,
        blockCount: blockCount,
      );

      if (doc.chapters.isEmpty || blockCount == 0) {
        return _withState(
          base,
          ProcessedArtifactState.incomplete,
          'Processed document contains no readable chapters or content blocks.',
        );
      }

      if (status == 'requiresOcr' || status == 'reconstructionFailed') {
        return _withState(
          base,
          ProcessedArtifactState.incomplete,
          'Processed document is not usable for Book Mode yet ($status).',
        );
      }

      if (manifest == null) {
        return _withState(
          base,
          ProcessedArtifactState.stale,
          'Processed document predates pipeline version tracking.',
        );
      }

      if (manifest.isNewer) {
        return _withState(
          base,
          ProcessedArtifactState.newer,
          'Processed document was created by a newer app version.',
        );
      }

      if (manifest.isOutdated) {
        return _withState(
          base,
          ProcessedArtifactState.stale,
          'Processed document was created by pipeline '
          '${manifest.pipelineVersion} (current '
          '${ProcessingManifest.currentPipelineVersion}).',
        );
      }

      return base;
    } catch (error) {
      return ProcessedArtifactStatus(
        state: ProcessedArtifactState.unreadable,
        path: path,
        message: 'Processed document is not valid JSON: $error',
      );
    }
  }

  static ProcessedArtifactStatus _withState(
    ProcessedArtifactStatus status,
    ProcessedArtifactState state,
    String message,
  ) => ProcessedArtifactStatus(
    state: state,
    manifest: status.manifest,
    path: status.path,
    message: message,
    processingStatus: status.processingStatus,
    chapterCount: status.chapterCount,
    blockCount: status.blockCount,
  );

  /// Restores `*.bak` left behind by an interrupted atomic reprocess and
  /// removes orphaned `*.tmp` files.
  ///
  /// A marker records whether the database transaction had already committed.
  /// An uncommitted marker means the new file and the old annotation anchors
  /// disagree, so the previous artifact is restored. A committed marker means
  /// only cleanup is left, so the new artifact is kept.
  static Future<ArtifactRecoveryResult> recoverInterrupted(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return ArtifactRecoveryResult.none;
    }

    final target = File(path);
    final backup = File('$path.bak');
    final temp = File('$path.tmp');
    final marker = File('$path.reprocess');
    var recovered = ArtifactRecoveryResult.none;

    if (await marker.exists()) {
      final committed = await _markerPhase(marker) == 'committed';
      if (committed && await _isValidArtifact(target)) {
        if (await backup.exists()) await backup.delete();
        await marker.delete();
        if (await temp.exists()) await temp.delete();
        return ArtifactRecoveryResult.cleanedBackup;
      }
      if (await backup.exists()) {
        if (await target.exists()) {
          await target.delete();
        }
        await backup.rename(path);
        await marker.delete();
        if (await temp.exists()) await temp.delete();
        return ArtifactRecoveryResult.restoredBackup;
      }
      await marker.delete();
    }

    if (await backup.exists()) {
      final targetValid = await _isValidArtifact(target);
      if (!targetValid) {
        if (await target.exists()) {
          await target.delete();
        }
        await backup.rename(path);
        recovered = ArtifactRecoveryResult.restoredBackup;
      } else {
        await backup.delete();
        recovered = ArtifactRecoveryResult.cleanedBackup;
      }
    }

    if (await temp.exists()) {
      await temp.delete();
      if (recovered == ArtifactRecoveryResult.none) {
        recovered = ArtifactRecoveryResult.cleanedTemp;
      }
    }

    return recovered;
  }

  static Future<String?> _markerPhase(File marker) async {
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is Map<String, dynamic>) {
        final phase = decoded['phase'];
        return phase is String ? phase : null;
      }
    } catch (_) {
      // A truncated marker is treated as uncommitted.
    }
    return null;
  }

  static Future<bool> _isValidArtifact(File file) async {
    try {
      if (!await file.exists()) return false;
      final status = await inspectJson(await file.readAsString());
      return status.state != ProcessedArtifactState.unreadable &&
          status.state != ProcessedArtifactState.incomplete;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _sha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
