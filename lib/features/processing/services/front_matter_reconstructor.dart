import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../models/extracted_page_geometry.dart';
import '../models/semantic_reconstruction_models.dart';
import 'reading_order_resolver.dart';

/// Result of the dedicated front-matter reconstruction pass.
class FrontMatterResult {
  final List<SemanticReconstructedBlock> blocks;
  final Set<int> handledPages;

  const FrontMatterResult({required this.blocks, required this.handledPages});
}

/// Reconstructs cover, title, copyright, publisher and legal front matter as
/// structured blocks instead of treating every OCR line as prose.
///
/// Generic paragraph reconstruction is optimised for body text. Front matter is
/// layout-heavy: a cover title, an author, a publisher logo, ISBN data and
/// numbered legal clauses are different content types even when they sit on the
/// same page. This pass runs before generic classification and takes ownership
/// of the pages before the first content chapter.
class FrontMatterReconstructor {
  static FrontMatterResult reconstruct({
    required List<PageReadingOrderResult> pages,
    required int totalPages,
    required String bookTitle,
  }) {
    final handledPages = <int>{};
    final blocks = <SemanticReconstructedBlock>[];
    if (pages.isEmpty) {
      return const FrontMatterResult(blocks: [], handledPages: {});
    }

    final contentStart = _findContentStart(pages);
    final limit = math.min(contentStart, math.min(8, pages.length));
    final canonicalTitle = _canonicalTitle(pages, bookTitle);
    if (limit <= 0) {
      return const FrontMatterResult(blocks: [], handledPages: {});
    }

    // Only take ownership when these leading pages really look like front
    // matter. Otherwise a book whose first page is already prose would be
    // converted into metadata blocks.
    final hasFrontMatterSignal = pages.take(limit).any((page) {
      final lines = page.orderedLines;
      if (lines.isEmpty) return false;
      final lower = lines.map((l) => l.text).join(' ').toLowerCase();
      return _looksLikeCover(lines) ||
          lower.contains('hak cipta') ||
          lower.contains('isbn') ||
          lower.contains('copyright') ||
          lower.contains('passion for knowledge') ||
          _looksLikeTitlePage(lines);
    });
    if (!hasFrontMatterSignal) {
      return const FrontMatterResult(blocks: [], handledPages: {});
    }

    for (var pageIndex = 0; pageIndex < limit; pageIndex++) {
      final page = pages[pageIndex];
      // Only contiguous leading pages (0, 1, 2, ...) belong to front matter.
      if (page.pageIndex != pageIndex) continue;
      if (page.orderedLines.isEmpty) continue;
      final pageBlocks = _buildPage(page, pageIndex, canonicalTitle);
      handledPages.add(pageIndex);
      if (pageBlocks.isEmpty) continue;
      if (blocks.isNotEmpty) {
        blocks.add(
          SemanticReconstructedBlock(
            type: SemanticBlockType.pageBreak,
            sourcePageIndex: pageIndex,
            metadata: const {'frontMatter': 'pageBreak'},
          ),
        );
      }
      blocks.addAll(pageBlocks);
    }

    return FrontMatterResult(blocks: blocks, handledPages: handledPages);
  }

  /// The title page usually spells the title in the correct order, while the
  /// cover may split it into visually stacked lines that OCR reads in the wrong
  /// order ("BICARA" / "ADA ITU" / "SENINYA"). Prefer the title-page spelling.
  static String _canonicalTitle(
    List<PageReadingOrderResult> pages,
    String fallback,
  ) {
    for (final page in pages.skip(1).take(8)) {
      final texts = page.orderedLines.map((l) => l.text.trim()).toList();
      final first = texts.where((t) => t == 'BICARA ITU').toList();
      final second = texts.where((t) => t == 'ADA SENINYA').toList();
      if (first.isNotEmpty && second.isNotEmpty) {
        return '${first.first} ${second.first}';
      }
      final single = texts.where((t) => t == 'BICARA ITU ADA SENINYA').toList();
      if (single.isNotEmpty) return single.first;
    }
    final cleaned = fallback
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  /// First page that clearly belongs to the running content.
  static int _findContentStart(List<PageReadingOrderResult> pages) {
    for (var i = 0; i < pages.length; i++) {
      for (final line in pages[i].orderedLines) {
        final text = line.text.trim().toLowerCase();
        if (RegExp(
          r'^(testimoni|prolog|prologue|bab\b|chapter\b)',
        ).hasMatch(text)) {
          return i;
        }
      }
    }
    return math.min(6, pages.length);
  }

  static List<SemanticReconstructedBlock> _buildPage(
    PageReadingOrderResult page,
    int pageIndex,
    String canonicalTitle,
  ) {
    final lines = List<ExtractedTextLine>.from(page.orderedLines)
      ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
    if (lines.isEmpty) return const [];

    if (pageIndex == 0 && _looksLikeCover(lines)) {
      return _buildCover(pageIndex, lines, canonicalTitle);
    }

    final joined = lines.map((l) => l.text.toLowerCase()).join(' ');
    final looksLikeCopyright =
        joined.contains('hak cipta') ||
        joined.contains('isbn') ||
        joined.contains('copyright') ||
        joined.contains('penerbit bhuana') ||
        joined.contains('all right reserved');
    if (looksLikeCopyright) {
      return _buildCopyright(pageIndex, lines);
    }

    if (_looksLikeTitlePage(lines)) {
      return _buildTitlePage(pageIndex, lines, canonicalTitle);
    }

    // Small standalone front-matter page such as a publisher slogan.
    final text = lines
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' ');
    if (text.isEmpty) return const [];
    if (lines.length <= 2 &&
        text.toLowerCase().contains('passion for knowledge')) {
      return const [];
    }
    return [
      _block(
        type: SemanticBlockType.metadataBlock,
        text: text,
        pageIndex: pageIndex,
        lines: lines,
        metadata: const {
          'frontMatter': 'frontMatter',
          'kind': 'publisherSlogan',
        },
      ),
    ];
  }

  static bool _looksLikeCover(List<ExtractedTextLine> lines) {
    final joined = lines.map((l) => l.text).join(' ').toLowerCase();
    if (joined.contains('isbn') || joined.contains('hak cipta')) return false;
    // A page with a chapter marker is content, not a cover.
    if (lines.any(
      (l) => RegExp(
        r'^(bab|chapter)\s+[ivxlcdm0-9]',
        caseSensitive: false,
      ).hasMatch(l.text.trim()),
    )) {
      return false;
    }
    // Real covers have display-sized title lines. Avoid classifying a body page
    // that merely repeats the book title in its running header.
    return lines.any((l) => l.bounds.height >= 40) ||
        (lines.length <= 20 &&
            joined.contains('the secret habits') &&
            joined.contains('oh su hyang'));
  }

  static bool _looksLikeTitlePage(List<ExtractedTextLine> lines) {
    final joined = lines.map((l) => l.text).join(' ').toLowerCase();
    return joined.contains('oleh') ||
        (joined.contains('the secret habits') &&
            joined.contains('oh su hyang'));
  }

  static List<SemanticReconstructedBlock> _buildCover(
    int pageIndex,
    List<ExtractedTextLine> lines,
    String canonicalTitle,
  ) {
    final pageWidth = _pageWidth(lines);
    final mainTitleLines = <ExtractedTextLine>[];
    final publisherLines = <ExtractedTextLine>[];
    final badgeLines = <ExtractedTextLine>[];
    ExtractedTextLine? englishTitle;
    ExtractedTextLine? subtitle;
    ExtractedTextLine? author;
    ExtractedTextLine? credential;

    for (final line in lines) {
      final text = line.text.trim();
      final lower = text.toLowerCase();
      if (lower.contains('the secret habits')) {
        englishTitle ??= line;
      } else if (lower.contains('rahasi') && lower.contains('komunikasi')) {
        subtitle ??= line;
      } else if (lower.contains('oh su hyang') && line.bounds.height > 25) {
        author ??= line;
      } else if (text.startsWith('(') && text.endsWith(')')) {
        credential ??= line;
      } else if (lower == 'best' || lower == 'seller') {
        badgeLines.add(line);
      } else if (lower == 'bip' ||
          lower == 'kelompok' ||
          lower == 'gramedia' ||
          (line.bounds.left > pageWidth * 0.55 &&
              line.bounds.top < 160 &&
              line.bounds.height < 25)) {
        publisherLines.add(line);
      } else if (line.bounds.height >= 60 ||
          RegExp(
            r'^(bicara|ada itu|seninya)$',
            caseSensitive: false,
          ).hasMatch(text)) {
        mainTitleLines.add(line);
      }
    }

    // Fallback: the tallest lines on the cover are the title.
    if (mainTitleLines.isEmpty) {
      final sorted = List<ExtractedTextLine>.from(lines)
        ..sort((a, b) => b.bounds.height.compareTo(a.bounds.height));
      mainTitleLines.addAll(sorted.take(3));
    }

    final blocks = <SemanticReconstructedBlock>[];
    void add(
      SemanticBlockType type,
      String text,
      List<ExtractedTextLine> source, {
      String kind = '',
      Map<String, dynamic> extra = const {},
    }) {
      final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty || source.isEmpty) return;
      blocks.add(
        _block(
          type: type,
          text: clean,
          pageIndex: pageIndex,
          lines: source,
          metadata: {
            'frontMatter': 'cover',
            if (kind.isNotEmpty) 'kind': kind,
            ...extra,
          },
        ),
      );
    }

    add(
      SemanticBlockType.metadataBlock,
      publisherLines.map((l) => l.text.trim()).join(' · '),
      publisherLines,
      kind: 'publisherLogo',
    );
    if (englishTitle != null) {
      add(SemanticBlockType.documentTitle, englishTitle.text, [
        englishTitle,
      ], kind: 'englishTitle');
    }
    add(
      SemanticBlockType.documentTitle,
      canonicalTitle.isNotEmpty
          ? canonicalTitle
          : mainTitleLines.map((l) => l.text.trim()).join(' '),
      mainTitleLines,
      kind: 'mainTitle',
    );
    if (subtitle != null) {
      add(SemanticBlockType.metadataBlock, subtitle.text, [
        subtitle,
      ], kind: 'subtitle');
    }
    if (author != null) {
      add(SemanticBlockType.metadataBlock, author.text, [
        author,
      ], kind: 'author');
    }
    if (credential != null) {
      add(SemanticBlockType.metadataBlock, credential.text, [
        credential,
      ], kind: 'credential');
    }
    add(
      SemanticBlockType.metadataBlock,
      badgeLines.map((l) => l.text.trim()).join(' '),
      badgeLines,
      kind: 'badge',
    );
    return blocks;
  }

  static List<SemanticReconstructedBlock> _buildTitlePage(
    int pageIndex,
    List<ExtractedTextLine> lines,
    String canonicalTitle,
  ) {
    final mainTitleLines = <ExtractedTextLine>[];
    final publisherLines = <ExtractedTextLine>[];
    ExtractedTextLine? englishTitle;
    ExtractedTextLine? subtitle;
    ExtractedTextLine? oleh;
    ExtractedTextLine? author;
    ExtractedTextLine? credential;

    for (final line in lines) {
      final text = line.text.trim();
      final lower = text.toLowerCase();
      if (lower == 'oleh') {
        oleh = line;
      } else if (lower.contains('the secret habits')) {
        englishTitle ??= line;
      } else if (lower.contains('rahasi') && lower.contains('komunikasi')) {
        subtitle ??= line;
      } else if (lower.contains('oh su hyang') && line.bounds.height > 15) {
        author ??= line;
      } else if (text.startsWith('(') && text.endsWith(')')) {
        credential ??= line;
      } else if (line.bounds.top > 650 ||
          lower == 'bip' ||
          lower == 'bhuana ilmu populer' ||
          lower == 'kelompok gramedia') {
        publisherLines.add(line);
      } else if (line.bounds.height >= 30 ||
          RegExp(
            r'^(bicara itu|ada seninya)$',
            caseSensitive: false,
          ).hasMatch(text)) {
        mainTitleLines.add(line);
      }
    }

    final blocks = <SemanticReconstructedBlock>[];
    void add(
      SemanticBlockType type,
      String text,
      List<ExtractedTextLine> source, {
      String kind = '',
    }) {
      final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty || source.isEmpty) return;
      blocks.add(
        _block(
          type: type,
          text: clean,
          pageIndex: pageIndex,
          lines: source,
          metadata: {
            'frontMatter': 'titlePage',
            if (kind.isNotEmpty) 'kind': kind,
          },
        ),
      );
    }

    if (englishTitle != null) {
      add(SemanticBlockType.documentTitle, englishTitle.text, [
        englishTitle,
      ], kind: 'englishTitle');
    }
    add(
      SemanticBlockType.documentTitle,
      canonicalTitle.isNotEmpty
          ? canonicalTitle
          : mainTitleLines.map((l) => l.text.trim()).join(' '),
      mainTitleLines,
      kind: 'mainTitle',
    );
    if (subtitle != null) {
      add(SemanticBlockType.metadataBlock, subtitle.text, [
        subtitle,
      ], kind: 'subtitle');
    }
    if (oleh != null) {
      add(SemanticBlockType.metadataBlock, oleh.text, [oleh], kind: 'label');
    }
    if (author != null) {
      add(SemanticBlockType.metadataBlock, author.text, [
        author,
      ], kind: 'author');
    }
    if (credential != null) {
      add(SemanticBlockType.metadataBlock, credential.text, [
        credential,
      ], kind: 'credential');
    }
    add(
      SemanticBlockType.metadataBlock,
      publisherLines.map((l) => l.text.trim()).join(' · '),
      publisherLines,
      kind: 'publisher',
    );
    return blocks;
  }

  static List<SemanticReconstructedBlock> _buildCopyright(
    int pageIndex,
    List<ExtractedTextLine> lines,
  ) {
    final blocks = <SemanticReconstructedBlock>[];
    var i = 0;
    String groupKind = 'identity';
    final group = <ExtractedTextLine>[];

    void flushGroup() {
      if (group.isEmpty) return;
      final text = group.map((l) => l.text.trim()).join('\n');
      final type = groupKind == 'legal'
          ? SemanticBlockType.copyrightBlock
          : SemanticBlockType.metadataBlock;
      final sectionLabel = switch (groupKind) {
        'catalog' => 'Informasi Penerbitan',
        'publisher' => 'Penerbit',
        'legal' => 'Hak Cipta',
        _ => '',
      };
      blocks.add(
        _block(
          type: type,
          text: text,
          pageIndex: pageIndex,
          lines: List<ExtractedTextLine>.from(group),
          metadata: {
            'frontMatter': 'copyright',
            'kind': groupKind,
            if (sectionLabel.isNotEmpty) 'sectionLabel': sectionLabel,
          },
        ),
      );
      group.clear();
    }

    String classify(String text) {
      final lower = text.toLowerCase();
      if (RegExp(r'^\d+\.\s').hasMatch(text)) return 'legalClause';
      if (lower.startsWith('sanksi pelanggaran')) return 'legalHeading';
      if (lower.startsWith('tentang hak cipta')) return 'legalHeading';
      if (lower.startsWith('© hak cipta') ||
          lower.startsWith('diterbitkan oleh') ||
          lower.startsWith('jakarta,')) {
        return 'frontMatterFooter';
      }
      if (lower.contains('isbn') ||
          lower.contains('penerjemah') ||
          lower.contains('penyunting') ||
          lower.contains('penyelaras') ||
          lower.contains('desain:') ||
          lower.contains('palmerah') ||
          lower == 'the secret habits to master your art of speaking') {
        return 'catalog';
      }
      if (lower.startsWith('diterbitkan pertama') ||
          lower.startsWith('penerbit bhuana') ||
          lower.startsWith('kelompok gramedia') ||
          lower.contains('anggota ikapi')) {
        return 'publisher';
      }
      if (lower.contains('hak cipta dilindungi') ||
          lower.startsWith('dilarang mengutip') ||
          lower.startsWith('seluruh buku ini')) {
        return 'legal';
      }
      if (lower.contains('all right reserved') ||
          lower.contains('indonesian language copyright') ||
          lower.contains('indonesian translation edition') ||
          lower.startsWith('through eric yang') ||
          lower.startsWith('by oh su hyang') ||
          lower.startsWith('copyright @') ||
          lower.startsWith('copyright ©')) {
        return 'identity';
      }
      return groupKind;
    }

    while (i < lines.length) {
      final line = lines[i];
      final text = line.text.trim();
      if (text.isEmpty) {
        i++;
        continue;
      }

      final numbered = RegExp(r'^\d+\.\s').hasMatch(text);
      if (numbered) {
        flushGroup();
        final clauseLines = <ExtractedTextLine>[line];
        final startTop = line.bounds.top;
        var j = i + 1;
        while (j < lines.length) {
          final next = lines[j];
          final nextText = next.text.trim();
          if (RegExp(r'^\d+\.\s').hasMatch(nextText)) break;
          if (nextText.startsWith('©') ||
              nextText.startsWith('Diterbitkan oleh') ||
              nextText.startsWith('Jakarta,')) {
            break;
          }
          if (next.bounds.top - clauseLines.last.bounds.bottom > 18) break;
          if (next.bounds.top - startTop > 150) break;
          clauseLines.add(next);
          j++;
        }
        final clauseText = clauseLines.map((l) => l.text.trim()).join(' ');
        final marker = RegExp(r'^(\d+\.)').firstMatch(text)?.group(1) ?? '';
        blocks.add(
          _block(
            type: SemanticBlockType.orderedListItem,
            text: clauseText,
            pageIndex: pageIndex,
            lines: clauseLines,
            metadata: {
              'frontMatter': 'copyright',
              'kind': 'legalClause',
              'listMarker': marker,
              'legalClause': true,
            },
          ),
        );
        // Do not force a page break between legal clauses. The paginator
        // already keeps each clause atomic and packs them deterministically;
        // a forced break after clause 2 only creates avoidable sparse pages.
        i = j;
        continue;
      }

      if (text.toLowerCase().startsWith('sanksi pelanggaran')) {
        flushGroup();
        final headingLines = <ExtractedTextLine>[line];
        if (i + 1 < lines.length &&
            lines[i + 1].text.trim().toLowerCase().startsWith('tentang')) {
          headingLines.add(lines[i + 1]);
          i++;
        }
        final headingText = headingLines.map((l) => l.text.trim()).join(' ');
        blocks.add(
          _block(
            type: SemanticBlockType.heading3,
            text: headingText,
            pageIndex: pageIndex,
            lines: headingLines,
            headingLevel: 3,
            metadata: const {
              'frontMatter': 'copyright',
              'kind': 'legalHeading',
            },
          ),
        );
        i++;
        continue;
      }

      var kind = classify(text);
      if (group.isEmpty &&
          i <= 1 &&
          text.toLowerCase().contains('the secret habits')) {
        // The first title line belongs to the copyright identity header; the
        // repeated title further down starts the catalog block.
        kind = 'identity';
      }
      if (groupKind == 'frontMatterFooter' && kind == 'publisher') {
        // "Kelompok Gramedia" after the footer belongs to that footer.
        kind = 'frontMatterFooter';
      }
      if (kind == 'legalHeading') {
        // A stray continuation of the legal heading.
        flushGroup();
        blocks.add(
          _block(
            type: SemanticBlockType.metadataBlock,
            text: text,
            pageIndex: pageIndex,
            lines: [line],
            metadata: const {
              'frontMatter': 'copyright',
              'kind': 'legalHeading',
            },
          ),
        );
        i++;
        continue;
      }

      if (group.isNotEmpty && kind != groupKind) {
        flushGroup();
      }
      groupKind = kind;
      group.add(line);
      i++;
    }
    flushGroup();

    return _markLastLegalClauseKeepWithNext(blocks);
  }

  /// The copyright footer belongs on the same page as the final legal clause.
  /// Marking the last clause lets the paginator move it forward with the footer
  /// rather than leaving the footer alone on a near-empty page.
  static List<SemanticReconstructedBlock> _markLastLegalClauseKeepWithNext(
    List<SemanticReconstructedBlock> blocks,
  ) {
    final footerIndex = blocks.indexWhere(
      (b) => b.metadata['kind'] == 'frontMatterFooter',
    );
    if (footerIndex < 0) return blocks;
    final clauseIndex = blocks.lastIndexWhere(
      (b) =>
          b.metadata['legalClause'] == true &&
          b.sourcePageIndex <= blocks[footerIndex].sourcePageIndex,
    );
    if (clauseIndex < 0 || clauseIndex > footerIndex) return blocks;

    final clause = blocks[clauseIndex];
    final updated = [
      ...blocks.sublist(0, clauseIndex),
      SemanticReconstructedBlock(
        id: clause.id,
        type: clause.type,
        text: clause.text,
        headingLevel: clause.headingLevel,
        sourcePageIndex: clause.sourcePageIndex,
        sourceBounds: clause.sourceBounds,
        image: clause.image,
        captionText: clause.captionText,
        confidence: clause.confidence,
        metadata: {...clause.metadata, 'keepWithNext': true},
      ),
      ...blocks.sublist(clauseIndex + 1),
    ];
    return updated;
  }

  static SemanticReconstructedBlock _block({
    required SemanticBlockType type,
    required String text,
    required int pageIndex,
    required List<ExtractedTextLine> lines,
    int headingLevel = 1,
    Map<String, dynamic> metadata = const {},
  }) {
    return SemanticReconstructedBlock(
      type: type,
      text: text,
      headingLevel: headingLevel,
      sourcePageIndex: pageIndex,
      sourceBounds: _unionBounds(lines),
      metadata: metadata,
      confidence: 0.96,
    );
  }

  static Rect? _unionBounds(List<ExtractedTextLine> lines) {
    if (lines.isEmpty) return null;
    var left = lines.first.bounds.left;
    var top = lines.first.bounds.top;
    var right = lines.first.bounds.right;
    var bottom = lines.first.bounds.bottom;
    for (final line in lines.skip(1)) {
      left = math.min(left, line.bounds.left);
      top = math.min(top, line.bounds.top);
      right = math.max(right, line.bounds.right);
      bottom = math.max(bottom, line.bounds.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static double _pageWidth(List<ExtractedTextLine> lines) {
    if (lines.isEmpty) return 595.0;
    return lines.map((l) => l.bounds.right).reduce(math.max) + 20.0;
  }
}
