import '../../providers/reader_settings_provider.dart';

enum ReflowableLayoutMode {
  paginated,
  scrolling,
}

class ReadingLocation {
  final String bookId;
  final ReadingMode sourceMode;
  final ReflowableLayoutMode layoutMode;

  // Original PDF
  final int? pdfPage;
  final double? pdfScrollOffset;

  // Reflowable
  final String? chapterId;
  final int chapterIndex;
  final String? anchorNodeId;
  final int characterOffset;
  final double chapterProgress;

  // General
  final double totalProgress;
  final DateTime lastReadAt;

  const ReadingLocation({
    required this.bookId,
    required this.sourceMode,
    this.layoutMode = ReflowableLayoutMode.paginated,
    this.pdfPage,
    this.pdfScrollOffset,
    this.chapterId,
    this.chapterIndex = 0,
    this.anchorNodeId,
    this.characterOffset = 0,
    this.chapterProgress = 0.0,
    this.totalProgress = 0.0,
    required this.lastReadAt,
  });

  ReadingLocation copyWith({
    String? bookId,
    ReadingMode? sourceMode,
    ReflowableLayoutMode? layoutMode,
    int? pdfPage,
    double? pdfScrollOffset,
    String? chapterId,
    int? chapterIndex,
    String? anchorNodeId,
    int? characterOffset,
    double? chapterProgress,
    double? totalProgress,
    DateTime? lastReadAt,
  }) {
    return ReadingLocation(
      bookId: bookId ?? this.bookId,
      sourceMode: sourceMode ?? this.sourceMode,
      layoutMode: layoutMode ?? this.layoutMode,
      pdfPage: pdfPage ?? this.pdfPage,
      pdfScrollOffset: pdfScrollOffset ?? this.pdfScrollOffset,
      chapterId: chapterId ?? this.chapterId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      anchorNodeId: anchorNodeId ?? this.anchorNodeId,
      characterOffset: characterOffset ?? this.characterOffset,
      chapterProgress: chapterProgress ?? this.chapterProgress,
      totalProgress: totalProgress ?? this.totalProgress,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'sourceMode': sourceMode.name,
        'layoutMode': layoutMode.name,
        'pdfPage': pdfPage,
        'pdfScrollOffset': pdfScrollOffset,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'anchorNodeId': anchorNodeId,
        'characterOffset': characterOffset,
        'chapterProgress': chapterProgress,
        'totalProgress': totalProgress,
        'lastReadAt': lastReadAt.toIso8601String(),
      };

  factory ReadingLocation.fromJson(Map<String, dynamic> json) => ReadingLocation(
        bookId: json['bookId'] as String? ?? '',
        sourceMode: ReadingMode.values.firstWhere(
          (m) => m.name == json['sourceMode'],
          orElse: () => ReadingMode.originalPdf,
        ),
        layoutMode: ReflowableLayoutMode.values.firstWhere(
          (m) => m.name == json['layoutMode'],
          orElse: () => ReflowableLayoutMode.paginated,
        ),
        pdfPage: json['pdfPage'] as int?,
        pdfScrollOffset: (json['pdfScrollOffset'] as num?)?.toDouble(),
        chapterId: json['chapterId'] as String?,
        chapterIndex: json['chapterIndex'] as int? ?? 0,
        anchorNodeId: json['anchorNodeId'] as String?,
        characterOffset: json['characterOffset'] as int? ?? 0,
        chapterProgress: (json['chapterProgress'] as num?)?.toDouble() ?? 0.0,
        totalProgress: (json['totalProgress'] as num?)?.toDouble() ?? 0.0,
        lastReadAt: json['lastReadAt'] != null
            ? DateTime.tryParse(json['lastReadAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

