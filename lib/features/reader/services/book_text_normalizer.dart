import 'package:uuid/uuid.dart';
import '../../reader/models/book_document.dart';

class BookTextNormalizer {
  static const Set<String> _chapterNumeralWords = {
    'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan', 'sembilan', 'sepuluh',
    'sebelas', 'dua belas', 'tiga belas', 'empat belas', 'lima belas', 'enam belas', 'tujuh belas',
    'delapan belas', 'sembilan belas', 'dua puluh', 'prolog', 'epilog', 'prologue', 'epilogue',
    'pendahuluan', 'pengantar', 'ucapan terima kasih', 'catatan akhir', 'daftar isi',
  };

  static final RegExp _chapterHeaderRegex = RegExp(
    r'^(bab|chapter|bagian|part|act|hukum)\s+([0-9ivxlcdm]+|[a-z]+)(:|\.|\s-|\s–)?\s*(.*)$',
    caseSensitive: false,
  );

  static final RegExp _standaloneNumberRegex = RegExp(r'^\d+$');
  static final RegExp _pageNumberRegex = RegExp(
    r'^(halaman\s*\d+|page\s*\d+|\d+\s*of\s*\d+)$',
    caseSensitive: false,
  );

  /// Normalizes and structures a BookDocument.
  /// If the document has already been nicely partitioned into multiple chapters with
  /// clean paragraphs, it still ensures headers/footers and hyphens are cleaned.
  /// If it contains raw dumped pages (e.g. isScanned or raw single-chapter text),
  /// it performs complete line-by-line reconstruction, de-hyphenation, header stripping,
  /// and chapter division.
  static BookDocument normalizeDocument(BookDocument document) {
    final title = document.title.trim();
    final author = document.author.trim();

    // Check if the document already has multiple rich chapters or if it's raw
    final List<BookChapter> normalizedChapters = [];
    final List<_RawLineInfo> collectedLines = [];

    // Extract all raw lines or preserve existing image blocks
    for (final chapter in document.chapters) {
      for (final block in chapter.blocks) {
        if (block.type == BlockType.image) {
          // Flush any gathered lines into paragraphs first
          if (collectedLines.isNotEmpty) {
            _processLinesIntoChapters(
              collectedLines,
              normalizedChapters,
              title: title,
              author: author,
            );
            collectedLines.clear();
          }
          // Add image block to the last chapter or create a new chapter
          if (normalizedChapters.isEmpty) {
            normalizedChapters.add(BookChapter(
              id: const Uuid().v4(),
              index: 0,
              title: chapter.title.isNotEmpty ? chapter.title : title,
              blocks: [block],
            ));
          } else {
            normalizedChapters.last.blocks.add(block);
          }
          continue;
        }

        final rawText = block.text;
        final lines = rawText.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            collectedLines.add(_RawLineInfo(
              text: trimmed,
              originalPage: block.originalPageNumber,
            ));
          }
        }
      }
    }

    if (collectedLines.isNotEmpty) {
      _processLinesIntoChapters(
        collectedLines,
        normalizedChapters,
        title: title,
        author: author,
      );
    }

    if (normalizedChapters.isEmpty) {
      return document;
    }

    // Ensure consecutive indices
    final List<BookChapter> finalChapters = [];
    for (int i = 0; i < normalizedChapters.length; i++) {
      final ch = normalizedChapters[i];
      finalChapters.add(BookChapter(
        id: ch.id,
        index: i,
        title: ch.title.isNotEmpty ? ch.title : (i == 0 ? 'Pengantar' : 'Bab $i'),
        blocks: ch.blocks,
      ));
    }

    return document.copyWith(chapters: finalChapters);
  }

  static void _processLinesIntoChapters(
    List<_RawLineInfo> rawLines,
    List<BookChapter> outputChapters, {
    required String title,
    required String author,
  }) {
    // 1. Filter out running headers and footers
    final List<_RawLineInfo> cleaned = [];
    final lowerTitle = title.toLowerCase();
    final lowerAuthor = author.toLowerCase();

    for (int i = 0; i < rawLines.length; i++) {
      final item = rawLines[i];
      final line = item.text;
      final lower = line.toLowerCase();

      // Check for standalone running headers / footers
      final isHeaderFooter = _isHeaderOrFooter(
        lower,
        line,
        lowerTitle: lowerTitle,
        lowerAuthor: lowerAuthor,
      );

      if (isHeaderFooter) {
        continue;
      }

      cleaned.add(item);
    }

    // 2. Stitch lines, repair hyphenations, detect chapters
    String currentChapterTitle = outputChapters.isEmpty ? 'Pengantar' : 'Bab ${outputChapters.length}';
    List<BookBlock> currentBlocks = [];
    int currentChapterPage = cleaned.isNotEmpty ? cleaned.first.originalPage : 1;

    String currentParagraphText = '';
    int currentParagraphPage = currentChapterPage;

    void flushParagraph() {
      if (currentParagraphText.trim().isEmpty) return;
      final text = currentParagraphText.trim();

      // Classify if it's a short centered subhead or regular paragraph
      if (_isStandaloneSubtitle(text)) {
        currentBlocks.add(BookBlock(
          id: const Uuid().v4(),
          type: BlockType.heading,
          headingLevel: 2,
          text: text,
          originalPageNumber: currentParagraphPage,
        ));
      } else {
        currentBlocks.add(BookBlock(
          id: const Uuid().v4(),
          type: BlockType.paragraph,
          text: text,
          originalPageNumber: currentParagraphPage,
        ));
      }
      currentParagraphText = '';
    }

    for (int i = 0; i < cleaned.length; i++) {
      final item = cleaned[i];
      var line = item.text.trim().replaceAll(RegExp(r'[ \t]+'), ' ');

      // Clean leading isolated capital letters noise like "K H Sanksi..."
      final leadingNoiseRegex = RegExp(r'^[A-Z](\s+[A-Z]){1,3}\s+([A-Za-z].*)$');
      final leadingNoiseMatch = leadingNoiseRegex.firstMatch(line);
      if (leadingNoiseMatch != null) {
        line = leadingNoiseMatch.group(2) ?? line;
      }

      final lower = line.toLowerCase();

      // Check if this line is a Chapter Heading
      final isChapterHeading = _isChapterHeading(lower, line);

      if (isChapterHeading) {
        flushParagraph();

        // If current chapter has content, complete it and start a new chapter
        if (currentBlocks.isNotEmpty) {
          outputChapters.add(BookChapter(
            id: const Uuid().v4(),
            index: outputChapters.length,
            title: currentChapterTitle,
            blocks: List.from(currentBlocks),
          ));
          currentBlocks.clear();
        }

        currentChapterTitle = line.trim();
        currentChapterPage = item.originalPage;

        currentBlocks.add(BookBlock(
          id: const Uuid().v4(),
          type: BlockType.heading,
          headingLevel: 1,
          text: currentChapterTitle,
          originalPageNumber: currentChapterPage,
        ));
        continue;
      }

      // Check legal or disclaimer clauses: e.g. "(1). Setiap orang..."
      final isLegalClause = RegExp(r'^\(\d+\)\.?').hasMatch(line);
      if (isLegalClause) {
        flushParagraph();
        currentParagraphText = line;
        currentParagraphPage = item.originalPage;
        continue;
      }

      if (currentParagraphText.isEmpty) {
        currentParagraphText = line;
        currentParagraphPage = item.originalPage;
      } else {
        // Hyphenation stitch check
        if (currentParagraphText.endsWith('-')) {
          final base = currentParagraphText.substring(0, currentParagraphText.length - 1);
          final tokens = line.split(RegExp(r'\s+'));
          final firstWord = tokens.isNotEmpty ? tokens.first : '';
          final rest = tokens.length > 1 ? line.substring(firstWord.length).trim() : '';

          // Check Indonesian reduplication: e.g. "dalam-dalam", "pagi-pagi", "berkibar-kibar"
          final lastWordMatch = RegExp(r'(\w+)$').firstMatch(base);
          final lastWord = lastWordMatch?.group(1) ?? '';

          String joined;
          if (lastWord.isNotEmpty &&
              (lastWord.toLowerCase() == firstWord.toLowerCase() ||
                  firstWord.toLowerCase().startsWith(lastWord.toLowerCase()) ||
                  lastWord.toLowerCase().endsWith(firstWord.toLowerCase()))) {
            joined = '$base-$firstWord';
          } else {
            joined = '$base$firstWord';
          }

          currentParagraphText = rest.isNotEmpty ? '$joined $rest' : joined;
        } else {
          // Check if line starts a new dialogue or section
          final startsDialogue = line.startsWith('"') ||
              line.startsWith('“') ||
              line.startsWith('”') ||
              line.startsWith('- ') ||
              line.startsWith('—');
          final prevEndsTerminal = RegExp(r'[.!?":]\s*$').hasMatch(currentParagraphText);

          // Natural paragraph boundary:
          // 1. Dialogue start after a terminal
          // 2. Previous sentence ended and accumulated paragraph is substantial (> 280 chars) and new line starts with a Capital letter
          // 3. Accumulated text is very long (> 700 chars) and previous sentence ended
          final isNewParagraph = prevEndsTerminal && (
            startsDialogue ||
            (currentParagraphText.length > 280 && RegExp(r'^[A-Z]').hasMatch(line)) ||
            currentParagraphText.length > 700
          );

          if (isNewParagraph) {
            flushParagraph();
            currentParagraphText = line;
            currentParagraphPage = item.originalPage;
          } else {
            currentParagraphText = '$currentParagraphText $line';
          }
        }
      }
    }

    flushParagraph();

    if (currentBlocks.isNotEmpty) {
      outputChapters.add(BookChapter(
        id: const Uuid().v4(),
        index: outputChapters.length,
        title: currentChapterTitle,
        blocks: List.from(currentBlocks),
      ));
    }
  }

  static bool _isHeaderOrFooter(
    String lower,
    String line, {
    required String lowerTitle,
    required String lowerAuthor,
  }) {
    final trimmed = line.trim();
    if (_standaloneNumberRegex.hasMatch(trimmed) || _pageNumberRegex.hasMatch(trimmed)) {
      return true;
    }

    // Single or double isolated letters from publisher logos or vertical OCR spine (e.g. "G", "S", "H", "K H")
    if (RegExp(r'^[a-zA-Z](\s+[a-zA-Z]){0,2}$').hasMatch(trimmed)) {
      return true;
    }

    if (lower == lowerTitle || lower == lowerAuthor) {
      return true;
    }

    // Common OCR artifacts on header lines
    const garbageHeaders = {
      'ith lh', 'hta la', 'kesetaan mk x', 'to ko', 'kompas gramedia',
      'penerbit gramedia', 'gramedia pustaka utama', 'sfile.mobi', 'epub',
      'kesetiaan mr. x', 'kesetiaan mr x', 'keigo higashino',
    };
    if (garbageHeaders.contains(lower)) {
      return true;
    }

    // Match author or title fragment in short header line
    if (trimmed.length <= 45) {
      if (lowerAuthor.isNotEmpty && lowerAuthor.length > 3 && lower.contains(lowerAuthor)) {
        return true;
      }
      if (lowerTitle.isNotEmpty && lowerTitle.length > 4 && lowerTitle.contains(lower)) {
        return true;
      }
      if (RegExp(r'^(keigo higashino|kesetiaan mr\.?\s*x|leila s\.?\s*chudori|laut bercerita|teka[- ]teki rumah aneh|uketsu)$', caseSensitive: false).hasMatch(trimmed)) {
        return true;
      }
    }

    return false;
  }

  static bool _isChapterHeading(String lower, String line) {
    final trimmed = line.trim();
    if (_chapterNumeralWords.contains(lower)) {
      return true;
    }

    if (_chapterHeaderRegex.hasMatch(trimmed) && trimmed.length <= 50) {
      return true;
    }

    // All uppercase single word or short phrase
    if (trimmed.length >= 3 && trimmed.length <= 25 && trimmed == trimmed.toUpperCase()) {
      if (RegExp(r'^[A-Z0-9\s\-]+$').hasMatch(trimmed)) {
        if (_chapterNumeralWords.contains(trimmed.toLowerCase())) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _isStandaloneSubtitle(String text) {
    if (text.length > 50) return false;
    if (text.endsWith('.') || text.endsWith(',') || text.endsWith(';') || text.endsWith(':')) {
      return false;
    }
    // Check if it's title case or all caps
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 5 && (text == text.toUpperCase() || words.every((w) => w.isNotEmpty && w[0] == w[0].toUpperCase()))) {
      return true;
    }
    return false;
  }
}

class _RawLineInfo {
  final String text;
  final int originalPage;

  _RawLineInfo({required this.text, required this.originalPage});
}

