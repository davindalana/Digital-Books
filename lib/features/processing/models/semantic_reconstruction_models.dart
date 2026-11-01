import 'dart:ui' show Rect;
import 'package:uuid/uuid.dart';
import '../../reader/models/book_document.dart';
import 'extracted_page_geometry.dart';

/// Semantic role of a reconstructed content block.
enum SemanticBlockType {
  heading1,
  heading2,
  heading3,
  bodyParagraph,
  quote,
  caption,
  footnote,
  runningHeader,
  runningFooter,
  pageNumber,
  image,
  table,
  documentTitle,
  orderedListItem,
  unorderedListItem,
  copyrightBlock,
  metadataBlock,
  unknown,
}

/// Overall quality assessment of semantic reconstruction for a document or page.
enum QualityStatus {
  /// Structure, reading order, and assets reconstructed with high confidence.
  good,

  /// Some elements had ambiguous layout, missing text, or mixed scanned content.
  partial,

  /// Severe extraction/reconstruction failure (e.g. pure scans without OCR or corrupted flow).
  poor,
}

/// Represents an individual reconstructed block with semantic classification and source provenance.
class SemanticReconstructedBlock {
  final String id;
  final SemanticBlockType type;
  final String text;
  final int headingLevel;
  final int sourcePageIndex;
  final Rect? sourceBounds;
  final ExtractedImage? image;
  final String? captionText;
  final double confidence;
  final Map<String, dynamic> metadata;

  SemanticReconstructedBlock({
    String? id,
    required this.type,
    this.text = '',
    this.headingLevel = 1,
    required this.sourcePageIndex,
    this.sourceBounds,
    this.image,
    this.captionText,
    this.confidence = 1.0,
    this.metadata = const {},
  }) : id = id ?? const Uuid().v4();

  bool get isHeading =>
      type == SemanticBlockType.heading1 ||
      type == SemanticBlockType.heading2 ||
      type == SemanticBlockType.heading3;

  bool get isChrome =>
      type == SemanticBlockType.runningHeader ||
      type == SemanticBlockType.runningFooter ||
      type == SemanticBlockType.pageNumber;

  /// Converts this semantic block into a reader-compatible BookBlock.
  BookBlock toBookBlock() {
    BlockType blockType;
    int level = headingLevel;

    switch (type) {
      case SemanticBlockType.documentTitle:
        blockType = BlockType.documentTitle;
        level = 1;
        break;
      case SemanticBlockType.heading1:
        blockType = BlockType.heading;
        level = 1;
        break;
      case SemanticBlockType.heading2:
        blockType = BlockType.sectionHeading;
        level = 2;
        break;
      case SemanticBlockType.heading3:
        blockType = BlockType.heading;
        level = 3;
        break;
      case SemanticBlockType.quote:
        blockType = BlockType.quote;
        break;
      case SemanticBlockType.footnote:
        blockType = BlockType.footnote;
        break;
      case SemanticBlockType.image:
        blockType = BlockType.image;
        break;
      case SemanticBlockType.caption:
        blockType = BlockType.caption;
        break;
      case SemanticBlockType.table:
        blockType = BlockType.table;
        break;
      case SemanticBlockType.orderedListItem:
        blockType = BlockType.orderedList;
        break;
      case SemanticBlockType.unorderedListItem:
        blockType = BlockType.unorderedList;
        break;
      case SemanticBlockType.copyrightBlock:
        blockType = BlockType.copyrightBlock;
        break;
      case SemanticBlockType.metadataBlock:
        blockType = BlockType.metadataBlock;
        break;
      case SemanticBlockType.bodyParagraph:
      case SemanticBlockType.unknown:
      default:
        blockType = BlockType.paragraph;
        break;
    }

    return BookBlock(
      id: id,
      type: blockType,
      text: text,
      headingLevel: level,
      imagePath: image?.imagePath,
      originalPageNumber: sourcePageIndex + 1,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'headingLevel': headingLevel,
    'sourcePageIndex': sourcePageIndex,
    'sourceBounds': sourceBounds != null
        ? [
            sourceBounds!.left,
            sourceBounds!.top,
            sourceBounds!.width,
            sourceBounds!.height,
          ]
        : null,
    'image': image?.toJson(),
    'captionText': captionText,
    'confidence': confidence,
    'metadata': metadata,
  };
}

/// Comprehensive quality report evaluating reconstruction fidelity.
class ReconstructionQuality {
  final QualityStatus status;
  final double score; // 0.0 (unusable) to 1.0 (flawless)
  final List<String> reasons;
  final Map<String, dynamic> metrics;
  final String recommendedTier;

  const ReconstructionQuality({
    required this.status,
    required this.score,
    required this.reasons,
    required this.metrics,
    required this.recommendedTier,
  });

  bool get isSuitableForReflowable => status == QualityStatus.good;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'score': score,
    'reasons': reasons,
    'metrics': metrics,
    'recommendedTier': recommendedTier,
  };
}

/// A structured document produced by the Semantic Reconstruction Engine.
class ReconstructedDocument {
  final String bookId;
  final String title;
  final String author;
  final int totalPages;
  final List<BookChapter> chapters;
  final List<SemanticReconstructedBlock> blocks;
  final ReconstructionQuality quality;
  final double durationMs;

  const ReconstructedDocument({
    required this.bookId,
    required this.title,
    required this.author,
    required this.totalPages,
    required this.chapters,
    required this.blocks,
    required this.quality,
    required this.durationMs,
  });

  /// Converts this reconstructed document into a domain BookDocument for reader playback.
  BookDocument toBookDocument({Map<String, dynamic>? extraMetadata}) {
    return BookDocument(
      id: bookId,
      title: title,
      author: author,
      totalPages: totalPages,
      isScanned: quality.status == QualityStatus.poor,
      chapters: chapters,
      metadata: {
        'reconstructionQuality': quality.toJson(),
        'reconstructionDurationMs': durationMs,
        if (extraMetadata != null) ...extraMetadata,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'title': title,
    'author': author,
    'totalPages': totalPages,
    'quality': quality.toJson(),
    'durationMs': durationMs,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };
}

