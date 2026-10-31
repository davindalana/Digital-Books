import 'dart:convert';

enum BlockType { heading, paragraph, image, pageBreak, quote, footnote }

class BookBlock {
  final String id;
  final BlockType type;
  final String text;
  final int headingLevel; // 1 for chapter title, 2 for section, 3 for sub
  final String? imagePath;
  final int originalPageNumber;

  const BookBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.headingLevel = 1,
    this.imagePath,
    this.originalPageNumber = 1,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'headingLevel': headingLevel,
    'imagePath': imagePath,
    'originalPageNumber': originalPageNumber,
  };

  factory BookBlock.fromJson(Map<String, dynamic> json) => BookBlock(
    id: json['id'] as String? ?? '',
    type: BlockType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => BlockType.paragraph,
    ),
    text: json['text'] as String? ?? '',
    headingLevel: json['headingLevel'] as int? ?? 1,
    imagePath: json['imagePath'] as String?,
    originalPageNumber: json['originalPageNumber'] as int? ?? 1,
  );
}

class BookChapter {
  final String id;
  final int index;
  final String title;
  final List<BookBlock> blocks;

  const BookChapter({
    required this.id,
    required this.index,
    required this.title,
    required this.blocks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  factory BookChapter.fromJson(Map<String, dynamic> json) => BookChapter(
    id: json['id'] as String? ?? '',
    index: json['index'] as int? ?? 0,
    title: json['title'] as String? ?? 'Untitled Chapter',
    blocks: (json['blocks'] as List<dynamic>? ?? [])
        .map((b) => BookBlock.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}

class BookDocument {
  final String id;
  final String title;
  final String author;
  final int totalPages;
  final bool isScanned;
  final List<BookChapter> chapters;
  final Map<String, dynamic> metadata;

  const BookDocument({
    required this.id,
    required this.title,
    required this.author,
    required this.totalPages,
    this.isScanned = false,
    required this.chapters,
    this.metadata = const {},
  });

  BookDocument copyWith({
    String? id,
    String? title,
    String? author,
    int? totalPages,
    bool? isScanned,
    List<BookChapter>? chapters,
    Map<String, dynamic>? metadata,
  }) => BookDocument(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author ?? this.author,
    totalPages: totalPages ?? this.totalPages,
    isScanned: isScanned ?? this.isScanned,
    chapters: chapters ?? this.chapters,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'totalPages': totalPages,
    'isScanned': isScanned,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'metadata': metadata,
  };

  factory BookDocument.fromJson(Map<String, dynamic> json) => BookDocument(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled Book',
    author: json['author'] as String? ?? 'Unknown Author',
    totalPages: json['totalPages'] as int? ?? 0,
    isScanned: json['isScanned'] as bool? ?? false,
    chapters: (json['chapters'] as List<dynamic>? ?? [])
        .map((c) => BookChapter.fromJson(c as Map<String, dynamic>))
        .toList(),
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
  );

  String toJsonString() => jsonEncode(toJson());

  factory BookDocument.fromJsonString(String rawJson) =>
      BookDocument.fromJson(jsonDecode(rawJson) as Map<String, dynamic>);
}
