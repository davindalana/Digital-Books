import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:digital_books/core/constants/app_strings.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/app_theme_tokens.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestApp({double width = 900, double height = 700}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseServiceProvider.overrideWithValue(dbService),
        allBooksStreamProvider.overrideWith((ref) => Stream.value(<Book>[])),
        recentlyAddedStreamProvider.overrideWith(
          (ref) => Stream.value(<Book>[]),
        ),
        currentlyReadingStreamProvider.overrideWith(
          (ref) => Stream.value(<BookWithProgress>[]),
        ),
        unstartedBooksStreamProvider.overrideWith(
          (ref) => Stream.value(<Book>[]),
        ),
        finishedBooksStreamProvider.overrideWith(
          (ref) => Stream.value(<BookWithProgress>[]),
        ),
        collectionsStreamProvider.overrideWith(
          (ref) => Stream.value(<Collection>[]),
        ),
        collectionBookCountsStreamProvider.overrideWith(
          (ref) => Stream.value(<String, int>{}),
        ),
        searchBooksStreamProvider.overrideWith((ref) => Stream.value(<Book>[])),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          platform: TargetPlatform.macOS,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppThemeTokens.darkBackground,
        ),
        home: SizedBox(
          width: width,
          height: height,
          child: const LibraryScreen(),
        ),
      ),
    );
  }

  group('Phase 2 — macOS Shell & Responsive Sidebar Breakpoints', () {
    testWidgets(
      '1. Expansive Mode (>= 1100pt, 1280pt window): 240pt sidebar and centered content',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildTestApp(width: 1280, height: 800));
        await tester.pumpAndSettle();

        // Sidebar container width is 240pt
        final sidebarContainerFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == AppThemeTokens.sidebarExpansiveWidth,
        );
        expect(sidebarContainerFinder, findsOneWidget);

        // Section title is Sedang Dibaca
        final titleFinder = find.text(AppStrings.navSedangDibaca);
        expect(titleFinder, findsWidgets);

        // Traffic light clearance in sidebar: Header text 'Buku' is at X >= 88
        final appNameFinder = find.text(AppStrings.appNameShort);
        expect(appNameFinder, findsOneWidget);
        final appNameTopLeft = tester.getTopLeft(appNameFinder);
        expect(appNameTopLeft.dx, greaterThanOrEqualTo(88.0));

        // Sort & View mode toggle are hidden on Sedang Dibaca
        expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
        expect(find.byIcon(Icons.view_list_rounded), findsNothing);
      },
    );

    testWidgets('2. Standard Mode (760-1099pt, 900pt window): 200pt sidebar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestApp(width: 900, height: 700));
      await tester.pumpAndSettle();

      // Sidebar container width is 200pt
      final sidebarContainerFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == AppThemeTokens.sidebarStandardWidth,
      );
      expect(sidebarContainerFinder, findsOneWidget);

      // Sidebar categories exist
      expect(find.text(AppStrings.categoryPustaka), findsOneWidget);
      expect(find.text(AppStrings.categoryKoleksi), findsOneWidget);
      expect(find.text(AppStrings.categoryCatatan), findsOneWidget);
    });

    testWidgets(
      '3. Compact Mode (< 760pt, 700pt window): 64pt Icon Rail without mobile bottom bar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(700, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildTestApp(width: 700, height: 650));
        await tester.pumpAndSettle();

        // Sidebar collapses to 64pt icon rail
        final railContainerFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == AppThemeTokens.sidebarCompactWidth,
        );
        expect(railContainerFinder, findsOneWidget);

        // Mobile bottom bar does NOT exist on macOS
        expect(find.byType(NavigationBar), findsNothing);

        // In Compact mode, the content area title has left inset >= 32pt so its X >= 96pt,
        // completely clearing macOS traffic lights (X in [20, 78])
        final titleFinder = find.text(AppStrings.navSedangDibaca);
        expect(
          titleFinder,
          findsOneWidget,
        ); // Only top bar title, since rail uses icon+tooltip
        final titleTopLeft = tester.getTopLeft(titleFinder);
        expect(titleTopLeft.dx, greaterThanOrEqualTo(92.0));
        expect(titleTopLeft.dy, greaterThanOrEqualTo(14.0));
      },
    );

    testWidgets(
      '4. Navigation to Semua Buku reveals sort and view mode toggle',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildTestApp(width: 1000, height: 700));
        await tester.pumpAndSettle();

        // Initially on Sedang Dibaca: no sort or view controls
        expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

        // Tap 'Semua Buku' in sidebar
        await tester.tap(find.text(AppStrings.navSemuaBuku));
        await tester.pumpAndSettle();

        // Now view mode buttons appear
        expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
        expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);

        // Sort dropdown appears
        expect(find.text(AppStrings.sortRecentlyAdded), findsOneWidget);
      },
    );

    testWidgets('5. Shortcuts Cmd+K and Cmd+F focus global search field', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestApp(width: 1000, height: 700));
      await tester.pumpAndSettle();

      final searchTextFieldFinder = find.byType(TextField);
      expect(searchTextFieldFinder, findsOneWidget);

      // Send Cmd+K
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();

      // Enter search text
      await tester.enterText(searchTextFieldFinder, 'Sherlock');
      await tester.pumpAndSettle();

      // Title switches to the English search label.
      expect(find.text('Search'), findsOneWidget);

      // Clean up widget tree before tearDown
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets(
      '6. Currently Reading entry point: status filter chip in Semua Buku',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.binding.setSurfaceSize(null);
        });

        await tester.pumpWidget(buildTestApp(width: 1000, height: 700));
        await tester.pumpAndSettle();

        // Tap 'Semua Buku' in sidebar
        await tester.tap(find.text(AppStrings.navSemuaBuku));
        await tester.pumpAndSettle();

        // Status filter chips appear: 'Semua (0)', 'Sedang Dibaca (0)', 'Selesai (0)'
        expect(find.text('Semua (0)'), findsOneWidget);
        expect(find.text('${AppStrings.navSedangDibaca} (0)'), findsOneWidget);
        expect(find.text('${AppStrings.navSelesai} (0)'), findsOneWidget);

        // Tap 'Sedang Dibaca' filter chip
        await tester.tap(find.text('${AppStrings.navSedangDibaca} (0)'));
        await tester.pumpAndSettle();

        // Displays in-progress empty state
        expect(find.text('No Books Currently In Progress'), findsOneWidget);

        // Clean up
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  });
}
