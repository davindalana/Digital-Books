import '../../reader/models/book_document.dart';

/// Structural clean-up for chapters produced by semantic reconstruction.
///
/// The classifier is intentionally permissive: every H1 is a candidate chapter
/// boundary. That is correct for clean digital PDFs but produces legacy
/// artefacts like:
///
/// * a table-of-contents entry promoted to a one-block "chapter";
/// * the same title appearing twice (TOC/front matter plus the real chapter);
/// * a sentence in display type becoming a chapter title.
///
/// This pass fixes those shapes without changing extraction or losing content.
/// Blocks from a removed chapter are merged into a surviving chapter, and only
/// the heading that duplicated the chapter title is dropped.
class ChapterQualityNormalizer {
  /// A chapter with more than this many blocks, or enough text, is treated as
  /// the real chapter when the same title appears more than once.
  static const int _substantialBlockCount = 3;
  static const int _substantialCharacterCount = 400;

  static List<BookChapter> normalize(List<BookChapter> chapters) {
    if (chapters.isEmpty) return chapters;

    final working = <_MutableChapter>[
      for (var i = 0; i < chapters.length; i++)
        _MutableChapter(
          id: chapters[i].id.isEmpty ? 'chapter-$i' : chapters[i].id,
          title: chapters[i].title.trim().isEmpty
              ? 'Bagian ${i + 1}'
              : chapters[i].title.trim(),
          blocks: List<BookBlock>.of(chapters[i].blocks),
          order: i,
        ),
    ];

    _mergeTocChapters(working);
    _mergeSentenceTitles(working);
    _mergeDuplicateTitles(working);
    _mergeEmptyChapters(working);
    _normalizeNumberedChapterTitles(working);

    final result = <BookChapter>[];
    for (var i = 0; i < working.length; i++) {
      final chapter = working[i];
      final blocks = _dedupeConsecutiveHeadings(chapter.blocks);
      result.add(
        BookChapter(
          id: chapter.id,
          index: i,
          title: chapter.title,
          blocks: blocks.isEmpty
              ? [
                  const BookBlock(
                    id: 'empty-chapter-placeholder',
                    type: BlockType.paragraph,
                    text: 'This section contains no extractable text.',
                  ),
                ]
              : blocks,
        ),
      );
    }
    return result;
  }

  /// A table of contents is front matter, not a chapter. Keeping it as its own
  /// chapter produces a one-block "Daftar Isi" chapter next to the real
  /// chapters. Its text is still preserved: it is merged into the neighbouring
  /// chapter as body content.
  static void _mergeTocChapters(List<_MutableChapter> chapters) {
    for (var i = chapters.length - 1; i >= 0; i--) {
      final title = _normalizeTitle(chapters[i].title);
      if (title != 'daftar isi' &&
          title != 'table of contents' &&
          title != 'contents') {
        continue;
      }
      final blocks = _blocksWithoutDuplicateTitleHeading(chapters[i]);
      // A contents chapter that carries real entry text is a legitimate front
      // matter section and must stay addressable by navigation and audits.
      // Only a heading-only artefact is folded away.
      if (blocks.isNotEmpty) continue;
      if (chapters.length == 1) {
        chapters[i].title = 'Bagian Awal';
        chapters[i].blocks
          ..clear()
          ..addAll(blocks);
        continue;
      }
      if (i > 0) {
        chapters[i - 1].blocks.addAll(blocks);
        chapters.removeAt(i);
      } else {
        chapters[1].blocks.insertAll(0, blocks);
        chapters.removeAt(0);
      }
    }
  }

  static void _mergeSentenceTitles(List<_MutableChapter> chapters) {
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (!_isSentenceTitle(chapter.title)) continue;

      final blocks = _blocksWithoutDuplicateTitleHeading(chapter);
      if (i > 0) {
        chapters[i - 1].blocks.addAll(blocks);
        chapters.removeAt(i);
        i--;
      } else if (chapters.length > 1) {
        chapters[1].blocks.insertAll(0, blocks);
        chapters.removeAt(0);
        i--;
      } else {
        // A single sentence-like title still needs to remain readable; keep it
        // as the default chapter instead of deleting the only chapter.
        chapter.title = 'Bagian Awal';
      }
    }
  }

  static void _mergeDuplicateTitles(List<_MutableChapter> chapters) {
    final groups = <String, List<_MutableChapter>>{};
    for (final chapter in chapters) {
      groups.putIfAbsent(_normalizeTitle(chapter.title), () => []).add(chapter);
    }

    final toRemove = <_MutableChapter>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) => a.order.compareTo(b.order));

      final substantial = group.where((c) => _isSubstantial(c)).toList();
      final anchor = substantial.isNotEmpty
          ? substantial.reduce(
              (a, b) => a.blocks.length >= b.blocks.length ? a : b,
            )
          : group.first;

      final before = <BookBlock>[];
      final after = <BookBlock>[];
      for (final chapter in group) {
        if (identical(chapter, anchor)) continue;
        final blocks = _blocksWithoutDuplicateTitleHeading(chapter);
        if (chapter.order < anchor.order) {
          before.addAll(blocks);
        } else {
          after.addAll(blocks);
        }
        toRemove.add(chapter);
      }
      anchor.blocks
        ..insertAll(0, before)
        ..addAll(after);
    }

    if (toRemove.isNotEmpty) {
      chapters.removeWhere(toRemove.contains);
    }
  }

  /// Repairs a single roman-numeral chapter label inside an otherwise arabic
  /// sequence (for example "CHAPTER II" between "CHAPTER 10" and
  /// "CHAPTER 12"). Fonts that render lining figures as roman glyphs produce
  /// this; the surrounding sequence identifies the intended number.
  static void _normalizeNumberedChapterTitles(List<_MutableChapter> chapters) {
    final pattern = RegExp(
      r'^((?:bab|chapter|bagian)\s+)([ivxlcdm]+|\d+)(\s*[:.\-–—]?\s*.*)$',
      caseSensitive: false,
    );

    final parsed = <({int position, int value, bool isRoman, Match match})>[];
    for (var i = 0; i < chapters.length; i++) {
      final match = pattern.firstMatch(chapters[i].title.trim());
      if (match == null) continue;
      final token = match.group(2)!.toLowerCase();
      final numeric = int.tryParse(token);
      final value = numeric ?? _romanToInt(token);
      if (value == null) continue;
      parsed.add((
        position: i,
        value: value,
        isRoman: numeric == null,
        match: match,
      ));
    }

    for (var i = 0; i < parsed.length; i++) {
      final entry = parsed[i];
      if (!entry.isRoman) continue;
      if (i == 0 || i == parsed.length - 1) continue;
      final previous = parsed[i - 1];
      final next = parsed[i + 1];
      if (previous.isRoman || next.isRoman) continue;
      if (next.value != previous.value + 2) continue;

      final corrected = previous.value + 1;
      final match = entry.match;
      chapters[entry.position].title =
          '${match.group(1)}$corrected${match.group(3)}'.trimRight();
      // Keep the parsed sequence coherent for any later roman label.
      parsed[i] = (
        position: entry.position,
        value: corrected,
        isRoman: false,
        match: entry.match,
      );
    }
  }

  static int? _romanToInt(String token) {
    const values = {
      'i': 1,
      'v': 5,
      'x': 10,
      'l': 50,
      'c': 100,
      'd': 500,
      'm': 1000,
    };
    var total = 0;
    var previous = 0;
    for (var i = token.length - 1; i >= 0; i--) {
      final value = values[token[i]];
      if (value == null) return null;
      if (value < previous) {
        total -= value;
      } else {
        total += value;
        previous = value;
      }
    }
    return total > 0 ? total : null;
  }

  static void _mergeEmptyChapters(List<_MutableChapter> chapters) {
    for (var i = chapters.length - 1; i >= 0; i--) {
      final chapter = chapters[i];
      final hasContent = chapter.blocks.any(
        (block) =>
            block.text.trim().isNotEmpty ||
            block.type == BlockType.image ||
            block.type == BlockType.table,
      );
      if (hasContent || chapters.length == 1) continue;

      if (i > 0) {
        chapters.removeAt(i);
      } else {
        final blocks = chapter.blocks;
        chapters.removeAt(0);
        chapters.first.blocks.insertAll(0, blocks);
      }
    }
  }

  static List<BookBlock> _blocksWithoutDuplicateTitleHeading(
    _MutableChapter chapter,
  ) {
    final blocks = List<BookBlock>.of(chapter.blocks);
    if (blocks.isEmpty) return blocks;
    final first = blocks.first;
    final isHeading =
        first.type == BlockType.heading ||
        first.type == BlockType.sectionHeading ||
        first.type == BlockType.documentTitle;
    if (isHeading &&
        _normalizeTitle(first.text) == _normalizeTitle(chapter.title)) {
      blocks.removeAt(0);
    }
    return blocks;
  }

  static List<BookBlock> _dedupeConsecutiveHeadings(List<BookBlock> blocks) {
    final cleaned = <BookBlock>[];
    for (final block in blocks) {
      final previous = cleaned.isEmpty ? null : cleaned.last;
      if (previous != null &&
          _isHeading(previous) &&
          _isHeading(block) &&
          _normalizeTitle(previous.text) == _normalizeTitle(block.text)) {
        continue;
      }
      cleaned.add(block);
    }
    return cleaned;
  }

  static bool _isHeading(BookBlock block) =>
      block.type == BlockType.heading ||
      block.type == BlockType.sectionHeading ||
      block.type == BlockType.documentTitle;

  /// A display line that is actually a sentence, not a title.
  static bool _isSentenceTitle(String title) {
    final text = title.trim();
    if (text.isEmpty) return false;
    if (text.endsWith('.')) return true;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return words > 14 &&
        (text.endsWith('.') || text.endsWith('?') || text.endsWith('!'));
  }

  static bool _isSubstantial(_MutableChapter chapter) {
    final characters = chapter.blocks.fold<int>(
      0,
      (sum, block) => sum + block.text.length,
    );
    return chapter.blocks.length > _substantialBlockCount ||
        characters > _substantialCharacterCount;
  }

  static String _normalizeTitle(String title) => title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
      .trim();
}

class _MutableChapter {
  final String id;
  String title;
  final List<BookBlock> blocks;
  final int order;

  _MutableChapter({
    required this.id,
    required this.title,
    required this.blocks,
    required this.order,
  });
}
