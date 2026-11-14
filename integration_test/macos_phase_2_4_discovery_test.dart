import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/book_search_dialog.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/presentation/widgets/search_traversal_bar.dart';
import 'package:digital_books/features/reader/presentation/widgets/toc_dialog.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sampleDoc = ReaderDocument(
    bookId: 'book-mac-discovery-qa',
    title: 'Filosofi Hidup Stoikisme Modern',
    author: 'Epictetus & Marcus Aurelius',
    totalPages: 42,
    chapters: [
      ReaderChapter(
        id: 'c1',
        title: 'Bab 1: Mengenal Kendali Diri',
        index: 0,
        nodes: [
          const ContentNode(
            id: 'h1',
            type: ContentNodeType.heading,
            text: 'Prinsip Dasar Dikotomi Kendali',
            level: 1,
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'p1',
            type: ContentNodeType.paragraph,
            text:
                'Ada hal-hal di bawah kendali kita, dan ada hal-hal yang tidak di bawah kendali kita. Pikiran, dorongan jiwa, keinginan, keengganan—singkat kata, apa pun yang berasal dari tindakan kita sendiri. Di luar kendali kita adalah tubuh, harta benda, reputasi, dan jabatan.',
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'h2',
            type: ContentNodeType.heading,
            text: 'Bagian A: Mengelola Reaksi Batin',
            level: 2,
            sourcePdfPage: 2,
          ),
          const ContentNode(
            id: 'q1',
            type: ContentNodeType.quote,
            text:
                'Bukan peristiwa yang merisaukan manusia, melainkan penilaian yang dibuat manusia tentang peristiwa tersebut.',
            sourcePdfPage: 2,
          ),
          const ContentNode(
            id: 'p2',
            type: ContentNodeType.paragraph,
            text:
                'Ketika kita memahami dikotomi kendali, kecemasan tidak lagi menguasai kehidupan sehari-hari. Kita memusatkan daya pada apa yang dapat diubah dan menerima apa yang di luar jangkauan dengan ketenangan batin yang tulus.',
            sourcePdfPage: 3,
          ),
        ],
      ),
      ReaderChapter(
        id: 'c2',
        title: 'Bab 2: Ketenangan dalam Badai',
        index: 1,
        nodes: [
          const ContentNode(
            id: 'h3',
            type: ContentNodeType.heading,
            text: 'Latihan Mental Setiap Pagi',
            level: 1,
            sourcePdfPage: 4,
          ),
          const ContentNode(
            id: 'p3',
            type: ContentNodeType.paragraph,
            text:
                'Ketenangan batin sejati bermula dari penerimaan tulus terhadap hal yang di luar kendali kita. Hadapi hari dengan kesiapan jiwa.',
            sourcePdfPage: 4,
          ),
        ],
      ),
    ],
  );

  final screenshotDir =
      p.join(Directory.systemTemp.path, 'db_phase_2_4_screenshots');

  Future<void> captureBoundary(GlobalKey key, String filename) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint('WARNING: Could not find RenderRepaintBoundary for $filename');
      return;
    }
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final file = File('$screenshotDir/$filename');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
      debugPrint(
        'CAPTURED SCREENSHOT: ${file.path} (${file.lengthSync()} bytes)',
      );
    }
  }

  testWidgets(
    'Phase 2.4 Native macOS Visual QA: TOC, Search, Traversal & History',
    (tester) async {
      final key1 = GlobalKey();
      final key2 = GlobalKey();
      final key3 = GlobalKey();
      final key4 = GlobalKey();
      final key5 = GlobalKey();

      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);

      final now = DateTime.now();
      await db
          .into(db.books)
          .insert(
            BooksCompanion(
              id: const drift.Value('book-mac-discovery-qa'),
              title: const drift.Value('Filosofi Hidup Stoikisme Modern'),
              author: const drift.Value('Epictetus & Marcus Aurelius'),
              originalPdfPath: const drift.Value('/tmp/stoikisme.pdf'),
              totalPages: const drift.Value(42),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

      // Add user saved highlight in yellow
      final userHighlight = Highlight(
        id: 'hl-user-1',
        bookId: 'book-mac-discovery-qa',
        chapterId: 'c1',
        selectedText: 'Pikiran, dorongan jiwa, keinginan, keengganan',
        startPosition: 0,
        endPosition: 0,
        color: 'yellow',
        note: 'Fokus kendali internal',
        anchorNodeId: 'p1',
        startOffset: 77,
        endOffset: 122,
        anchorVersion: 1,
        createdAt: now,
      );

      // Active search match in bright amber
      const searchMatch = ActiveSearchMatch(
        nodeId: 'p1',
        startOffset: 16,
        endOffset: 23, // Matches 'kendali'
        isActive: true,
      );

      // -------------------------------------------------------------
      // SCENARIO 1: Hierarchical Table of Contents Dialog (Expanded Sections)
      // -------------------------------------------------------------
      debugPrint('--- Scenario 1: Hierarchical TOC Panel ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-discovery-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            home: Scaffold(
              backgroundColor: const Color(0xFFE2E8F0),
              body: Center(
                child: RepaintBoundary(
                  key: key1,
                  child: SizedBox(
                    width: 580,
                    height: 600,
                    child: TocDialog(
                      bookId: 'book-mac-discovery-qa',
                      readerDocument: sampleDoc,
                      currentChapterIndex: 0,
                      currentAnchorNodeId: 'h2',
                      onNavigateToChapter: (ch, page) {},
                      onNavigateToPosition: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await captureBoundary(key1, 'phase_2_4_toc_hierarchical_panel.png');

      // -------------------------------------------------------------
      // SCENARIO 2: In-Book Search Dialog with Results & Emphasized Snippets
      // -------------------------------------------------------------
      debugPrint('--- Scenario 2: In-Book Search Dialog ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-discovery-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            home: Scaffold(
              backgroundColor: const Color(0xFFE2E8F0),
              body: Center(
                child: RepaintBoundary(
                  key: key2,
                  child: SizedBox(
                    width: 600,
                    height: 620,
                    child: BookSearchDialog(
                      readerDocument: sampleDoc,
                      theme: ReadingThemeType.white,
                      onNavigateToResult: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Type query and wait for debounce
      await tester.enterText(find.byType(TextField), 'kendali');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await captureBoundary(key2, 'phase_2_4_in_book_search_dialog.png');

      // -------------------------------------------------------------
      // SCENARIO 3: Search Result Navigation with Floating Traversal Bar
      // -------------------------------------------------------------
      debugPrint('--- Scenario 3: Search Traversal in Paginated Reader ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-discovery-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            home: Scaffold(
              body: RepaintBoundary(
                key: key3,
                child: SizedBox(
                  width: 1024,
                  height: 768,
                  child: Stack(
                    children: [
                      ReflowableReaderContainer(
                        bookId: 'book-mac-discovery-qa',
                        document: sampleDoc,
                        initialChapterIndex: 0,
                        initialPosition: 0,
                        initialAnchorNodeId: 'p1',
                        searchMatches: const [searchMatch],
                        theme: ReadingThemeType.white,
                        typography: const TypographySettings(fontSize: 16.0),
                        onTapContent: () {},
                        onProgressChanged: (ch, page, pct, anchor, offset) {},
                      ),
                      // Floating Search Traversal Capsule at Top
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SearchTraversalBar(
                            query: 'kendali',
                            currentIndex: 0,
                            totalCount: 5,
                            theme: ReadingThemeType.white,
                            onPrevious: () {},
                            onNext: () {},
                            onClose: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await captureBoundary(key3, 'phase_2_4_search_traversal_paginated.png');

      // -------------------------------------------------------------
      // SCENARIO 4: Coexistence of Saved Highlight + Search Highlight
      // -------------------------------------------------------------
      debugPrint('--- Scenario 4: Highlight Coexistence ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-discovery-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            home: Scaffold(
              backgroundColor: const Color(0xFFFBF0D9),
              body: RepaintBoundary(
                key: key4,
                child: SizedBox(
                  width: 1024,
                  height: 768,
                  child: ReflowableReaderContainer(
                    bookId: 'book-mac-discovery-qa',
                    document: sampleDoc,
                    initialChapterIndex: 0,
                    initialPosition: 0,
                    initialAnchorNodeId: 'p1',
                    customHighlights: [userHighlight],
                    searchMatches: const [searchMatch],
                    theme: ReadingThemeType.sepia,
                    typography: const TypographySettings(fontSize: 16.0),
                    onTapContent: () {},
                    onProgressChanged: (ch, page, pct, anchor, offset) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await captureBoundary(key4, 'phase_2_4_search_highlight_coexistence.png');

      // -------------------------------------------------------------
      // SCENARIO 5: Full Reader Top Toolbar with Navigation History Back Button
      // -------------------------------------------------------------
      debugPrint('--- Scenario 5: Navigation History Toolbar Active ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-discovery-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            home: Scaffold(
              body: RepaintBoundary(
                key: key5,
                child: SizedBox(
                  width: 1050,
                  height: 750,
                  child: Stack(
                    children: [
                      ReflowableReaderContainer(
                        bookId: 'book-mac-discovery-qa',
                        document: sampleDoc,
                        initialChapterIndex: 1,
                        initialPosition: 0,
                        initialAnchorNodeId: 'p3',
                        theme: ReadingThemeType.white,
                        typography: const TypographySettings(fontSize: 16.0),
                        onTapContent: () {},
                        onProgressChanged: (ch, page, pct, anchor, offset) {},
                      ),
                      // Floating Top Bar with History Back button enabled
                      Positioned(
                        top: 16,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.chevron_left,
                                size: 24,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 4),
                              // Blue History Back button
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF).withAlpha(25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.history_rounded,
                                      size: 16,
                                      color: Color(0xFF007AFF),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Kembali ke Bab 1',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  sampleDoc.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.list_alt,
                                size: 20,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 12),
                              const Icon(
                                Icons.search,
                                size: 20,
                                color: Color(0xFFFF9500),
                              ),
                              const SizedBox(width: 12),
                              const Icon(
                                Icons.bookmark_border,
                                size: 20,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await captureBoundary(key5, 'phase_2_4_navigation_history_active.png');

      await db.close();
    },
  );
}
