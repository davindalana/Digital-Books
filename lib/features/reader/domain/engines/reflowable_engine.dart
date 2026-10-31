import '../../models/book_document.dart';
import '../../services/book_text_normalizer.dart';
import '../models/reader_content.dart';

class ReflowableEngine {
  /// Transforms a legacy or imported [BookDocument] into a normalized [ReaderDocument]
  /// with stable deterministic anchor IDs for every content node.
  static ReaderDocument normalizeDocument(BookDocument doc) {
    // Check if the document already has explicitly structured blocks (e.g. non-default IDs or diverse block types).
    // If it does, preserve the user/engine-defined block hierarchy rather than destroying it via raw line-stitching.
    final hasStructuredBlocks = doc.chapters.any(
      (c) =>
          c.blocks.any((b) => b.type != BlockType.paragraph || b.id.isNotEmpty),
    );

    final sourceDoc = hasStructuredBlocks
        ? doc
        : BookTextNormalizer.normalizeDocument(doc);
    final List<ReaderChapter> chapters = [];

    for (int chIdx = 0; chIdx < sourceDoc.chapters.length; chIdx++) {
      final ch = sourceDoc.chapters[chIdx];
      final List<ContentNode> nodes = [];

      for (int blkIdx = 0; blkIdx < ch.blocks.length; blkIdx++) {
        final b = ch.blocks[blkIdx];
        final cleanText = b.text.trim();
        if (b.type == BlockType.paragraph && cleanText.isEmpty) {
          continue;
        }

        final stableId = b.id.isNotEmpty && !b.id.startsWith('default')
            ? b.id
            : 'ch${chIdx}_n$blkIdx';

        ContentNodeType nodeType;
        switch (b.type) {
          case BlockType.heading:
            nodeType = ContentNodeType.heading;
            break;
          case BlockType.quote:
            nodeType = ContentNodeType.quote;
            break;
          case BlockType.image:
            nodeType = ContentNodeType.image;
            break;
          case BlockType.pageBreak:
            nodeType = ContentNodeType.pageBreak;
            break;
          default:
            nodeType = ContentNodeType.paragraph;
            break;
        }

        nodes.add(
          ContentNode(
            id: stableId,
            type: nodeType,
            text: b.text,
            level: b.headingLevel,
            imagePath: b.imagePath,
            sourcePdfPage: b.originalPageNumber,
          ),
        );
      }

      if (nodes.isEmpty) {
        nodes.add(
          ContentNode(
            id: 'ch${chIdx}_n0',
            type: ContentNodeType.paragraph,
            text: 'Tidak ada konten pada bab ini.',
          ),
        );
      }

      chapters.add(
        ReaderChapter(
          id: ch.id.isNotEmpty ? ch.id : 'ch_$chIdx',
          index: chIdx,
          title: ch.title,
          nodes: nodes,
        ),
      );
    }

    if (chapters.isEmpty) {
      chapters.add(
        ReaderChapter(
          id: 'ch_0',
          index: 0,
          title: doc.title,
          nodes: [
            const ContentNode(
              id: 'ch0_n0',
              type: ContentNodeType.paragraph,
              text: 'Dokumen kosong.',
            ),
          ],
        ),
      );
    }

    return ReaderDocument(
      bookId: doc.id,
      title: doc.title,
      author: doc.author,
      totalPages: doc.totalPages,
      chapters: chapters,
      metadata: doc.metadata,
    );
  }

  /// Calculates total word count and estimated reading time (in minutes) for a chapter
  static int estimateChapterReadingMinutes(
    ReaderChapter chapter, {
    int wpm = 220,
  }) {
    int totalWords = 0;
    for (final node in chapter.nodes) {
      if (node.text.isNotEmpty) {
        totalWords += node.text.split(RegExp(r'\s+')).length;
      }
    }
    return (totalWords / wpm).ceil().clamp(1, 120);
  }
}
