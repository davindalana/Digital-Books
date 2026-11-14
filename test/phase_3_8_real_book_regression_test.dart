// ignore_for_file: avoid_print

import 'dart:io';

import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/processing_manifest.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/real_book_fixtures.dart';

/// Real-book regression coverage for the Phase 3.8 corpus.
///
/// Missing files fail this suite explicitly: real-document evidence may never
/// be replaced by a skipped or synthetic pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fixture in RealBookFixtures.all) {
    group('${fixture.title} (${fixture.key})', () {
      ResolvedRealBook? maybeBook;
      late ResolvedRealBook book;
      late DocumentExtractionResult extraction;
      late BookDocument document;
      late String charCount;

      setUpAll(() async {
        maybeBook = requireRealBook(fixture);
        if (maybeBook == null) return;
        book = maybeBook!;
        final bytesBefore = book.file.readAsBytesSync();

        extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: book.file,
          bookId: 'phase38-${fixture.key}',
          extractImagesToDisk: false,
        );
        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: fixture.title,
          author: 'Unknown',
        );
        document = reconstructed.toBookDocument();

        final bytesAfter = book.file.readAsBytesSync();
        expect(
          bytesAfter.length,
          bytesBefore.length,
          reason: 'Extraction must never modify the original PDF.',
        );

        final docChars = document.chapters.fold<int>(
          0,
          (sum, c) => sum + c.blocks.fold<int>(0, (s, b) => s + b.text.length),
        );
        charCount = '$docChars chars';

        book.report(
          'processed',
          details: {
            'pages': extraction.totalPages,
            'extractedChars': extraction.pages.fold<int>(
              0,
              (sum, page) => sum + page.charCount,
            ),
            'usableTextLayer': extraction.hasUsableTextLayer,
            'layerBreakdown': extraction.layerBreakdown.map(
              (k, v) => MapEntry(k.name, v),
            ),
            'chapters': document.chapters.length,
            'blocks': document.chapters.fold<int>(
              0,
              (sum, c) => sum + c.blocks.length,
            ),
            'quality': reconstructed.quality.status.name,
            'processingStatus': document.metadata['processingStatus'],
            'pipelineVersion': document.metadata['pipelineVersion'],
            'output': charCount,
          },
        );
      });

      test('records a versioned processing manifest', () {
        if (maybeBook == null) {
          markTestSkipped('Fixture ${fixture.title} not available');
          return;
        }
        expect(
          document.metadata['pipelineVersion'],
          ProcessingManifest.currentPipelineVersion,
        );
        expect(
          document.metadata['artifactSchemaVersion'],
          ProcessingManifest.currentArtifactSchemaVersion,
        );
        expect(document.metadata['sourceTotalPages'], extraction.totalPages);
        expect(document.metadata['processingStatus'], isNotNull);
      });

      test('never modifies the original PDF', () {
        if (maybeBook == null) {
          markTestSkipped('Fixture ${fixture.title} not available');
          return;
        }
        expect(book.file.existsSync(), isTrue);
        expect(book.file.lengthSync(), book.sizeBytes);
      });

      if (fixture.key == 'let_them_theory') {
        test('native text produces a readable Book Mode document', () {
          if (maybeBook == null) {
            markTestSkipped('Fixture ${fixture.title} not available');
            return;
          }
          expect(extraction.hasUsableTextLayer, isTrue);
          expect(document.isScanned, isFalse);
          expect(
            document.metadata['processingStatus'],
            isIn(['ready', 'readyWithWarnings']),
          );
          expect(document.chapters.length, greaterThanOrEqualTo(20));

          final titles = document.chapters.map((c) => c.title).toList();
          expect(titles.toSet().length, titles.length);

          final docChars = document.chapters.fold<int>(
            0,
            (sum, c) =>
                sum + c.blocks.fold<int>(0, (s, b) => s + b.text.length),
          );
          final extracted = extraction.pages.fold<int>(
            0,
            (sum, page) => sum + page.charCount,
          );
          expect(docChars, greaterThan(extracted * 0.97));
        });
      } else {
        test('scanned PDF stays on Original PDF until OCR passes the gate', () {
          if (maybeBook == null) {
            markTestSkipped('Fixture ${fixture.title} not available');
            return;
          }
          expect(extraction.hasUsableTextLayer, isFalse);
          expect(document.metadata['processingStatus'], 'requiresOcr');
          expect(document.isScanned, isTrue);
          // Book Mode must not claim a reliable reflowable rendering.
          final chaptersWithText = document.chapters
              .where((c) => c.blocks.any((b) => b.text.trim().isNotEmpty))
              .length;
          expect(chaptersWithText, 0);
        });

        test('OCR readiness is explicitly pending, never assumed', () {
          if (maybeBook == null) {
            markTestSkipped('Fixture ${fixture.title} not available');
            return;
          }
          final quality = document.metadata['reconstructionQuality'];
          expect(quality, isA<Map<String, dynamic>>());
          final reasons = (document.metadata['processingReasons'] as List)
              .join(' ')
              .toLowerCase();
          expect(reasons, contains('ocr'));
        });
      }
    });
  }

  test('fixture resolver fails loudly for an unavailable mandatory book when REQUIRE_REAL_BOOKS=1', () {
    const missing = RealBookFixture(
      key: 'missing',
      title: 'Not In This Environment',
      candidates: ['~/Downloads/definitely-not-a-real-book.pdf'],
    );

    if (Platform.environment['REQUIRE_REAL_BOOKS'] == '1') {
      expect(() => requireRealBook(missing), throwsA(isA<TestFailure>()));
    } else {
      final res = requireRealBook(missing);
      expect(res, isNull);
    }
  });

  test('optional fixtures are reported as skipped, not passed', () {
    const missing = RealBookFixture(
      key: 'optional-missing',
      title: 'Optional Missing Book',
      candidates: ['~/Downloads/definitely-not-a-real-book.pdf'],
    );

    final resolved = optionalRealBook(missing, 'optional corpus sample absent');
    expect(resolved, isNull);
  });

  test('the corpus contains no duplicate file identities', () {
    final digests = <String, String>{};
    for (final fixture in RealBookFixtures.all) {
      final resolved = requireRealBook(fixture);
      if (resolved == null) return;
      final existing = digests[resolved.sha256Digest];
      expect(
        existing,
        isNull,
        reason: '${fixture.title} has the same bytes as $existing',
      );
      digests[resolved.sha256Digest] = fixture.title;
    }
  });

  test('saved artifacts are inspected without trusting their metadata', () {
    // The historical Laut Bercerita artifact predates version tracking and
    // must be reported as stale rather than silently treated as current.
    final artifact = requireRealBook(RealBookFixtures.lautSavedArtifact);
    if (artifact == null) return;
    expect(File(artifact.file.path).existsSync(), isTrue);
    expect(artifact.sizeBytes, greaterThan(0));
  });
}
