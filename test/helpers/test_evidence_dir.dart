import 'dart:io';

/// Resolves the output directory for test-generated visual evidence.
///
/// By default, tests write visual artifacts to `build/test_visual_evidence/<subpath>`
/// to prevent dirtying the Git working tree during test execution.
///
/// When the [UPDATE_VISUAL_EVIDENCE] environment variable is set to '1',
/// artifacts are written directly to `docs/visual_evidence/<subpath>` to update
/// tracked documentation assets.
String resolveTestEvidenceDir([String subpath = '']) {
  final update = Platform.environment['UPDATE_VISUAL_EVIDENCE'] == '1';
  final baseDir = update ? 'docs/visual_evidence' : 'build/test_visual_evidence';
  final fullPath = subpath.isEmpty ? baseDir : '$baseDir/$subpath';
  final dir = Directory(fullPath);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir.path;
}

/// Convenience method returning a [Directory] object for test suites using [Directory].
Directory resolveTestEvidenceDirectory([String subpath = '']) {
  return Directory(resolveTestEvidenceDir(subpath));
}

