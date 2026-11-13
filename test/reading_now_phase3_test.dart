import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/constants/app_strings.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';
import 'package:digital_books/features/library/presentation/widgets/book_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final book1 = Book(
    id: 'book-1',
    title: 'Atomic Habits',
    author: 'James Clear',
    originalPdfPath: '/mock/atomic_habits.pdf',
    coverPath: null,
    totalPages: 320,
    isScanned: false,
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
    updatedAt: DateTime.now().subtract(const Duration(days: 1)),
  );

  final book2 = Book(
    id: 'book-2',
    title: 'Deep Work',
    author: 'Cal Newport',
    originalPdfPath: '/mock/deep_work.pdf',
    coverPath: null,
    totalPages: 280,
    isScanned: true, // Scanned book
    createdAt: DateTime.now().subtract(const Duration(days: 8)),
    updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
  );

  final book3 = Book(
    id: 'book-3',
    title: 'Filosofi Teras',
    author: 'Henry Manampiring',
    originalPdfPath: '/mock/filosofi_teras.pdf',
    coverPath: null,
    totalPages: 312,
    isScanned: false,
    createdAt: DateTime.now().subtract(const Duration(days: 5)),
    updatedAt: DateTime.now().subtract(const Duration(days: 5)),
  );

  final bookEmptyAuthor = Book(
    id: 'book-4',
    title: 'Unknown Masterpiece',
    author: '   ', // Empty author
    originalPdfPath: '/mock/unknown.pdf',
    coverPath: null,
    totalPages: 100,
    isScanned: false,
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    updatedAt: DateTime.now().subtract(const Duration(days: 2)),
  );

  final heroProgress = ReadingProgress(
    id: 'prog-1',
    bookId: 'book-1',
    currentChapter: 2,
    currentPosition: 80,
    progressPercentage: 0.25, // 25%
    lastReadingMode: 'pdf',
    lastReadAt: DateTime.now().subtract(const Duration(hours: 2)),
  );

  final rak1Progress = ReadingProgress(
    id: 'prog-2',
    bookId: 'book-2',
    currentChapter: 1,
    currentPosition: 42,
    progressPercentage: 0.15, // 15%
    lastReadingMode: 'pdf',
    lastReadAt: DateTime.now().subtract(const Duration(hours: 5)),
  );

  Widget createLibraryScreen({
    List<Book>? allBooks,
    List<BookWithProgress>? currentlyReading,
    List<Book>? unstartedBooks,
  }) {
    return ProviderScope(
      overrides: [
        allBooksStreamProvider.overrideWith(
          (ref) => Stream.value(allBooks ?? [book1, book2, book3]),
        ),
        currentlyReadingStreamProvider.overrideWith(
          (ref) => Stream.value(
            currentlyReading ??
                [
                  BookWithProgress(book: book1, progress: heroProgress),
                  BookWithProgress(book: book2, progress: rak1Progress),
                ],
          ),
        ),
        unstartedBooksStreamProvider.overrideWith(
          (ref) => Stream.value(unstartedBooks ?? [book3]),
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
        recentlyAddedStreamProvider.overrideWith(
          (ref) => Stream.value(allBooks ?? [book1, book2, book3]),
        ),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox(width: 1200, height: 800, child: LibraryScreen()),
        ),
      ),
    );
  }

  group('Phase 3 — Sedang Dibaca & Book Cards Acceptance Tests', () {
    testWidgets(
      '1. Hero Card renders large 220pt cover, relative time eyebrow, 3pt gold progress, and "Lanjutkan" button',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(createLibraryScreen());
        await tester.pumpAndSettle();

        // Eyebrow displays relative time formatted as "TERAKHIR DIBACA 2 JAM LALU"
        expect(find.text('TERAKHIR DIBACA 2 JAM LALU'), findsOneWidget);

        // Title and Author
        expect(find.text('Atomic Habits'), findsOneWidget);
        expect(find.text('James Clear'), findsOneWidget);

        // Progress text formatted via ReadingProgressCalculator
        expect(
          find.textContaining('25% Selesai • Hal. 80 dari 320'),
          findsOneWidget,
        );

        // Action button "Lanjutkan"
        expect(find.text(AppStrings.actionLanjutkan), findsOneWidget);

        // Cover height ~220pt
        final heroCoverFinder = find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 220.0,
        );
        expect(heroCoverFinder, findsOneWidget);

        // Slim 3pt gold progress bar
        final heroProgressFinder = find.byWidgetPredicate(
          (w) => w is LinearProgressIndicator && w.minHeight == 3.0,
        );
        expect(heroProgressFinder, findsWidgets);
      },
    );

    testWidgets(
      '2. BookCard shows dimmed "Penulis tidak diketahui" when author is empty',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 140,
                  height: 260,
                  child: BookCard(book: bookEmptyAuthor),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is BookCard && w.book.title == 'Unknown Masterpiece',
          ),
          findsOneWidget,
        );
        expect(find.text(AppStrings.unknownAuthor), findsOneWidget);
      },
    );

    testWidgets(
      '3. BookCard renders "Pindai" badge in bottom-left corner with correct tooltip for scanned book',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 140,
                  height: 260,
                  child: BookCard(book: book2, progressPercentage: 0.15),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // "Pindai" badge exists
        expect(find.text(AppStrings.badgePindai), findsOneWidget);
        expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);

        // Tooltip message indicates OCR is required (since processedBookPath is null)
        expect(
          find.byTooltip(AppStrings.badgePindaiNeedsOcrTooltip),
          findsOneWidget,
        );

        // Compact percentage text
        expect(find.text('15%'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Strict Deduplication: Hero book is absent from Rak 1 and Rak 2; Rak 1 is absent from Rak 2',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(createLibraryScreen());
        await tester.pumpAndSettle();

        // Hero book is book1 (Atomic Habits)
        // Rak 1 is book2 (Deep Work)
        // Rak 2 is book3 (Filosofi Teras)

        // Find shelf titles
        expect(find.text(AppStrings.shelfBukuLainSedangDibaca), findsOneWidget);
        expect(find.text(AppStrings.shelfBelumDimulai), findsOneWidget);

        // Check deduplication:
        // 'Atomic Habits' only appears in the Hero card (NOT in any BookCard on shelves)
        expect(
          find.byWidgetPredicate(
            (w) => w is BookCard && w.book.title == 'Atomic Habits',
          ),
          findsNothing,
        );

        // 'Deep Work' appears in Rak 1 (findsOneWidget BookCard)
        expect(
          find.byWidgetPredicate(
            (w) => w is BookCard && w.book.title == 'Deep Work',
          ),
          findsOneWidget,
        );

        // 'Filosofi Teras' appears in Rak 2 (findsOneWidget BookCard)
        expect(
          find.byWidgetPredicate(
            (w) => w is BookCard && w.book.title == 'Filosofi Teras',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '5. Rak 2 ("Belum dimulai") is hidden when there are no unstarted books',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          createLibraryScreen(
            unstartedBooks: [], // Empty unstarted books
          ),
        );
        await tester.pumpAndSettle();

        // Shelf 2 is hidden
        expect(find.text(AppStrings.shelfBelumDimulai), findsNothing);
      },
    );

    testWidgets(
      '6. Empty Sedang Dibaca state: shows friendly prompt when library has books but none in progress',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          createLibraryScreen(
            currentlyReading: [], // No book started yet
            unstartedBooks: [book1, book2, book3],
          ),
        );
        await tester.pumpAndSettle();

        // Friendly prompt
        expect(find.text(AppStrings.emptySedangDibacaTitle), findsOneWidget);
        expect(find.text('Choose a Book'), findsOneWidget);

        // Rak "Belum dimulai" is visible right below
        expect(find.text(AppStrings.shelfBelumDimulai), findsOneWidget);
      },
    );

    testWidgets(
      '7. Empty Library state: shows "Tambah Buku" CTA when library has zero books',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          createLibraryScreen(
            allBooks: [],
            currentlyReading: [],
            unstartedBooks: [],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.emptyLibraryTitle), findsOneWidget);
        expect(find.text(AppStrings.actionTambahBuku), findsWidgets);
      },
    );

    testWidgets(
      '8. "Lihat semua →" button in Rak 1 switches section to All Books with "Sedang Dibaca" filter',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(createLibraryScreen());
        await tester.pumpAndSettle();

        final seeAllFinder = find.text('Lihat semua');
        expect(seeAllFinder, findsOneWidget);

        await tester.tap(seeAllFinder);
        await tester.pumpAndSettle();

        // We should now be in All Books with filter chips
        expect(find.text('Semua (3)'), findsOneWidget);
      },
    );
  });
}
