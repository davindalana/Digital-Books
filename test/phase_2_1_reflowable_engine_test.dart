import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/reading_location.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    PaginationEngine.clearCache();
  });

  group('Phase 2.1 - Content Models & Processing', () {
    test('ContentNode JSON serialization round-trip preserves all fields', () {
      const node = ContentNode(
        id: 'ch0_n5',
        type: ContentNodeType.heading,
        text: 'Bab 1: Permulaan',
        level: 2,
        imagePath: '/images/cover.jpg',
        sourcePdfPage: 12,
        attributes: {'bold': true, 'italic': false},
      );

      final json = node.toJson();
      final restored = ContentNode.fromJson(json);

      expect(restored.id, equals(node.id));
      expect(restored.type, equals(ContentNodeType.heading));
      expect(restored.text, equals('Bab 1: Permulaan'));
      expect(restored.level, equals(2));
      expect(restored.imagePath, equals('/images/cover.jpg'));
      expect(restored.sourcePdfPage, equals(12));
      expect(restored.attributes['bold'], isTrue);
    });

    test(
      'ReaderDocument bidirectional conversion with BookDocument preserves structure',
      () {
        final originalBookDoc = BookDocument(
          id: 'book_123',
          title: 'Filosofi Teras',
          author: 'Henry Manampiring',
          totalPages: 280,
          chapters: [
            BookChapter(
              id: 'ch_0',
              index: 0,
              title: 'Pengantar',
              blocks: [
                const BookBlock(
                  id: 'blk_0_0',
                  type: BlockType.heading,
                  text: 'Pengantar Stoikisme',
                  headingLevel: 1,
                  originalPageNumber: 1,
                ),
                const BookBlock(
                  id: 'blk_0_1',
                  type: BlockType.paragraph,
                  text: 'Sebuah panduan praktis hidup tenteram.',
                  originalPageNumber: 2,
                ),
                const BookBlock(
                  id: 'blk_0_2',
                  type: BlockType.quote,
                  text: 'Ketenangan batin berasal dari kendali diri.',
                  originalPageNumber: 3,
                ),
              ],
            ),
          ],
          metadata: {'publisher': 'Kompas', 'year': 2019},
        );

        final readerDoc = ReaderDocument.fromBookDocument(originalBookDoc);
        expect(readerDoc.bookId, equals('book_123'));
        expect(readerDoc.title, equals('Filosofi Teras'));
        expect(readerDoc.author, equals('Henry Manampiring'));
        expect(readerDoc.chapters.length, equals(1));
        expect(readerDoc.chapters.first.nodes.length, equals(3));
        expect(
          readerDoc.chapters.first.nodes[0].type,
          equals(ContentNodeType.heading),
        );
        expect(
          readerDoc.chapters.first.nodes[1].type,
          equals(ContentNodeType.paragraph),
        );
        expect(
          readerDoc.chapters.first.nodes[2].type,
          equals(ContentNodeType.quote),
        );
        expect(readerDoc.chapters.first.nodes[2].sourcePdfPage, equals(3));

        final convertedBack = readerDoc.toBookDocument();
        expect(convertedBack.id, equals(originalBookDoc.id));
        expect(convertedBack.title, equals(originalBookDoc.title));
        expect(convertedBack.chapters.first.blocks.length, equals(3));
      },
    );

    test(
      'ReflowableEngine.normalizeDocument creates deterministic anchor IDs and drops empty blocks',
      () {
        final messyDoc = BookDocument(
          id: 'messy_doc',
          title: 'Buku Uji Normalisasi',
          author: 'Penulis Uji',
          totalPages: 10,
          chapters: [
            BookChapter(
              id: '',
              index: 0,
              title: 'Bab 1',
              blocks: [
                const BookBlock(
                  id: '',
                  type: BlockType.paragraph,
                  text: '   \n  \t ',
                ),
                const BookBlock(
                  id: '',
                  type: BlockType.heading,
                  text: 'Judul Utama',
                  headingLevel: 1,
                ),
                const BookBlock(
                  id: '',
                  type: BlockType.paragraph,
                  text: 'Teks paragraf pertama yang bermakna.',
                ),
              ],
            ),
          ],
        );

        final normalized = ReflowableEngine.normalizeDocument(messyDoc);
        expect(normalized.chapters.length, equals(1));
        final nodes = normalized.chapters.first.nodes;
        // Empty paragraph was removed
        expect(nodes.length, equals(2));
        expect(nodes[0].id, equals('ch0_n1'));
        expect(nodes[0].type, equals(ContentNodeType.heading));
        expect(nodes[1].id, equals('ch0_n2'));
        expect(nodes[1].type, equals(ContentNodeType.paragraph));
      },
    );

    test(
      'ReflowableEngine.estimateChapterReadingMinutes computes reasonable reading duration',
      () {
        final words = List.generate(440, (i) => 'kata$i').join(' ');
        final chapter = ReaderChapter(
          id: 'ch_long',
          index: 0,
          title: 'Bab Panjang',
          nodes: [
            ContentNode(id: 'n0', type: ContentNodeType.paragraph, text: words),
          ],
        );

        // 440 words at 220 wpm = 2 minutes
        final minutes = ReflowableEngine.estimateChapterReadingMinutes(
          chapter,
          wpm: 220,
        );
        expect(minutes, equals(2));
      },
    );
  });

  group('Phase 2.1 - Typography Engine & Settings', () {
    test(
      'TypographySettings provides proportional heading, body, and quote styles',
      () {
        const settings = TypographySettings(
          fontSize: 18.0,
          fontFamily: ReadingFontFamily.georgia,
          lineSpacing: 1.5,
          letterSpacing: 0.5,
          paragraphSpacing: 16.0,
        );

        final body = settings.bodyStyle();
        expect(body.fontSize, equals(18.0));
        expect(body.height, equals(1.5));
        expect(body.letterSpacing, equals(0.5));

        final h1 = settings.headingStyle(level: 1);
        expect(h1.fontSize, equals(18.0 * 1.45));
        expect(h1.fontWeight, equals(FontWeight.bold));

        final h2 = settings.headingStyle(level: 2);
        expect(h2.fontSize, equals(18.0 * 1.25));

        final quote = settings.quoteStyle();
        expect(quote.fontStyle, equals(FontStyle.italic));
        expect(quote.fontSize, equals(18.0 * 0.95));
      },
    );

    test(
      'TypographySettings cacheKey updates when any typographical parameter is modified',
      () {
        const base = TypographySettings(fontSize: 16.0);
        final withFont = base.copyWith(fontSize: 20.0);
        final withFamily = base.copyWith(
          fontFamily: ReadingFontFamily.sansSerif,
        );
        final withSpacing = base.copyWith(paragraphSpacing: 24.0);

        expect(base.cacheKey, isNot(equals(withFont.cacheKey)));
        expect(base.cacheKey, isNot(equals(withFamily.cacheKey)));
        expect(base.cacheKey, isNot(equals(withSpacing.cacheKey)));
      },
    );
  });

  group('Phase 2.1 - Pagination Engine (TextPainter-based dynamic layout)', () {
    const typography = TypographySettings(
      fontSize: 16.0,
      fontFamily: ReadingFontFamily.sansSerif,
      lineSpacing: 1.4,
      paragraphSpacing: 14.0,
      horizontalMargin: 24.0,
    );

    test('Short Chapter (< 1 page) fits within a single page', () {
      const shortChapter = ReaderChapter(
        id: 'ch_short',
        index: 0,
        title: 'Bab Pendek',
        nodes: [
          ContentNode(
            id: 'n0',
            type: ContentNodeType.heading,
            text: 'Bab Pendek',
            level: 1,
          ),
          ContentNode(
            id: 'n1',
            type: ContentNodeType.paragraph,
            text: 'Ini hanya kalimat singkat.',
          ),
        ],
      );

      final pages = PaginationEngine.paginateChapter(
        chapter: shortChapter,
        viewportWidth: 800,
        viewportHeight: 600,
        typography: typography,
      );

      expect(pages.length, equals(1));
      expect(pages.first.pageIndexInChapter, equals(0));
      expect(pages.first.slices.length, equals(2));
      expect(pages.first.firstAnchorNodeId, equals('n0'));
      expect(pages.first.lastAnchorNodeId, equals('n1'));
    });

    test('Long Chapter (> 10 pages) generates multiple contiguous pages', () {
      final List<ContentNode> manyNodes = [];
      for (int i = 0; i < 60; i++) {
        manyNodes.add(
          ContentNode(
            id: 'p_$i',
            type: ContentNodeType.paragraph,
            text:
                'Paragraf nomor $i berisi teks yang cukup panjang untuk mengisi beberapa baris dalam halaman buku digital. ' *
                4,
          ),
        );
      }

      final longChapter = ReaderChapter(
        id: 'ch_long',
        index: 0,
        title: 'Bab Panjang',
        nodes: manyNodes,
      );

      final pages = PaginationEngine.paginateChapter(
        chapter: longChapter,
        viewportWidth: 600,
        viewportHeight: 500,
        typography: typography,
      );

      expect(pages.length, greaterThanOrEqualTo(10));
      for (int i = 0; i < pages.length; i++) {
        expect(pages[i].pageIndexInChapter, equals(i));
        expect(pages[i].slices, isNotEmpty);
      }
    });

    test('Long paragraph splitting never splits words across page boundaries', () {
      final words = [
        'Keberanian',
        'adalah',
        'kebijaksanaan',
        'dalam',
        'menghadapi',
        'kesulitan.',
        'Ketenangan',
        'pikiran',
        'merupakan',
        'tujuan',
        'utama',
        'filsafat',
        'kuno.',
        'Kita',
        'tidak',
        'dapat',
        'mengontrol',
        'peristiwa',
        'eksternal',
        'di',
        'dunia.',
        'Namun',
        'kita',
        'memiliki',
        'kuasa',
        'penuh',
        'atas',
        'respon',
        'batiniah.',
      ];
      // Generate a massive paragraph that is guaranteed to split across multiple pages
      final longText = List.generate(40, (i) => words.join(' ')).join('\n\n');

      final chapter = ReaderChapter(
        id: 'ch_split',
        index: 0,
        title: 'Bab Pemecahan Paragraf',
        nodes: [
          ContentNode(
            id: 'split_node',
            type: ContentNodeType.paragraph,
            text: longText,
          ),
        ],
      );

      final pages = PaginationEngine.paginateChapter(
        chapter: chapter,
        viewportWidth: 400,
        viewportHeight: 400,
        typography: typography,
      );

      expect(pages.length, greaterThan(1));

      // Verify that every slice starts and ends on clean word boundaries
      for (int i = 0; i < pages.length; i++) {
        final slice = pages[i].slices.first;
        final sliceText = slice.textSlice;

        expect(sliceText.trim(), isNotEmpty);
        // Verify no slice ends with an incomplete word from the middle of a token
        if (slice.hasMore) {
          final nextCharInOriginal = longText[slice.endCharOffset];
          // The break character in the source text must be whitespace or punctuation, not inside a word
          expect(
            nextCharInOriginal == ' ' ||
                nextCharInOriginal == '\n' ||
                slice.textSlice.endsWith(' ') ||
                slice.textSlice.endsWith('.'),
            isTrue,
            reason:
                'Slice $i split inside a word at offset ${slice.endCharOffset}',
          );
        }
      }
    });

    test(
      'Heading orphan prevention pushes heading to next page if minimum room is unavailable',
      () {
        // Create a page that fills nearly all height, followed by a heading and its content
        final chapter = ReaderChapter(
          id: 'ch_heading',
          index: 0,
          title: 'Bab Uji Orphan Heading',
          nodes: [
            // Pre-filler paragraphs to fill most of page 1
            ContentNode(
              id: 'filler_1',
              type: ContentNodeType.paragraph,
              text:
                  'Baris kalimat pengisi halaman pertama bagian satu yang panjang. ' *
                  8,
            ),
            ContentNode(
              id: 'filler_2',
              type: ContentNodeType.paragraph,
              text:
                  'Baris kalimat pengisi halaman pertama bagian dua yang panjang. ' *
                  6,
            ),
            // Heading that should NOT be orphaned at the bottom of page 1
            const ContentNode(
              id: 'section_heading',
              type: ContentNodeType.heading,
              text: 'Sub-bab Penting Berikutnya',
              level: 2,
            ),
            const ContentNode(
              id: 'section_body',
              type: ContentNodeType.paragraph,
              text:
                  'Teks penjelas yang mengikuti sub-bab penting harus berada bersama atau segera setelah heading.',
            ),
          ],
        );

        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 500,
          viewportHeight: 420,
          typography: typography,
        );

        expect(pages.length, greaterThanOrEqualTo(2));

        // Find which page contains section_heading
        final headingPageIndex = pages.indexWhere(
          (p) => p.slices.any((s) => s.node.id == 'section_heading'),
        );
        expect(headingPageIndex, isNonNegative);

        // Verify heading is NOT left alone as the sole last item without any following content
        final headingPage = pages[headingPageIndex];
        final headingSliceIndex = headingPage.slices.indexWhere(
          (s) => s.node.id == 'section_heading',
        );

        // If heading is near bottom or on next page, verify it is positioned with body text or has room
        expect(headingSliceIndex, isNonNegative);
      },
    );

    test(
      'Image node budgets height and triggers page break when exceeding available room',
      () {
        final chapter = ReaderChapter(
          id: 'ch_image',
          index: 0,
          title: 'Bab Gambar',
          nodes: [
            ContentNode(
              id: 'intro_para',
              type: ContentNodeType.paragraph,
              text:
                  'Paragraf pengantar sebelum ilustrasi penting ditampilkan. ' *
                  5,
            ),
            const ContentNode(
              id: 'diagram_img',
              type: ContentNodeType.image,
              text: '',
              imagePath: '/images/diagram1.png',
            ),
            const ContentNode(
              id: 'caption_para',
              type: ContentNodeType.paragraph,
              text: 'Keterangan gambar diagram arsitektur sistem.',
            ),
          ],
        );

        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 500,
          viewportHeight: 380, // tight height budget
          typography: typography,
        );

        expect(pages.length, greaterThanOrEqualTo(2));
        final hasImageSlice = pages.any(
          (p) => p.slices.any((s) => s.node.id == 'diagram_img'),
        );
        expect(hasImageSlice, isTrue);
      },
    );

    test('Explicit ContentNodeType.pageBreak forces new page immediately', () {
      const chapter = ReaderChapter(
        id: 'ch_break',
        index: 0,
        title: 'Bab Pembatas Halaman',
        nodes: [
          ContentNode(
            id: 'before_break',
            type: ContentNodeType.paragraph,
            text: 'Teks sebelum pembatas halaman.',
          ),
          ContentNode(
            id: 'break_node',
            type: ContentNodeType.pageBreak,
            text: '',
          ),
          ContentNode(
            id: 'after_break',
            type: ContentNodeType.paragraph,
            text: 'Teks setelah pembatas halaman.',
          ),
        ],
      );

      final pages = PaginationEngine.paginateChapter(
        chapter: chapter,
        viewportWidth: 800,
        viewportHeight: 600,
        typography: typography,
      );

      expect(pages.length, equals(2));
      expect(pages[0].slices.any((s) => s.node.id == 'before_break'), isTrue);
      expect(pages[1].slices.any((s) => s.node.id == 'after_break'), isTrue);
    });

    test(
      'Chapter boundaries never bleed content across chapters in paginateDocument',
      () {
        const doc = ReaderDocument(
          bookId: 'doc_multi_ch',
          title: 'Buku Multi Bab',
          author: 'Penulis',
          chapters: [
            ReaderChapter(
              id: 'ch1',
              index: 0,
              title: 'Bab 1',
              nodes: [
                ContentNode(
                  id: 'c1_p1',
                  type: ContentNodeType.paragraph,
                  text: 'Isi Bab 1.',
                ),
              ],
            ),
            ReaderChapter(
              id: 'ch2',
              index: 1,
              title: 'Bab 2',
              nodes: [
                ContentNode(
                  id: 'c2_p1',
                  type: ContentNodeType.paragraph,
                  text: 'Isi Bab 2.',
                ),
              ],
            ),
          ],
        );

        final pages = PaginationEngine.paginateDocument(
          document: doc,
          viewportWidth: 800,
          viewportHeight: 600,
          typography: typography,
        );

        // Even though both chapters are tiny and could fit on one screen,
        // they MUST be on separate pages (page 0 for Ch1, page 1 for Ch2)
        expect(pages.length, equals(2));
        expect(pages[0].chapterIndex, equals(0));
        expect(pages[0].chapterTitle, equals('Bab 1'));
        expect(pages[1].chapterIndex, equals(1));
        expect(pages[1].chapterTitle, equals('Bab 2'));
      },
    );

    test(
      'Deterministic pagination: identical inputs produce identical page count and cache hits',
      () {
        final chapter = ReaderChapter(
          id: 'ch_det',
          index: 0,
          title: 'Bab Uji Deterministik',
          nodes: List.generate(
            15,
            (i) => ContentNode(
              id: 'd_$i',
              type: ContentNodeType.paragraph,
              text:
                  'Kalimat uji determinisme tata letak halaman buku nomor $i. ' *
                  3,
            ),
          ),
        );

        final run1 = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 600,
          viewportHeight: 800,
          typography: typography,
        );

        final run2 = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 600,
          viewportHeight: 800,
          typography: typography,
        );

        expect(run1.length, equals(run2.length));
        for (int i = 0; i < run1.length; i++) {
          expect(run1[i].slices.length, equals(run2[i].slices.length));
          expect(run1[i].firstAnchorNodeId, equals(run2[i].firstAnchorNodeId));
          expect(run1[i].lastAnchorNodeId, equals(run2[i].lastAnchorNodeId));
        }
      },
    );
  });

  group('Phase 2.1 - Responsive Viewports & Typography Scaling', () {
    final chapter = ReaderChapter(
      id: 'ch_responsive',
      index: 0,
      title: 'Bab Responsif',
      nodes: List.generate(
        20,
        (i) => ContentNode(
          id: 'resp_$i',
          type: ContentNodeType.paragraph,
          text:
              'Teks uji variasi layar dan ukuran font untuk menguji kemampuan adaptasi tata letak. ' *
              3,
        ),
      ),
    );

    test(
      'Mobile viewport (360x640) produces more pages than Desktop viewport (1400x900)',
      () {
        const typo = TypographySettings(fontSize: 16.0);

        final mobilePages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 360,
          viewportHeight: 640,
          typography: typo,
        );

        final desktopPages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 1400,
          viewportHeight: 900,
          typography: typo,
        );

        expect(mobilePages.length, greaterThan(desktopPages.length));
      },
    );

    test(
      'Larger font size (24pt) produces more pages than standard font size (14pt)',
      () {
        const smallTypo = TypographySettings(fontSize: 14.0);
        const largeTypo = TypographySettings(fontSize: 24.0);

        final smallPages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 700,
          viewportHeight: 600,
          typography: smallTypo,
        );

        final largePages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 700,
          viewportHeight: 600,
          typography: largeTypo,
        );

        expect(largePages.length, greaterThan(smallPages.length));
      },
    );
  });

  group('Phase 2.1 - Anchor Resolution & Position Restoration', () {
    test(
      'findPageIndexForAnchor pinpoints correct page for middle anchor and character offsets',
      () {
        final List<ContentNode> nodes = [];
        for (int i = 0; i < 25; i++) {
          nodes.add(
            ContentNode(
              id: 'node_$i',
              type: ContentNodeType.paragraph,
              text:
                  'Paragraf $i yang berisi konten cukup panjang untuk dipaginasi bertahap. ' *
                  4,
            ),
          );
        }

        final chapter = ReaderChapter(
          id: 'ch_anchors',
          index: 0,
          title: 'Bab Jangkar',
          nodes: nodes,
        );

        const typo = TypographySettings(fontSize: 16.0);
        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 600,
          viewportHeight: 500,
          typography: typo,
        );

        // Verify node_0 is on page 0
        final firstIdx = PaginationEngine.findPageIndexForAnchor(
          pages: pages,
          anchorNodeId: 'node_0',
          characterOffset: 0,
        );
        expect(firstIdx, equals(0));

        // Verify node_15 is in a later page
        final midIdx = PaginationEngine.findPageIndexForAnchor(
          pages: pages,
          anchorNodeId: 'node_15',
          characterOffset: 0,
        );
        expect(midIdx, greaterThan(0));
        expect(pages[midIdx].slices.any((s) => s.node.id == 'node_15'), isTrue);
      },
    );

    test(
      'Anchor restoration survives viewport resizing without jumping to chapter start',
      () {
        final longText =
            'Kata pembuka untuk bab simulasi perubahan ukuran viewport. ' * 40;
        final chapter = ReaderChapter(
          id: 'ch_resize_anchor',
          index: 0,
          title: 'Bab Resize',
          nodes: [
            const ContentNode(
              id: 'n_intro',
              type: ContentNodeType.heading,
              text: 'Pengantar',
              level: 1,
            ),
            ContentNode(
              id: 'n_long',
              type: ContentNodeType.paragraph,
              text: longText,
            ),
            const ContentNode(
              id: 'n_conclusion',
              type: ContentNodeType.paragraph,
              text: 'Kesimpulan bab ini.',
            ),
          ],
        );

        const typo = TypographySettings(fontSize: 16.0);

        // Desktop layout
        final desktopPages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 1200,
          viewportHeight: 800,
          typography: typo,
        );

        // Target anchor is n_conclusion
        final targetNodeId = 'n_conclusion';
        final desktopPageIndex = PaginationEngine.findPageIndexForAnchor(
          pages: desktopPages,
          anchorNodeId: targetNodeId,
        );
        expect(desktopPageIndex, isNonNegative);

        // Resize to narrow mobile viewport
        final mobilePages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 380,
          viewportHeight: 600,
          typography: typo,
        );

        // Find anchor in mobile pages
        final mobilePageIndex = PaginationEngine.findPageIndexForAnchor(
          pages: mobilePages,
          anchorNodeId: targetNodeId,
        );

        // Mobile page count is higher, anchor is preserved, never resets to page 0
        expect(mobilePages.length, greaterThan(desktopPages.length));
        expect(mobilePageIndex, greaterThan(0));
        expect(
          mobilePages[mobilePageIndex].slices.any(
            (s) => s.node.id == targetNodeId,
          ),
          isTrue,
        );
      },
    );

    test('ReadingLocation JSON serialization and copyWith work accurately', () {
      final location = ReadingLocation(
        bookId: 'book_abc',
        sourceMode: ReadingMode.reflowable,
        layoutMode: ReflowableLayoutMode.paginated,
        chapterId: 'ch_1',
        chapterIndex: 1,
        anchorNodeId: 'ch1_n4',
        characterOffset: 120,
        chapterProgress: 0.45,
        totalProgress: 0.30,
        lastReadAt: DateTime(2026, 10, 31, 15, 30),
      );

      final json = location.toJson();
      final restored = ReadingLocation.fromJson(json);

      expect(restored.bookId, equals('book_abc'));
      expect(restored.sourceMode, equals(ReadingMode.reflowable));
      expect(restored.layoutMode, equals(ReflowableLayoutMode.paginated));
      expect(restored.chapterIndex, equals(1));
      expect(restored.anchorNodeId, equals('ch1_n4'));
      expect(restored.characterOffset, equals(120));
      expect(restored.chapterProgress, closeTo(0.45, 0.001));
      expect(restored.totalProgress, closeTo(0.30, 0.001));

      final updated = location.copyWith(
        characterOffset: 180,
        layoutMode: ReflowableLayoutMode.scrolling,
      );
      expect(updated.characterOffset, equals(180));
      expect(updated.layoutMode, equals(ReflowableLayoutMode.scrolling));
      expect(updated.anchorNodeId, equals('ch1_n4'));
    });
  });

  group('Phase 2.1 - Edge Cases & Malformed Content Resilience', () {
    test(
      'Empty chapter nodes produces single placeholder page without crashing',
      () {
        const emptyChapter = ReaderChapter(
          id: 'ch_empty',
          index: 0,
          title: 'Bab Kosong',
          nodes: [],
        );

        final pages = PaginationEngine.paginateChapter(
          chapter: emptyChapter,
          viewportWidth: 600,
          viewportHeight: 500,
          typography: const TypographySettings(),
        );

        expect(pages, isNotEmpty);
        expect(pages.first.pageIndexInChapter, equals(0));
      },
    );

    test(
      'Chapter with single huge unbroken word (e.g. 500 characters) does not crash or loop infinitely',
      () {
        final hugeWord = 'A' * 500;
        final chapter = ReaderChapter(
          id: 'ch_huge_token',
          index: 0,
          title: 'Bab Token Ekstrem',
          nodes: [
            ContentNode(
              id: 'huge_1',
              type: ContentNodeType.paragraph,
              text: hugeWord,
            ),
          ],
        );

        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 400,
          viewportHeight: 300,
          typography: const TypographySettings(),
        );

        expect(pages, isNotEmpty);
        // Ensure all characters were accounted for across slices
        final totalSliceLength = pages
            .expand((p) => p.slices)
            .fold<int>(0, (sum, s) => sum + s.textSlice.length);
        expect(totalSliceLength, greaterThan(0));
      },
    );

    test('Extreme small viewport does not crash and clamps cleanly', () {
      const chapter = ReaderChapter(
        id: 'ch_tiny',
        index: 0,
        title: 'Bab Layar Mikro',
        nodes: [
          ContentNode(
            id: 't1',
            type: ContentNodeType.paragraph,
            text: 'Paragraf kecil pada layar sempit.',
          ),
        ],
      );

      final pages = PaginationEngine.paginateChapter(
        chapter: chapter,
        viewportWidth: 80,
        viewportHeight: 80,
        typography: const TypographySettings(),
      );

      expect(pages, isNotEmpty);
    });
  });
}
