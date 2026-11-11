// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/models/book_document.dart';

const _bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
const _jsonPath =
    '/Users/davindalana/Documents/DigitalBooks/books/$_bookId.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Book Mode composition audit on the real book', () async {
    final dbFile = File('/Users/davindalana/Documents/digital_books_db.sqlite');
    final pdfFile = File(
      '/Users/davindalana/Documents/DigitalBooks/originals/$_bookId.pdf',
    );
    BookDocument? book;
    if (dbFile.existsSync() && pdfFile.existsSync()) {
      final db = AppDatabase(NativeDatabase(dbFile));
      final dbService = DatabaseService(db);
      final pipeline = OcrSemanticPipeline(dbService);
      book = await pipeline.reconstructDocument(
        bookId: _bookId,
        pdfPath: pdfFile.path,
      );
      await db.close();
    }

    if (book == null) {
      final file = File(_jsonPath);
      if (!file.existsSync()) {
        markTestSkipped('Real book JSON not found at $_jsonPath');
        return;
      }
      book = BookDocument.fromJsonString(await file.readAsString());
    }
    final readerDoc = ReflowableEngine.normalizeDocument(book);

    final attributeCount = readerDoc.chapters
        .expand((c) => c.nodes)
        .where((n) => n.attributes.isNotEmpty)
        .length;
    print('Reader nodes with attributes: $attributeCount');
    print('Reader chapters: ${readerDoc.chapters.length}');
    for (final c in readerDoc.chapters) {
      final kinds = <String>{};
      for (final n in c.nodes) {
        final kind = n.attributes['kind']?.toString();
        if (kind != null) kinds.add(kind);
      }
      print(
        '  ch${c.index} "${c.title}" nodes=${c.nodes.length} '
        'kinds=${kinds.isEmpty ? '-' : kinds.join(',')}',
      );
    }

    for (final size in [
      const (label: 'spread', w: 1102.0, h: 951.0),
      const (label: 'compact', w: 600.0, h: 800.0),
    ]) {
      final typography = TypographySettings(twoPageSpread: size.w >= 850);
      final metrics = _Metrics(size.w, size.h, typography);
      PaginationEngine.clearCache();
      final pages = PaginationEngine.paginateDocument(
        document: readerDoc,
        viewportWidth: size.w,
        viewportHeight: size.h,
        typography: typography,
      );
      print(
        '\n=== ${size.label} (${size.w}x${size.h}) '
        'pages=${pages.length} contentWidth=${metrics.contentWidth.toStringAsFixed(1)} '
        'availableHeight=${metrics.availableHeight.toStringAsFixed(1)}',
      );

      final sparse = <(int, double, int)>[];
      final headingLast = <int>[];
      final singleSlice = <int>[];
      final overflow = <(int, double)>[];
      var totalUtil = 0.0;
      var nonTerminalCount = 0;

      for (var i = 0; i < pages.length; i++) {
        final p = pages[i];
        final measured = metrics.measurePage(p);
        final isTerminal =
            i == pages.length - 1 ||
            (i < pages.length - 1 && pages[i + 1].pageIndexInChapter == 0);
        final isFrontMatter = p.chapterIndex == 0;
        final util = measured.height / metrics.availableHeight;
        if (measured.height > metrics.availableHeight + 0.5) {
          overflow.add((i, measured.height));
        }
        if (!isTerminal && !isFrontMatter) {
          totalUtil += util;
          nonTerminalCount++;
          if (util < 0.35) sparse.add((i, util, measured.lines));
        }
        if (p.slices.isNotEmpty && _isHeading(p.slices.last.node.type)) {
          headingLast.add(i);
        }
        if (p.slices.length <= 1) singleSlice.add(i);
      }

      print(
        'non-terminal avg util: '
        '${nonTerminalCount == 0 ? '-' : '${(totalUtil / nonTerminalCount * 100).toStringAsFixed(1)}%'}',
      );
      print('overflow pages (${overflow.length}):');
      for (final o in overflow.take(20)) {
        print(
          '  page ${o.$1} h=${o.$2.toStringAsFixed(1)} :: '
          '${_summary(pages[o.$1])}',
        );
      }
      expect(
        overflow,
        isEmpty,
        reason: 'Zero overflow pages required across viewports',
      );
      print('sparse (<35%) (${sparse.length}):');
      for (final s in sparse.take(40)) {
        print(
          '  page ${s.$1} util=${(s.$2 * 100).toStringAsFixed(1)}% '
          'lines=${s.$3} :: ${_summary(pages[s.$1])}',
        );
      }
      print('heading as last slice (${headingLast.length}):');
      for (final i in headingLast.take(30)) {
        print('  page $i :: ${_summary(pages[i])}');
      }
      print('single-slice pages (${singleSlice.length}):');
      for (final i in singleSlice.take(30)) {
        print('  page $i :: ${_summary(pages[i])}');
      }

      // Front-matter composition (chapter 0).
      final front = pages.where((p) => p.chapterIndex == 0).toList();
      print('front-matter pages: ${front.length}');
      for (final p in front) {
        final m = metrics.measurePage(p);
        print(
          '  ch0 page ${p.pageIndexInBook} (${p.pageIndexInChapter + 1}) '
          'util=${(m.height / metrics.availableHeight * 100).toStringAsFixed(1)}% '
          ':: ${_summary(p)}',
        );
      }

      // TOC composition (find the chapter whose nodes contain toc entries).
      for (final c in readerDoc.chapters) {
        final hasToc = c.nodes.any(
          (n) =>
              n.attributes['kind'] == 'tocEntry' ||
              n.attributes['kind'] == 'tocChapterLabel',
        );
        if (!hasToc) continue;
        final toc = pages.where((p) => p.chapterIndex == c.index).toList();
        print('toc chapter ${c.index} "${c.title}" pages: ${toc.length}');
        for (final p in toc) {
          final m = metrics.measurePage(p);
          print(
            '  toc page ${p.pageIndexInBook} '
            'util=${(m.height / metrics.availableHeight * 100).toStringAsFixed(1)}% '
            ':: ${_summary(p)}',
          );
        }
      }
    }
  });
}

class _Metrics {
  final double contentWidth;
  final double availableHeight;
  final TypographySettings typography;

  _Metrics(double viewportWidth, double viewportHeight, this.typography)
    : contentWidth = _contentWidth(viewportWidth, typography),
      availableHeight = (viewportHeight - 16.0 - 28.0 - 24.0).clamp(
        120.0,
        4000.0,
      );

  static double _contentWidth(
    double viewportWidth,
    TypographySettings typography,
  ) {
    final spread = viewportWidth >= 850.0 && typography.twoPageSpread;
    final rawPageWidth = spread
        ? ((viewportWidth - 24.0) / 2.0)
        : viewportWidth;
    final margin = rawPageWidth < 400.0
        ? 18.0
        : (rawPageWidth < 650.0
              ? 24.0
              : math.max(32.0, typography.horizontalMargin));
    return (rawPageWidth - (margin * 2.0)).clamp(160.0, spread ? 620.0 : 680.0);
  }

  ({double height, int lines}) measurePage(PaginatedPage page) {
    var height = 0.0;
    var lines = 0;
    for (final s in page.slices) {
      if (s.node.type == ContentNodeType.image) {
        height += 220.0 + (s.node.text.trim().isNotEmpty ? 28.0 : 0.0);
        height += typography.paragraphSpacing;
        lines += 8;
        continue;
      }
      final style = PaginationEngine.textStyleFor(s.node, typography);
      final tp = TextPainter(
        text: TextSpan(text: s.textSlice, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
      height += tp.height + PaginationEngine.paddingFor(s.node, typography);
      lines += tp.computeLineMetrics().length;
      tp.dispose();
    }
    return (height: height, lines: lines);
  }
}

bool _isHeading(ContentNodeType t) =>
    t == ContentNodeType.heading ||
    t == ContentNodeType.sectionHeading ||
    t == ContentNodeType.documentTitle;

String _summary(PaginatedPage p) {
  return p.slices
      .map((s) {
        final text = s.textSlice.replaceAll('\n', ' ').trim();
        final short = text.length > 45 ? '${text.substring(0, 45)}…' : text;
        return '${s.node.type.name}[${s.node.attributes['kind'] ?? ''}]"$short"';
      })
      .join(' | ');
}
