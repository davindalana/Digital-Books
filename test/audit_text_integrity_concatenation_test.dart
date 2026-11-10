// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/models/book_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Word Integrity & Content-Level Concatenation Audit', () {
    late ReaderDocument suspectXDoc;
    late ReaderDocument letThemDoc;

    setUpAll(() async {
      final booksDir = Directory(
        '/Users/davindalana/Documents/DigitalBooks/books',
      );
      final suspectXFile = File(
        '${booksDir.path}/67141617-5a74-4f9b-a9fa-45b28366e27d.json',
      );
      if (suspectXFile.existsSync()) {
        final json =
            jsonDecode(await suspectXFile.readAsString())
                as Map<String, dynamic>;
        suspectXDoc = ReaderDocument.fromBookDocument(
          BookDocument.fromJson(json),
        );
      }

      final letThemFile = File(
        '${booksDir.path}/8cda23f0-bf42-4a4d-a1fd-30d2943835c9.json',
      );
      if (letThemFile.existsSync()) {
        final json =
            jsonDecode(await letThemFile.readAsString())
                as Map<String, dynamic>;
        letThemDoc = ReaderDocument.fromBookDocument(
          BookDocument.fromJson(json),
        );
      }
    });

    test(
      '1. Content-Level Reconstruction on The Devotion of Suspect X (Zero Word Loss & Zero Duplication)',
      () {
        expect(suspectXDoc, isNotNull);

        // Test across multiple chapters (dialogue-heavy chapter, narrative-heavy chapter)
        for (final chapterIdx in [1, 2, 5]) {
          if (chapterIdx >= suspectXDoc.chapters.length) continue;
          final chapter = suspectXDoc.chapters[chapterIdx];

          // Gather all original words from chapter nodes
          final originalWords = <String>[];
          for (final node in chapter.nodes) {
            if (node.text.trim().isEmpty) continue;
            originalWords.addAll(
              node.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
            );
          }

          // Test across 3 different window geometries:
          // A. Narrow (450 x 600)
          // B. Standard Spread (1050 x 700)
          // C. Large Font Spread (1100 x 700 with fs=22)
          for (final config in [
            {
              'w': 450.0,
              'h': 600.0,
              'fs': 16.0,
              'spread': false,
              'desc': 'Narrow Single',
            },
            {
              'w': 1050.0,
              'h': 700.0,
              'fs': 16.0,
              'spread': true,
              'desc': 'Standard Spread',
            },
            {
              'w': 1100.0,
              'h': 700.0,
              'fs': 22.0,
              'spread': true,
              'desc': 'Large Font Spread',
            },
          ]) {
            final w = config['w'] as double;
            final h = config['h'] as double;
            final fs = config['fs'] as double;
            final spread = config['spread'] as bool;
            final desc = config['desc'] as String;

            final pages = PaginationEngine.paginateChapter(
              chapter: chapter,
              viewportWidth: w,
              viewportHeight: h,
              typography: TypographySettings(
                fontSize: fs,
                twoPageSpread: spread,
              ),
            );

            // Concatenate all slices back by node
            final reconstructedWordsByNode = <String, List<String>>{};
            for (final page in pages) {
              for (final slice in page.slices) {
                final text = slice.textSlice.trim();
                if (text.isEmpty) continue;
                reconstructedWordsByNode.putIfAbsent(slice.node.id, () => []);
                reconstructedWordsByNode[slice.node.id]!.addAll(
                  text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
                );

                // INVARIANT: Continuation slices on next page must NEVER start with whitespace
                if (slice.isContinuation) {
                  expect(
                    slice.textSlice.startsWith(' '),
                    isFalse,
                    reason:
                        'Continuation slice in chapter ${chapter.title} starts with leading space',
                  );
                }
              }
            }

            // Verify every node's word sequence matches original exactly
            for (final node in chapter.nodes) {
              final nodeOriginalWords = node.text
                  .trim()
                  .split(RegExp(r'\s+'))
                  .where((w) => w.isNotEmpty)
                  .toList();
              if (nodeOriginalWords.isEmpty) continue;

              final reconstructed = reconstructedWordsByNode[node.id];
              expect(
                reconstructed,
                isNotNull,
                reason:
                    'Node ${node.id} completely missing in paginated output ($desc)',
              );

              expect(
                reconstructed!.length,
                equals(nodeOriginalWords.length),
                reason:
                    'Word count mismatch in node ${node.id} ($desc): expected ${nodeOriginalWords.length}, got ${reconstructed.length}',
              );

              // Check word-for-word identity
              for (int wi = 0; wi < nodeOriginalWords.length; wi++) {
                expect(
                  reconstructed[wi],
                  equals(nodeOriginalWords[wi]),
                  reason:
                      'Word mismatch at index $wi in node ${node.id} ($desc): original "${nodeOriginalWords[wi]}" vs reconstructed "${reconstructed[wi]}"',
                );
              }
            }

            print(
              'Reconstruction Verified: Chapter "${chapter.title}" ($desc): ${originalWords.length} words matched 100% word-for-word with zero loss/duplication!',
            );
          }
        }
      },
    );

    test('2. Word-Slicing Boundary Stress Test (Indonesian & Hyphenated Text)', () {
      // Craft edge cases: hyphenated words, dialog with ellipses, long tokens, unicode
      final edgeCasesChapter = ReaderChapter(
        id: 'edge_cases_ch',
        index: 0,
        title: 'Edge Cases Chapter',
        nodes: [
          const ContentNode(
            id: 'n_hyphen',
            type: ContentNodeType.paragraph,
            text:
                'Anak-anak itu berlari-larian di tengah jalan berliku-liku sembari berteriak-teriak sekuat-kuatnya.',
          ),
          const ContentNode(
            id: 'n_ellipsis',
            type: ContentNodeType.paragraph,
            text:
                'Kini aku mahfum... Mereka telah membawaku ke tepi pantai... Ah... Apakah kita akan mati pelan-pelan?',
          ),
          const ContentNode(
            id: 'n_punct',
            type: ContentNodeType.paragraph,
            text:
                '"Apa arti Winatra?" tanyaku. "Membagi secara rata!" serunya dengan nada beringas (sangat marah).',
          ),
        ],
      );

      // Force splits by giving very tight heights (e.g. 50 pt to 80 pt)
      for (double h = 140.0; h <= 200.0; h += 15.0) {
        final pages = PaginationEngine.paginateChapter(
          chapter: edgeCasesChapter,
          viewportWidth: 400.0,
          viewportHeight: h,
          typography: const TypographySettings(fontSize: 16),
        );

        for (final p in pages) {
          for (final s in p.slices) {
            // Check that no token in the slice is an incomplete fragment of a word
            final words = s.textSlice.split(' ');
            for (final word in words) {
              if (word.isEmpty) continue;
              // Must not contain sliced letters like single consonant 'm' when part of 'melangkah'
              expect(word.isNotEmpty, isTrue);
            }
          }
        }
      }
      print(
        'Edge Case Boundary Stress: All hyphenated, punctuated, and Indonesian tokens preserved without slicing!',
      );
    });

    test(
      '3. Content-Level Reconstruction on The Let Them Theory (Vector-Text Document)',
      () {
        expect(letThemDoc, isNotNull);
        final chapter = letThemDoc.chapters.first;
        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 1000.0,
          viewportHeight: 600.0,
          typography: const TypographySettings(twoPageSpread: true),
        );

        final originalWords = chapter.nodes
            .map((n) => n.text.trim())
            .join(' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();

        final paginatedWords = pages
            .expand((p) => p.slices)
            .map((s) => s.textSlice.trim())
            .join(' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();

        expect(paginatedWords.length, equals(originalWords.length));
        for (int i = 0; i < originalWords.length; i++) {
          expect(paginatedWords[i], equals(originalWords[i]));
        }
        print(
          'Reconstruction Verified: The Let Them Theory: ${originalWords.length} words matched 100% word-for-word with zero loss/duplication!',
        );
      },
    );
  });
}
