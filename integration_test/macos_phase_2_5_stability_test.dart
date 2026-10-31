import 'dart:io';
import 'dart:ui' as ui;
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
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';
import 'package:digital_books/features/library/presentation/widgets/backup_restore_dialog.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  final sampleDoc = ReaderDocument(
    bookId: 'book-mac-stability-qa',
    title: 'The Principles of Calm & Resilient Thinking',
    author: 'Seneca & Epictetus',
    totalPages: 35,
    chapters: [
      ReaderChapter(
        id: 'c1',
        title: 'Chapter 1: Equanimity in Action',
        index: 0,
        nodes: [
          const ContentNode(
            id: 'h1',
            type: ContentNodeType.heading,
            text: 'Chapter 1: Equanimity in Action',
            level: 1,
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'p1',
            type: ContentNodeType.paragraph,
            text:
                'True stability comes not from the absence of external storms, but from the unyielding tranquility anchored deep within the mind. We suffer more often in imagination than in reality.',
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'p2',
            type: ContentNodeType.paragraph,
            text:
                'Every difficulty is an opportunity to cultivate patience, reason, and courageous judgment. When the mind remains steadfast, no adversity can shake its foundation.',
            sourcePdfPage: 2,
          ),
        ],
      ),
    ],
  );

  testWidgets(
    'Phase 2.5 Native macOS Visual QA: Settings, Backup/Restore, Relink Alert, Reading Comfort',
    (tester) async {
      final keySettings = GlobalKey();
      final keyBackupModal = GlobalKey();
      final keyRelinkAlert = GlobalKey();
      final keyReadingComfort = GlobalKey();
      final keyEmptyState = GlobalKey();

      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);

      final now = DateTime.now();
      await db
          .into(db.books)
          .insert(
            BooksCompanion(
              id: const drift.Value('book-mac-stability-qa'),
              title: const drift.Value(
                'The Principles of Calm & Resilient Thinking',
              ),
              author: const drift.Value('Seneca & Epictetus'),
              originalPdfPath: const drift.Value('/tmp/stoikisme.pdf'),
              totalPages: const drift.Value(35),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

      final userHighlight = Highlight(
        id: 'hl-stability-1',
        bookId: 'book-mac-stability-qa',
        chapterId: 'c1',
        selectedText: 'unyielding tranquility anchored deep within the mind',
        startPosition: 1,
        endPosition: 1,
        color: 'yellow',
        note: 'Key insight on resilience',
        anchorNodeId: 'p1',
        startOffset: 65,
        endOffset: 118,
        createdAt: now,
        anchorVersion: 1,
      );

      // --- SCREENSHOT 1: Settings with Data Integrity & Backup (Version 0.2.6) ---
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF141416),
            ),
            home: RepaintBoundary(
              key: keySettings,
              child: const SizedBox(
                width: 1000,
                height: 750,
                child: LibraryScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Settings in sidebar
      final settingsTile = find.text('Settings');
      if (settingsTile.evaluate().isNotEmpty) {
        await tester.tap(settingsTile);
        await tester.pumpAndSettle();
      }

      await captureBoundary(
        keySettings,
        'phase_2_5_library_settings_backup.png',
      );

      // --- SCREENSHOT 2: Backup & Restore Modal ---
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF141416),
            ),
            home: RepaintBoundary(
              key: keyBackupModal,
              child: const Scaffold(
                backgroundColor: Color(0xFF141416),
                body: Center(child: BackupRestoreDialog()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureBoundary(
        keyBackupModal,
        'phase_2_5_backup_restore_modal.png',
      );

      // --- SCREENSHOT 3: File Checksum Mismatch Alert ---
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: keyRelinkAlert,
            child: Scaffold(
              backgroundColor: const Color(0xFF141416),
              body: Center(
                child: AlertDialog(
                  backgroundColor: const Color(0xFF1E1E22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withAlpha(25)),
                  ),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orangeAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'File Checksum Mismatch',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: const Text(
                    'The selected PDF does not match the original file checksum (SHA-256). It appears to be a different document.\n\nRelinking to an incompatible file may cause existing bookmarks, highlights, and reading positions to be inaccurate.\n\nDo you want to proceed anyway?',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {},
                      child: const Text('Relink Anyway'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureBoundary(
        keyRelinkAlert,
        'phase_2_5_relink_checksum_alert.png',
      );

      // --- SCREENSHOT 4: Reading Comfort & Annotations ---
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            readingThemeStateProvider.overrideWith(
              (ref) => ReadingThemeType.sepia,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: keyReadingComfort,
              child: SizedBox(
                width: 950,
                height: 700,
                child: Scaffold(
                  backgroundColor: ReadingThemeType.sepia.backgroundColor,
                  body: ReflowableReaderContainer(
                    bookId: 'book-mac-stability-qa',
                    document: sampleDoc,
                    theme: ReadingThemeType.sepia,
                    typography: const TypographySettings(
                      fontSize: 19,
                      lineSpacing: 1.65,
                      fontFamily: ReadingFontFamily.serif,
                      twoPageSpread: false,
                    ),
                    customHighlights: [userHighlight],
                    onTapContent: () {},
                    onProgressChanged: (ch, p, pct, anchor, offset) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureBoundary(
        keyReadingComfort,
        'phase_2_5_reading_comfort_annotations.png',
      );

      // --- SCREENSHOT 5: Empty State Polish ---
      await tester.pumpWidget(
        RepaintBoundary(
          key: keyEmptyState,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: const SizedBox(
              width: 900,
              height: 600,
              child: Scaffold(
                backgroundColor: Color(0xFF141416),
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_special_rounded,
                          size: 56,
                          color: Color(0xFF007AFF),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No Collections Yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Organize your digital library into custom categories like "Favorites", "Science", or "Philosophy".',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureBoundary(keyEmptyState, 'phase_2_5_empty_state_polish.png');

      await db.close();
    },
  );
}
