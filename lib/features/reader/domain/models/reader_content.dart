import 'dart:convert';
import '../../models/book_document.dart';

enum ContentNodeType {
  heading,
  paragraph,
  quote,
  image,
  pageBreak,
  divider,
  footnote,
  documentTitle,
  sectionHeading,
  orderedList,
  unorderedList,
  listItem,
  caption,
  table,
  copyrightBlock,
  metadataBlock,
}

class ContentNode {
  final String id;
  final ContentNodeType type;
  final String text;
  final int level;
  final String? imagePath;
  final int sourcePdfPage;
  final Map<String, dynamic> attributes;

  const ContentNode({
    required this.id,
    required this.type,
    required this.text,
    this.level = 1,
    this.imagePath,
    this.sourcePdfPage = 1,
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'level': level,
    'imagePath': imagePath,
    'sourcePdfPage': sourcePdfPage,
    'attributes': attributes,
  };

  factory ContentNode.fromJson(Map<String, dynamic> json) => ContentNode(
    id: json['id'] as String? ?? '',
    type: ContentNodeType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ContentNodeType.paragraph,
    ),
    text: json['text'] as String? ?? '',
    level: json['level'] as int? ?? 1,
    imagePath: json['imagePath'] as String?,
    sourcePdfPage: json['sourcePdfPage'] as int? ?? 1,
    attributes: (json['attributes'] as Map<String, dynamic>?) ?? const {},
  );

  factory ContentNode.fromBookBlock(
    BookBlock block,
    int chapterIndex,
    int nodeIndex,
  ) {
    ContentNodeType nodeType;
    switch (block.type) {
      case BlockType.documentTitle:
        nodeType = ContentNodeType.documentTitle;
        break;
      case BlockType.heading:
        nodeType = ContentNodeType.heading;
        break;
      case BlockType.sectionHeading:
        nodeType = ContentNodeType.sectionHeading;
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
      case BlockType.footnote:
        nodeType = ContentNodeType.footnote;
        break;
      case BlockType.orderedList:
        nodeType = ContentNodeType.orderedList;
        break;
      case BlockType.unorderedList:
        nodeType = ContentNodeType.unorderedList;
        break;
      case BlockType.listItem:
        nodeType = ContentNodeType.listItem;
        break;
      case BlockType.caption:
        nodeType = ContentNodeType.caption;
        break;
      case BlockType.table:
        nodeType = ContentNodeType.table;
        break;
      case BlockType.copyrightBlock:
        nodeType = ContentNodeType.copyrightBlock;
        break;
      case BlockType.metadataBlock:
        nodeType = ContentNodeType.metadataBlock;
        break;
      default:
        nodeType = ContentNodeType.paragraph;
        break;
    }

    final stableId = block.id.isNotEmpty
        ? block.id
        : 'ch${chapterIndex}_n$nodeIndex';

    return ContentNode(
      id: stableId,
      type: nodeType,
      text: block.text,
      level: block.headingLevel,
      imagePath: block.imagePath,
      sourcePdfPage: block.originalPageNumber,
      attributes: block.metadata,
    );
  }

  BookBlock toBookBlock() {
    BlockType bType;
    switch (type) {
      case ContentNodeType.documentTitle:
        bType = BlockType.documentTitle;
        break;
      case ContentNodeType.heading:
        bType = BlockType.heading;
        break;
      case ContentNodeType.sectionHeading:
        bType = BlockType.sectionHeading;
        break;
      case ContentNodeType.quote:
        bType = BlockType.quote;
        break;
      case ContentNodeType.image:
        bType = BlockType.image;
        break;
      case ContentNodeType.pageBreak:
        bType = BlockType.pageBreak;
        break;
      case ContentNodeType.footnote:
        bType = BlockType.footnote;
        break;
      case ContentNodeType.orderedList:
        bType = BlockType.orderedList;
        break;
      case ContentNodeType.unorderedList:
        bType = BlockType.unorderedList;
        break;
      case ContentNodeType.listItem:
        bType = BlockType.listItem;
        break;
      case ContentNodeType.caption:
        bType = BlockType.caption;
        break;
      case ContentNodeType.table:
        bType = BlockType.table;
        break;
      case ContentNodeType.copyrightBlock:
        bType = BlockType.copyrightBlock;
        break;
      case ContentNodeType.metadataBlock:
        bType = BlockType.metadataBlock;
        break;
      default:
        bType = BlockType.paragraph;
        break;
    }

    return BookBlock(
      id: id,
      type: bType,
      text: text,
      headingLevel: level,
      imagePath: imagePath,
      originalPageNumber: sourcePdfPage,
      metadata: attributes,
    );
  }
}

class ReaderChapter {
  final String id;
  final int index;
  final String title;
  final List<ContentNode> nodes;

  const ReaderChapter({
    required this.id,
    required this.index,
    required this.title,
    required this.nodes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'title': title,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };

  factory ReaderChapter.fromJson(Map<String, dynamic> json) => ReaderChapter(
    id: json['id'] as String? ?? '',
    index: json['index'] as int? ?? 0,
    title: json['title'] as String? ?? 'Untitled Chapter',
    nodes: (json['nodes'] as List<dynamic>? ?? [])
        .map((n) => ContentNode.fromJson(n as Map<String, dynamic>))
        .toList(),
  );

  factory ReaderChapter.fromBookChapter(BookChapter chapter) {
    return ReaderChapter(
      id: chapter.id,
      index: chapter.index,
      title: chapter.title,
      nodes: chapter.blocks.asMap().entries.map((entry) {
        return ContentNode.fromBookBlock(entry.value, chapter.index, entry.key);
      }).toList(),
    );
  }

  BookChapter toBookChapter() {
    return BookChapter(
      id: id,
      index: index,
      title: title,
      blocks: nodes.map((n) => n.toBookBlock()).toList(),
    );
  }
}

class ReaderDocument {
  final String bookId;
  final String title;
  final String author;
  final int totalPages;
  final List<ReaderChapter> chapters;
  final Map<String, dynamic> metadata;

  int get totalParagraphCount => chapters.fold(
        0,
        (sum, c) =>
            sum +
            c.nodes
                .where(
                  (n) =>
                      n.type == ContentNodeType.paragraph ||
                      n.type == ContentNodeType.footnote,
                )
                .length,
      );

  const ReaderDocument({
    required this.bookId,
    required this.title,
    required this.author,
    this.totalPages = 0,
    required this.chapters,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'title': title,
    'author': author,
    'totalPages': totalPages,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'metadata': metadata,
  };

  String toJsonString() => jsonEncode(toJson());

  factory ReaderDocument.fromJson(Map<String, dynamic> json) => ReaderDocument(
    bookId: json['bookId'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled',
    author: json['author'] as String? ?? 'Unknown',
    totalPages: json['totalPages'] as int? ?? 0,
    chapters: (json['chapters'] as List<dynamic>? ?? [])
        .map((c) => ReaderChapter.fromJson(c as Map<String, dynamic>))
        .toList(),
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
  );

  factory ReaderDocument.fromJsonString(String jsonString) =>
      ReaderDocument.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  factory ReaderDocument.fromBookDocument(BookDocument doc) {
    return ReaderDocument(
      bookId: doc.id,
      title: doc.title,
      author: doc.author,
      totalPages: doc.totalPages,
      chapters: doc.chapters.map(ReaderChapter.fromBookChapter).toList(),
      metadata: doc.metadata,
    );
  }

  BookDocument toBookDocument() {
    return BookDocument(
      id: bookId,
      title: title,
      author: author,
      totalPages: totalPages,
      chapters: chapters.map((c) => c.toBookChapter()).toList(),
      metadata: metadata,
    );
  }
}
