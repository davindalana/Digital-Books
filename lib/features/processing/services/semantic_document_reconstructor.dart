import 'package:uuid/uuid.dart';
import '../../reader/models/book_document.dart';
import '../models/extracted_page_geometry.dart';
import '../models/semantic_reconstruction_models.dart';
import 'chapter_quality_normalizer.dart';
import 'front_matter_reconstructor.dart';
import 'image_placement_resolver.dart';
import 'ocr_correction_pass.dart';
import 'paragraph_reconstructor.dart';
import 'reading_order_resolver.dart';
import 'reconstruction_quality_analyzer.dart';
import 'semantic_classifier.dart';
import 'toc_reconstructor.dart';

/// Master Engine coordinating Phase 2.7D Semantic Reconstruction.
/// Transforms raw geometry-aware extraction output into semantically structured,
/// reading-order-verified documents suitable for natural reflowable reading.
class SemanticDocumentReconstructor {
  /// Reconstructs a full document from its intermediate geometry extraction.
  static Future<ReconstructedDocument> reconstruct({
    required DocumentExtractionResult extraction,
    required String title,
    String author = 'Unknown Author',
  }) async {
    final sw = Stopwatch()..start();

    // D1: Reading Order Reconstruction
    final readingOrders = ReadingOrderResolver.resolveDocument(extraction);

    // D1b: Dedicated front-matter reconstruction (cover, title, copyright,
    // publisher metadata, legal clauses). Generic paragraph reconstruction is
    // optimised for prose and produces an unusable blob for these pages.
    final frontMatter = FrontMatterReconstructor.reconstruct(
      pages: readingOrders,
      totalPages: extraction.totalPages,
      bookTitle: title,
    );

    // D1c: Table-of-contents reconstruction. The OCR emits TOC titles, dot
    // leaders and page labels as separate lines; combine them into entries.
    final toc = TocReconstructor.reconstruct(pages: readingOrders);

    // D2: Paragraph Reconstruction
    final paragraphs = ParagraphReconstructor.reconstructDocument(
      readingOrders,
    );

    // D3: Semantic Classification
    final pageHeights = <int, double>{
      for (final page in extraction.pages) page.pageIndex: page.pageSize.height,
    };
    final pageWidths = <int, double>{
      for (final page in extraction.pages) page.pageIndex: page.pageSize.width,
    };
    final classifiedBlocks = SemanticClassifier.classifyDocument(
      paragraphs: paragraphs,
      totalPages: extraction.totalPages,
      pageHeights: pageHeights,
      pageWidths: pageWidths,
    );

    // Front matter and TOC own their pages; discard generic prose blocks for
    // those pages so title/publisher/legal/TOC lines are not duplicated.
    final handledPages = <int>{
      ...frontMatter.handledPages,
      ...toc.handledPages,
    };
    final blocksByPage = <int, List<SemanticReconstructedBlock>>{};
    void addByPage(Iterable<SemanticReconstructedBlock> blocks) {
      for (final block in blocks) {
        blocksByPage.putIfAbsent(block.sourcePageIndex, () => []).add(block);
      }
    }

    addByPage(frontMatter.blocks);
    addByPage(toc.blocks);
    addByPage(
      classifiedBlocks.where((b) => !handledPages.contains(b.sourcePageIndex)),
    );
    final pageOrder = blocksByPage.keys.toList()..sort();
    final mergedBlocks = <SemanticReconstructedBlock>[
      for (final page in pageOrder) ...blocksByPage[page]!,
    ];

    // D4: Image Placement & Caption Binding
    final allImages = extraction.pages.expand((p) => p.images).toList();
    final integratedBlocks = ImagePlacementResolver.integrateImages(
      blocks: mergedBlocks,
      images: allImages,
      pages: extraction.pages,
    );

    // D5: Reconstruction Quality Assessment
    final quality = ReconstructionQualityAnalyzer.analyze(
      extraction: extraction,
      readingOrders: readingOrders,
      blocks: integratedBlocks,
    );

    // Identify back-cover pages. Their marketing copy and barcode are part of
    // the physical cover, not of the last content chapter, and must not be
    // merged into "BAB V" as body text. The original PDF still contains them.
    final backCoverPages = <int>{};
    for (final page in extraction.pages) {
      final pageText = page.lines.map((l) => l.text).join(' ').toLowerCase();
      if (pageText.contains('harga p. jawa') ||
          pageText.contains('self improvement') ||
          pageText.contains('penerbitbip')) {
        backCoverPages.add(page.pageIndex);
      }
    }

    // Filter chrome (running headers/footers/page numbers) from reader content stream
    // but retain footnotes, quotes, headings, paragraphs, and images.
    // Explicitly filter out cover images so cover is not rendered inside body chapters.
    final contentBlocks = integratedBlocks.where((b) {
      if (b.isChrome) return false;
      if (backCoverPages.contains(b.sourcePageIndex)) return false;
      if (b.type == SemanticBlockType.image) {
        final role = b.metadata['role'] as String?;
        if (role == ImageSemanticRole.coverImage.name ||
            (b.sourcePageIndex == 0 &&
                (role == null || role == ImageSemanticRole.coverImage.name))) {
          return false;
        }
      }
      return true;
    }).toList();

    // Merge continuations only after chrome/back-cover removal so a page
    // footer cannot separate a paragraph from the list item it continues.
    final flowBlocks = _mergeBrokenContinuations(contentBlocks);
    // D6: OCR artefact correction. Runs after paragraph merging (so a marker
    // split across lines is already joined) and before chapter-title correction
    // (so TOC-sourced titles are corrected by the same traceable pass).
    final correctedOcrBlocks = OcrCorrectionPass.apply(flowBlocks);
    final correctedBlocks = _correctChapterTitles(correctedOcrBlocks);

    // Partition content into chapters based on detected H1 headings
    final chapters = _buildChapters(correctedBlocks, title);

    sw.stop();
    final durationMs = sw.elapsedMicroseconds / 1000.0;

    return ReconstructedDocument(
      bookId: extraction.bookId,
      title: title,
      author: author,
      totalPages: extraction.totalPages,
      chapters: chapters,
      blocks: integratedBlocks,
      quality: quality,
      durationMs: durationMs,
      isScannedSource: !extraction.hasUsableTextLayer,
    );
  }

  /// Corrects OCR errors in chapter titles using the document's own TOC.
  /// The correction is traceable through the block metadata.
  static List<SemanticReconstructedBlock> _correctChapterTitles(
    List<SemanticReconstructedBlock> blocks,
  ) {
    final tocTitles = <String, String>{};
    String? pendingLabel;
    for (final block in blocks) {
      final kind = block.metadata['kind'];
      if (kind == 'tocChapterLabel') {
        pendingLabel = block.text.trim().toUpperCase();
      } else if (kind == 'tocChapterTitle' && pendingLabel != null) {
        tocTitles[pendingLabel] = block.text.trim();
        pendingLabel = null;
      }
    }
    if (tocTitles.isEmpty) return blocks;

    final corrected = <SemanticReconstructedBlock>[];
    final chapterPattern = RegExp(
      r'^(BAB|CHAPTER)\s+([IVXLCDM0-9]+)\s*:\s*(.+)$',
      caseSensitive: false,
      dotAll: true,
    );
    for (final block in blocks) {
      if (block.type != SemanticBlockType.heading1) {
        corrected.add(block);
        continue;
      }
      final match = chapterPattern.firstMatch(block.text.trim());
      if (match == null) {
        corrected.add(block);
        continue;
      }
      final label =
          '${match.group(1)!.toUpperCase()} '
          '${match.group(2)!.toUpperCase()}';
      final tocTitle = tocTitles[label];
      if (tocTitle == null || tocTitle.isEmpty) {
        corrected.add(block);
        continue;
      }
      final newText = '$label: $tocTitle';
      if (newText == block.text.trim()) {
        corrected.add(block);
        continue;
      }
      corrected.add(
        SemanticReconstructedBlock(
          id: block.id,
          type: block.type,
          text: newText,
          headingLevel: block.headingLevel,
          sourcePageIndex: block.sourcePageIndex,
          sourceBounds: block.sourceBounds,
          confidence: block.confidence,
          metadata: {
            ...block.metadata,
            'titleCorrection': {'source': 'toc', 'originalText': block.text},
          },
        ),
      );
    }
    return corrected;
  }

  /// Merges a paragraph that continues across a page break into its predecessor.
  /// OCR and page slicing can leave a continuation as a lower-case paragraph or
  /// as a short fragment after a list item. Merging at the semantic stage keeps
  /// pagination and typography from having to compensate for broken content.
  static List<SemanticReconstructedBlock> _mergeBrokenContinuations(
    List<SemanticReconstructedBlock> blocks,
  ) {
    final output = <SemanticReconstructedBlock>[];
    for (final block in blocks) {
      final text = block.text.trim();
      final isParagraph = block.type == SemanticBlockType.bodyParagraph;
      final mergeablePrevious =
          output.isNotEmpty &&
          (output.last.type == SemanticBlockType.bodyParagraph ||
              output.last.type == SemanticBlockType.quote ||
              output.last.type == SemanticBlockType.orderedListItem ||
              output.last.type == SemanticBlockType.unorderedListItem);
      final adjacentPage =
          output.isNotEmpty &&
          (output.last.sourcePageIndex == block.sourcePageIndex ||
              output.last.sourcePageIndex + 1 == block.sourcePageIndex);

      // Dialogues, lists, formulas, and stage directions have explicit semantic
      // boundaries and must NEVER be absorbed as a mere continuation.
      final isDialogue = RegExp(r'^(["“‘«—\-¿]|--\s)').hasMatch(text);
      final isListMarker = RegExp(
        r'^(\d{1,3}[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]{1,3}\)|[•\-\*–—])',
      ).hasMatch(text);
      final isAnnotationOrFormula = RegExp(
        r'^(\[[^\]]+\]|\([^\)]+\)|[A-Z0-9\+\-\*\/=]+$)',
      ).hasMatch(text);

      final prevEndsSentence =
          output.isNotEmpty && _endsSentence(output.last.text);
      final prevEndsHyphen =
          output.isNotEmpty &&
          (output.last.text.trimRight().endsWith('-') ||
              output.last.text.trimRight().endsWith('\u2010') ||
              output.last.text.trimRight().endsWith('\u2013'));

      final startsLower =
          text.isNotEmpty &&
          text[0].toLowerCase() == text[0] &&
          text[0] != text[0].toUpperCase();

      // Lowercase continuation only merges if the previous block did not finish
      // a sentence or was split mid-word with a hyphen.
      final genuineLowerContinuation =
          startsLower && (!prevEndsSentence || prevEndsHyphen);

      final shortContinuation =
          text.length < 20 &&
          !isDialogue &&
          !isListMarker &&
          !isAnnotationOrFormula &&
          output.isNotEmpty &&
          !prevEndsSentence;

      if (isParagraph &&
          !isDialogue &&
          !isListMarker &&
          !isAnnotationOrFormula &&
          mergeablePrevious &&
          adjacentPage &&
          (genuineLowerContinuation || shortContinuation)) {
        final previous = output.removeLast();
        final joined = _joinContinuation(previous.text, text);
        output.add(
          SemanticReconstructedBlock(
            id: previous.id,
            type: previous.type,
            text: joined,
            headingLevel: previous.headingLevel,
            sourcePageIndex: previous.sourcePageIndex,
            sourceBounds: previous.sourceBounds,
            confidence: previous.confidence,
            metadata: {
              ...previous.metadata,
              'paragraphContinuation': true,
              'mergedPage': block.sourcePageIndex,
            },
          ),
        );
        continue;
      }
      output.add(block);
    }
    return output;
  }

  static bool _endsSentence(String text) {
    final trimmed = text.trimRight();
    return RegExp(r"""[.!?…”"']$""").hasMatch(trimmed);
  }

  static String _joinContinuation(String previous, String current) {
    final left = previous.trimRight();
    final right = current.trimLeft();
    if (left.endsWith('-') ||
        left.endsWith('\u2010') ||
        left.endsWith('\u2013')) {
      return '$left$right'.replaceFirstMapped(
        RegExp('[-\\u2010\\u2013](?=[a-zA-Z])'),
        (_) => '',
      );
    }
    return '$left $right';
  }

  /// Groups content blocks into chapters based on detected H1 headings.
  static List<BookChapter> _buildChapters(
    List<SemanticReconstructedBlock> blocks,
    String defaultTitle,
  ) {
    if (blocks.isEmpty) {
      return [
        BookChapter(
          id: const Uuid().v4(),
          index: 0,
          title: defaultTitle,
          blocks: [
            BookBlock(
              id: const Uuid().v4(),
              type: BlockType.paragraph,
              text: 'Document content is empty or unsupported.',
              originalPageNumber: 1,
            ),
          ],
        ),
      ];
    }

    final chapters = <BookChapter>[];
    String currentTitle = 'Bagian Awal';
    final currentBookBlocks = <BookBlock>[];
    int chapterIdx = 0;
    bool hasSeenFirstH1 = false;

    for (final block in blocks) {
      if (block.type == SemanticBlockType.heading1) {
        if (currentBookBlocks.isNotEmpty) {
          // Conclude previous chapter
          chapters.add(
            BookChapter(
              id: const Uuid().v4(),
              index: chapterIdx++,
              title: hasSeenFirstH1 ? currentTitle : 'Bagian Awal',
              blocks: List.from(currentBookBlocks),
            ),
          );
          currentBookBlocks.clear();
        }
        currentTitle = block.text.trim();
        hasSeenFirstH1 = true;
      }

      currentBookBlocks.add(block.toBookBlock());
    }

    if (currentBookBlocks.isNotEmpty) {
      chapters.add(
        BookChapter(
          id: const Uuid().v4(),
          index: chapterIdx,
          title: hasSeenFirstH1 ? currentTitle : defaultTitle,
          blocks: List.from(currentBookBlocks),
        ),
      );
    }

    return ChapterQualityNormalizer.normalize(chapters);
  }
}
