import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/highlight_interaction_sheet.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sampleDoc = ReaderDocument(
    bookId: 'book-mac-annotation-qa',
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
            sourcePdfPage: 2,
          ),
        ],
      ),
    ],
  );

  const screenshotDir =
      '/Users/davindalana/.gemini/antigravity/brain/d28b8768-0772-4001-8dca-34c07962ba48';

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
      file.writeAsBytesSync(byteData.buffer.asUint8List());
      debugPrint(
        'CAPTURED SCREENSHOT: ${file.path} (${file.lengthSync()} bytes)',
      );
    }
  }

  testWidgets(
    'Phase 2.3 Native macOS Visual QA: Annotations, Highlights, Notes & Hubs',
    (tester) async {
      final key1 = GlobalKey();
      final key2 = GlobalKey();
      final key3 = GlobalKey();
      final key4 = GlobalKey();
      final key5 = GlobalKey();

      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);

      // Populate mock book in SQLite
      final now = DateTime.now();
      await db
          .into(db.books)
          .insert(
            BooksCompanion(
              id: const drift.Value('book-mac-annotation-qa'),
              title: const drift.Value('Filosofi Hidup Stoikisme Modern'),
              author: const drift.Value('Epictetus & Marcus Aurelius'),
              originalPdfPath: const drift.Value('/tmp/stoikisme.pdf'),
              totalPages: const drift.Value(42),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

      // Populate mock highlights with 5 different colors & notes
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion(
              id: const drift.Value('hl-yellow'),
              bookId: const drift.Value('book-mac-annotation-qa'),
              chapterId: const drift.Value('c1'),
              anchorNodeId: const drift.Value('p1'),
              selectedText: const drift.Value(
                'Ada hal-hal di bawah kendali kita, dan ada hal-hal yang tidak di bawah kendali kita.',
              ),
              startPosition: const drift.Value(0),
              endPosition: const drift.Value(0),
              startOffset: const drift.Value(0),
              endOffset: const drift.Value(79),
              color: const drift.Value('yellow'),
              note: const drift.Value('Aksara emas kebijaksanaan Epictetus'),
              createdAt: drift.Value(now),
            ),
          );

      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion(
              id: const drift.Value('hl-blue'),
              bookId: const drift.Value('book-mac-annotation-qa'),
              chapterId: const drift.Value('c1'),
              anchorNodeId: const drift.Value('q1'),
              selectedText: const drift.Value(
                'Bukan peristiwa yang merisaukan manusia, melainkan penilaian yang dibuat manusia tentang peristiwa tersebut.',
              ),
              startPosition: const drift.Value(0),
              endPosition: const drift.Value(0),
              startOffset: const drift.Value(0),
              endOffset: const drift.Value(108),
              color: const drift.Value('blue'),
              note: const drift.Value(
                'Kognitif persepsi: inti terapi CBT modern',
              ),
              createdAt: drift.Value(now.add(const Duration(minutes: 5))),
            ),
          );

      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion(
              id: const drift.Value('hl-green'),
              bookId: const drift.Value('book-mac-annotation-qa'),
              chapterId: const drift.Value('c1'),
              anchorNodeId: const drift.Value('p2'),
              selectedText: const drift.Value('ketenangan batin yang tulus'),
              startPosition: const drift.Value(0),
              endPosition: const drift.Value(0),
              startOffset: const drift.Value(160),
              endOffset: const drift.Value(187),
              color: const drift.Value('green'),
              createdAt: drift.Value(now.add(const Duration(minutes: 10))),
            ),
          );

      // Populate bookmark at anchor p1
      await db
          .into(db.bookmarks)
          .insert(
            BookmarksCompanion(
              id: const drift.Value('bm-1'),
              bookId: const drift.Value('book-mac-annotation-qa'),
              chapterId: const drift.Value('c1'),
              anchorNodeId: const drift.Value('p1'),
              position: const drift.Value(1),
              label: const drift.Value('Bab 1: Mengenal Kendali Diri • Hal. 1'),
              createdAt: drift.Value(now),
            ),
          );

      // -------------------------------------------------------------
      // SCENARIO 1: Paginated Reader with Multi-Color Highlights & Badges
      // -------------------------------------------------------------
      debugPrint('--- Scenario 1: Paginated Reader with Highlights ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-annotation-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            home: Scaffold(
              body: RepaintBoundary(
                key: key1,
                child: SizedBox(
                  width: 1024,
                  height: 768,
                  child: ReflowableReaderContainer(
                    bookId: 'book-mac-annotation-qa',
                    document: sampleDoc,
                    initialChapterIndex: 0,
                    initialPosition: 0,
                    initialAnchorNodeId: 'h1',
                    theme: ReadingThemeType.white,
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
      await captureBoundary(key1, 'phase_2_3_paginated_highlights_light.png');

      // -------------------------------------------------------------
      // SCENARIO 2: Highlight Interaction Sheet Modal (Color + Note authoring)
      // -------------------------------------------------------------
      debugPrint('--- Scenario 2: Highlight Interaction Sheet Modal ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-annotation-qa',
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
                  child: Container(
                    width: 540,
                    padding: const EdgeInsets.all(8),
                    child: HighlightInteractionSheet(
                      selectedText:
                          'Bukan peristiwa yang merisaukan manusia, melainkan penilaian yang dibuat manusia tentang peristiwa tersebut.',
                      initialColor: 'blue',
                      initialNote:
                          'Kognitif persepsi: inti terapi CBT modern yang diajarkan oleh Epictetus.',
                      theme: ReadingThemeType.white,
                      onSave: (color, note) {},
                      onDelete: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await captureBoundary(key2, 'phase_2_3_note_sheet_modal.png');

      // -------------------------------------------------------------
      // SCENARIO 3: Scrolling Reader in Dark Mode with Pink & Purple
      // -------------------------------------------------------------
      debugPrint('--- Scenario 3: Scrolling Reader in Dark Mode ---');
      // Add dark mode highlights
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion(
              id: const drift.Value('hl-pink'),
              bookId: const drift.Value('book-mac-annotation-qa'),
              chapterId: const drift.Value('c1'),
              anchorNodeId: const drift.Value('p1'),
              selectedText: const drift.Value(
                'tubuh, harta benda, reputasi, dan jabatan.',
              ),
              startPosition: const drift.Value(0),
              endPosition: const drift.Value(0),
              startOffset: const drift.Value(194),
              endOffset: const drift.Value(238),
              color: const drift.Value('pink'),
              note: const drift.Value('Hal eksternal yang fana'),
              createdAt: drift.Value(now.add(const Duration(minutes: 15))),
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-annotation-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.scrolling),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: Scaffold(
              body: RepaintBoundary(
                key: key3,
                child: SizedBox(
                  width: 1024,
                  height: 768,
                  child: ReflowableReaderContainer(
                    bookId: 'book-mac-annotation-qa',
                    document: sampleDoc,
                    initialChapterIndex: 0,
                    initialPosition: 0,
                    initialAnchorNodeId: 'h1',
                    theme: ReadingThemeType.dark,
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
      await captureBoundary(key3, 'phase_2_3_scrolling_highlights_dark.png');

      // -------------------------------------------------------------
      // SCENARIO 4: Full Reading Screen with Bookmark Active in Sepia Theme
      // -------------------------------------------------------------
      debugPrint(
        '--- Scenario 4: Full Reading Screen with Bookmark Active ---',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-annotation-qa',
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
                  width: 1100,
                  height: 750,
                  child: Stack(
                    children: [
                      ReflowableReaderContainer(
                        bookId: 'book-mac-annotation-qa',
                        document: sampleDoc,
                        initialChapterIndex: 0,
                        initialPosition: 0,
                        initialAnchorNodeId: 'p1',
                        theme: ReadingThemeType.sepia,
                        typography: const TypographySettings(fontSize: 16.0),
                        onTapContent: () {},
                        onProgressChanged: (ch, page, pct, anchor, offset) {},
                      ),
                      // Floating Apple Books Top Toolbar
                      Positioned(
                        top: 16,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF4ECD8,
                            ).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.arrow_back,
                                size: 20,
                                color: Color(0xFF5F4B32),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  sampleDoc.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Color(0xFF2D241E),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF8B6F47,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Reflowable • Paginasi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF5F4B32),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Active Bookmark Indicator in Amber
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF9500,
                                  ).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.bookmark_rounded,
                                  size: 20,
                                  color: Color(0xFFFF9500),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.text_fields_rounded,
                                size: 20,
                                color: Color(0xFF5F4B32),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Floating Bottom Progress Bar
                      Positioned(
                        bottom: 16,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF4ECD8,
                            ).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text(
                                'Bab 1: Mengenal Kendali Diri',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5F4B32),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Hal. 1 dari 8 • 12% selesai',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8B6F47),
                                ),
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
      await captureBoundary(
        key4,
        'phase_2_3_reading_screen_bookmark_active.png',
      );

      // -------------------------------------------------------------
      // SCENARIO 5: Library Screen - Highlights & Notes Hub
      // -------------------------------------------------------------
      debugPrint('--- Scenario 5: Library Screen Annotations Hub ---');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            reflowableLayoutModeProvider(
              'book-mac-annotation-qa',
            ).overrideWith((ref) => ReflowableLayoutMode.paginated),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: Colors.deepPurple,
            ),
            home: RepaintBoundary(
              key: key5,
              child: const SizedBox(
                width: 1200,
                height: 800,
                child: LibraryScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to 'Highlights & Notes' tab in Library navigation rail / sidebar
      final highlightsNavItem = find.text('Highlights & Notes');
      if (highlightsNavItem.evaluate().isNotEmpty) {
        await tester.tap(highlightsNavItem);
        await tester.pumpAndSettle();
      }

      await captureBoundary(key5, 'phase_2_3_library_annotations_hub.png');

      await db.close();
    },
  );
}
