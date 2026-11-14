import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A real production document used by acceptance tests.
///
/// Behavior when missing:
/// * By default (without REQUIRE_REAL_BOOKS=1), [requireRealBook] marks the
///   test as skipped, allowing clean test runs in environments without fixtures.
/// * When REQUIRE_REAL_BOOKS=1, [requireRealBook] fails the test immediately.
/// * [optionalRealBook] always marks the test skipped and reports the reason.
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

/// The documents used by Digital Books test suites.
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

  static const filosofiTeras = RealBookFixture(
    key: 'filosofi_teras',
    title: 'Filosofi Teras',
    candidates: ['~/Downloads/filosofi-teraspdf.pdf'],
  );

  static const the48LawsOfPower = RealBookFixture(
    key: 'the_48_laws_of_power',
    title: 'The 48 Laws Of Power',
    candidates: [
      '~/Downloads/The 48 Laws Of Power (Robert Greene).pdf',
    ],
  );

  static const articleText = RealBookFixture(
    key: 'article_text',
    title: 'Academic Article Text',
    candidates: [
      '~/Downloads/1259-Article Text-5284-1-10-20231024.pdf',
    ],
  );

  static const all = [
    lautBercerita,
    letThemTheory,
    devotionOfSuspectX,
    bicaraItuAdaSeninya,
  ];

  static const theLetThemTheory = letThemTheory;
  static const kesetiaanMrX = devotionOfSuspectX;

  static File resolve(RealBookFixture fixture) {
    final path = _existingPath(fixture.candidates);
    if (path != null) return File(path);
    return File(expandHome(fixture.candidates.first));
  }

  /// Saved Book Mode artifacts that document known historical defects.
  static const lautSavedArtifact = RealBookFixture(
    key: 'laut_saved_artifact',
    title: 'Laut Bercerita saved artifact',
    candidates: [
      '~/Documents/DigitalBooks/books/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.json',
    ],
  );

  static const suspectXSavedArtifact = RealBookFixture(
    key: 'suspect_x_saved_artifact',
    title: 'Suspect X saved artifact',
    candidates: [
      '~/Documents/DigitalBooks/books/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
    ],
  );

  static const atomicHabitsArtifact = RealBookFixture(
    key: 'atomic_habits_artifact',
    title: 'Atomic Habits original PDF',
    candidates: [
      '~/Documents/DigitalBooks/originals/8cda23f0-bf42-4a4d-a1fd-30d2943835c9.pdf',
    ],
  );

  static String get downloadsDir =>
      Platform.environment['REAL_BOOKS_DIR'] ?? expandHome('~/Downloads');

  static String get digitalBooksDir =>
      Platform.environment['REAL_BOOKS_DIR'] ??
      expandHome('~/Documents/DigitalBooks');

  static String get originalsDir => p.join(digitalBooksDir, 'originals');

  static String get booksDir => p.join(digitalBooksDir, 'books');

  static String get documentsDir =>
      Platform.environment['REAL_BOOKS_DIR'] ?? expandHome('~/Documents');
}

String expandHome(String path) {
  if (!path.startsWith('~')) return path;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return path;
  return '$home${path.substring(1)}';
}

String? _existingPath(List<String> candidates) {
  final realBooksDir = Platform.environment['REAL_BOOKS_DIR'];
  if (realBooksDir != null && realBooksDir.isNotEmpty) {
    final cleanDir = expandHome(realBooksDir);
    for (final candidate in candidates) {
      final name = p.basename(candidate);
      final inDir = p.join(cleanDir, name);
      if (File(inDir).existsSync()) return inDir;
      final subPath = p.join(
        cleanDir,
        candidate.replaceAll(RegExp(r'^~/'), ''),
      );
      if (File(subPath).existsSync()) return subPath;
    }
  }

  for (final candidate in candidates) {
    final resolved = expandHome(candidate);
    if (File(resolved).existsSync()) return resolved;
  }
  return null;
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

/// Resolves a fixture.
///
/// When the fixture is missing:
/// - If REQUIRE_REAL_BOOKS=1: fails the test immediately with an actionable error.
/// - Otherwise: marks the test as skipped and returns null.
ResolvedRealBook? requireRealBook(RealBookFixture fixture) {
  final resolved = _resolve(fixture);
  if (resolved == null) {
    if (Platform.environment['REQUIRE_REAL_BOOKS'] == '1') {
      fail(
        'Mandatory real-book fixture "${fixture.title}" is missing. '
        'Checked: ${fixture.candidates.map(expandHome).join(', ')}'
        '${Platform.environment['REAL_BOOKS_DIR'] != null ? ' (REAL_BOOKS_DIR: ${Platform.environment['REAL_BOOKS_DIR']})' : ''}',
      );
    } else {
      markTestSkipped(
        'Real-book fixture "${fixture.title}" is not available in this environment. '
        'Set REAL_BOOKS_DIR or provide fixture files to run this test.',
      );
      return null;
    }
  }
  return resolved;
}

/// Resolves an optional fixture, marking the current test skipped when absent.
ResolvedRealBook? optionalRealBook(
  RealBookFixture fixture, [
  String reason = 'optional corpus sample absent',
]) {
  final resolved = _resolve(fixture);
  if (resolved == null) {
    markTestSkipped(
      '${fixture.title} not available in this environment; $reason',
    );
  }
  return resolved;
}

/// Resolves an arbitrary file by path or name, respecting REAL_BOOKS_DIR and HOME.
File? resolveFixtureFile(String path, {String? reason}) {
  final realBooksDir = Platform.environment['REAL_BOOKS_DIR'];
  if (realBooksDir != null && realBooksDir.isNotEmpty) {
    final cleanDir = expandHome(realBooksDir);
    final inDir = p.join(cleanDir, p.basename(path));
    if (File(inDir).existsSync()) return File(inDir);
    final subPath = p.join(cleanDir, path.replaceAll(RegExp(r'^~/'), ''));
    if (File(subPath).existsSync()) return File(subPath);
  }

  final resolved = expandHome(path);
  final f = File(resolved);
  if (f.existsSync()) return f;

  if (Platform.environment['REQUIRE_REAL_BOOKS'] == '1') {
    fail('Required fixture file "$path" is missing.');
  } else {
    markTestSkipped(
      'Fixture file "${p.basename(path)}" not available in this environment; ${reason ?? 'skipped'}.',
    );
    return null;
  }
}

/// Checks if a file or path exists, skipping the test if missing (or failing if REQUIRE_REAL_BOOKS=1).
/// Returns true if the file exists and test should proceed; returns false if skipped.
bool checkFixtureOrSkip(Object fileOrPath, [String? description]) {
  final file = fileOrPath is File ? fileOrPath : File(fileOrPath.toString());
  if (file.existsSync()) return true;
  if (Platform.environment['REQUIRE_REAL_BOOKS'] == '1') {
    fail('Required fixture "${description ?? file.path}" is missing.');
  } else {
    markTestSkipped('Fixture "${description ?? p.basename(file.path)}" not found in this environment.');
    return false;
  }
}
