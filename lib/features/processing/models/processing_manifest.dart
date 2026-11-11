/// Version and provenance information embedded in every processed Book Mode
/// artifact (`books/<bookId>.json`).
///
/// The artifact is a derivative of the immutable original PDF. Recording the
/// pipeline version here is what makes it possible to answer "is this saved
/// document stale?" without guessing from the shape of the JSON.
class ProcessingManifest {
  /// Semantic version of the reconstruction pipeline that produced an
  /// artifact. Bump this whenever extraction/classification/chapter building
  /// changes in a way that can alter reader output.
  static const String currentPipelineVersion = '3.8.0';

  /// Schema version of the persisted metadata contract. Bump this when the
  /// keys required to validate an artifact change, independently of the
  /// algorithm version.
  static const int currentArtifactSchemaVersion = 2;

  final String pipelineVersion;
  final int artifactSchemaVersion;
  final String? processedAt;
  final String? source;
  final String? sourceFileHash;
  final int? sourceFileSize;
  final int? sourceTotalPages;
  final int? ocrCompletedPages;

  const ProcessingManifest({
    required this.pipelineVersion,
    required this.artifactSchemaVersion,
    this.processedAt,
    this.source,
    this.sourceFileHash,
    this.sourceFileSize,
    this.sourceTotalPages,
    this.ocrCompletedPages,
  });

  static const ProcessingManifest current = ProcessingManifest(
    pipelineVersion: currentPipelineVersion,
    artifactSchemaVersion: currentArtifactSchemaVersion,
  );

  bool get isCurrent =>
      artifactSchemaVersion == currentArtifactSchemaVersion &&
      _compareVersions(pipelineVersion, currentPipelineVersion) == 0;

  bool get isNewer =>
      artifactSchemaVersion > currentArtifactSchemaVersion ||
      _compareVersions(pipelineVersion, currentPipelineVersion) > 0;

  bool get isOutdated =>
      artifactSchemaVersion < currentArtifactSchemaVersion ||
      _compareVersions(pipelineVersion, currentPipelineVersion) < 0;

  Map<String, dynamic> toMetadata() => {
    'pipelineVersion': pipelineVersion,
    'artifactSchemaVersion': artifactSchemaVersion,
    if (processedAt != null) 'processedAt': processedAt,
    if (source != null) 'processingSource': source,
    if (sourceFileHash != null) 'sourceFileHash': sourceFileHash,
    if (sourceFileSize != null) 'sourceFileSize': sourceFileSize,
    if (sourceTotalPages != null) 'sourceTotalPages': sourceTotalPages,
    if (ocrCompletedPages != null) 'ocrCompletedPages': ocrCompletedPages,
  };

  static ProcessingManifest? fromMetadata(Map<String, dynamic> metadata) {
    final rawVersion = metadata['pipelineVersion'];
    final rawSchema = metadata['artifactSchemaVersion'];
    final schemaVersion = _asInt(rawSchema);
    if (rawVersion is! String ||
        rawVersion.trim().isEmpty ||
        schemaVersion == null) {
      return null;
    }
    return ProcessingManifest(
      pipelineVersion: rawVersion.trim(),
      artifactSchemaVersion: schemaVersion,
      processedAt: metadata['processedAt'] as String?,
      source: metadata['processingSource'] as String?,
      sourceFileHash: metadata['sourceFileHash'] as String?,
      sourceFileSize: _asInt(metadata['sourceFileSize']),
      sourceTotalPages: _asInt(metadata['sourceTotalPages']),
      ocrCompletedPages: _asInt(metadata['ocrCompletedPages']),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Compares dotted numeric versions. Non-numeric suffixes are ignored, which
  /// is sufficient for the pipeline's own `major.minor.patch` scheme.
  static int _compareVersions(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static List<int> _parts(String version) => version
      .split(RegExp(r'[^0-9]+'))
      .where((part) => part.isNotEmpty)
      .map(int.parse)
      .toList();
}
