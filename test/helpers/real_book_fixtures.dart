import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real production document used by acceptance tests.
///
/// Missing files are never converted into passes:
/// * [requireRealBook] fails the test.
/// * [optionalRealBook] marks the test skipped and reports the missing path.
class RealBookFixture {
  final String key;
  final String title;
  final List<String> candidates;
  final bool required;

  const RealBookFixture({
    required this.key,
    required this.title,
    required this.candidates,
    this.required = true,
  });
}

class ResolvedRealBook {
  final RealBookFixture fixture;
  final File file;
  final int sizeBytes;
  final String sha256Digest;

  const ResolvedRealBook({
    required this.fixture,
    required this.file,
    required this.sizeBytes,
    required this.sha256Digest,
  });

  String get identity =>
      '${fixture.title} [${fixture.key}] ${file.path} '
      '($sizeBytes bytes, sha256 ${sha256Digest.substring(0, 12)}…)';

  void report(String stage, {Map<String, Object?> details = const {}}) {
    // ignore: avoid_print
    print('[real-book] $identity :: $stage $details');
  }
}

/// The documents named by Phase 3.8.
///
/// Only paths that actually exist in the environment are used; the list is
/// ordered so the current workspace copy wins over any older duplicate.
abstract final class RealBookFixtures {
  static const lautBercerita = RealBookFixture(
    key: 'laut_bercerita',
    title: 'Laut Bercerita',
    candidates: [
      '~/Downloads/Laut Bercerita (Leila S. Chudori).pdf',
      '~/Documents/DigitalBooks/originals/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.pdf',
    ],
  );

  static const letThemTheory = RealBookFixture(
    key: 'let_them_theory',
    title: 'The Let Them Theory',
    candidates: ['~/Downloads/The Let Them Theory (Mel Robbins).pdf'],
  );

  static const devotionOfSuspectX = RealBookFixture(
    key: 'devotion_of_suspect_x',
    title: 'The Devotion of Suspect X',
    candidates: [
      '~/Downloads/Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf',
      '~/Documents/DigitalBooks/originals/67141617-5a74-4f9b-a9fa-45b28366e27d.pdf',
    ],
  );

  static const bicaraItuAdaSeninya = RealBookFixture(
    key: 'bicara_itu_ada_seninya',
    title: 'Bicara Itu Ada Seninya',
    candidates: [
      '~/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf',
      '~/Documents/DigitalBooks/originals/7b3dcbf3-0f23-4c6d-8044-d525257dac00.pdf',
    ],
  );

  static const all = [
    lautBercerita,
    letThemTheory,
    devotionOfSuspectX,
    bicaraItuAdaSeninya,
  ];

  /// Saved Book Mode artifacts that document known historical defects.
  static const lautSavedArtifact = RealBookFixture(
    key: 'laut_saved_artifact',
    title: 'Laut Bercerita saved artifact',
    candidates: [
      '~/Documents/DigitalBooks/books/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.json',
    ],
  );
}

String? _existingPath(List<String> candidates) {
  for (final candidate in candidates) {
    final resolved = _expandHome(candidate);
    if (File(resolved).existsSync()) return resolved;
  }
  return null;
}

String _expandHome(String path) {
  if (!path.startsWith('~')) return path;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return path;
  return '$home${path.substring(1)}';
}

ResolvedRealBook? _resolve(RealBookFixture fixture) {
  final path = _existingPath(fixture.candidates);
  if (path == null) return null;
  final file = File(path);
  final bytes = file.readAsBytesSync();
  return ResolvedRealBook(
    fixture: fixture,
    file: file,
    sizeBytes: bytes.length,
    sha256Digest: sha256.convert(bytes).toString(),
  );
}

/// Resolves a mandatory fixture or fails with an actionable message.
ResolvedRealBook requireRealBook(RealBookFixture fixture) {
  final resolved = _resolve(fixture);
  if (resolved == null) {
    fail(
      'Mandatory real-book fixture "${fixture.title}" is missing. '
      'Checked: ${fixture.candidates.map(_expandHome).join(', ')}',
    );
  }
  return resolved;
}

/// Resolves an optional fixture, marking the current test skipped when absent.
ResolvedRealBook? optionalRealBook(RealBookFixture fixture, String reason) {
  final resolved = _resolve(fixture);
  if (resolved == null) {
    markTestSkipped(
      '${fixture.title} not available in this environment; $reason',
    );
  }
  return resolved;
}
