import 'package:uuid/uuid.dart';
import '../../reader/models/book_document.dart';
import '../models/extracted_page_geometry.dart';
import '../models/semantic_reconstruction_models.dart';
import 'image_placement_resolver.dart';
import 'paragraph_reconstructor.dart';
import 'reading_order_resolver.dart';
import 'reconstruction_quality_analyzer.dart';
import 'semantic_classifier.dart';

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

    // D2: Paragraph Reconstruction
    final paragraphs = ParagraphReconstructor.reconstructDocument(
      readingOrders,
    );

    // D3: Semantic Classification
    final classifiedBlocks = SemanticClassifier.classifyDocument(
      paragraphs: paragraphs,
      totalPages: extraction.totalPages,
    );

    // D4: Image Placement & Caption Binding
    final allImages = extraction.pages.expand((p) => p.images).toList();
    final integratedBlocks = ImagePlacementResolver.integrateImages(
      blocks: classifiedBlocks,
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

    // Partition content into chapters based on detected H1 headings
    final chapters = _buildChapters(contentBlocks, title);

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
    );
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

    return chapters;
  }
}
