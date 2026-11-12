import 'package:digital_books/core/constants/app_strings.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/utils/book_sort_helper.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';
import 'package:digital_books/features/library/presentation/widgets/book_card.dart';
import 'package:digital_books/features/library/presentation/widgets/book_details_dialog.dart';
import 'package:digital_books/features/library/presentation/widgets/book_list_tile.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookSortHelper Unit Tests', () {
    final now = DateTime(2026, 1, 15);
    final bookA = Book(
      id: 'book-a',
      title: 'Atomic Habits',
      author: 'James Clear',
      originalPdfPath: '/path/a.pdf',
      totalPages: 300,
      isScanned: false,
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now.subtract(const Duration(days: 10)),
    );
    final bookB = Book(
      id: 'book-b',
      title: 'Deep Work',
      author: 'Cal Newport',
      originalPdfPath: '/path/b.pdf',
      totalPages: 250,
      isScanned: false,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(days: 5)),
    );
    final bookC = Book(
      id: 'book-c',
      title: 'Thinking, Fast and Slow',
      author: 'Daniel Kahneman',
      originalPdfPath: '/path/c.pdf',
      totalPages: 400,
      isScanned: true,
      createdAt: now,
      updatedAt: now,
    );

    final books = [bookB, bookA, bookC];

    test('Sort by Title A to Z and Z to A', () {
      final sortedAsc = BookSortHelper.sortBooks(
        books,
        BookSortOption.titleAsc,
      );
      expect(sortedAsc.map((b) => b.title).toList(), [
        'Atomic Habits',
        'Deep Work',
        'Thinking, Fast and Slow',
      ]);

      final sortedDesc = BookSortHelper.sortBooks(
        books,
        BookSortOption.titleDesc,
      );
      expect(sortedDesc.map((b) => b.title).toList(), [
        'Thinking, Fast and Slow',
        'Deep Work',
        'Atomic Habits',
      ]);
    });

    test('Sort by Author A to Z', () {
      final sortedAuthor = BookSortHelper.sortBooks(
        books,
        BookSortOption.authorAsc,
      );
      expect(sortedAuthor.map((b) => b.author).toList(), [
        'Cal Newport',
        'Daniel Kahneman',
        'James Clear',
      ]);
    });

    test('Sort by Date Added Descending and Ascending', () {
      final sortedNewest = BookSortHelper.sortBooks(
        books,
        BookSortOption.dateAddedDesc,
      );
      expect(sortedNewest.map((b) => b.id).toList(), [
        'book-c', // now
        'book-b', // now - 5d
        'book-a', // now - 10d
      ]);

      final sortedOldest = BookSortHelper.sortBooks(
        books,
        BookSortOption.dateAddedAsc,
      );
      expect(sortedOldest.map((b) => b.id).toList(), [
        'book-a',
        'book-b',
        'book-c',
      ]);
    });

    test('Sort by Progress with progressMap', () {
      final progressMap = {'book-a': 0.85, 'book-b': 0.10, 'book-c': 0.50};

      final sortedProgDesc = BookSortHelper.sortBooks(
        books,
        BookSortOption.progressDesc,
        progressMap: progressMap,
      );
      expect(sortedProgDesc.map((b) => b.id).toList(), [
        'book-a', // 85%
        'book-c', // 50%
        'book-b', // 10%
      ]);

      final sortedProgAsc = BookSortHelper.sortBooks(
        books,
        BookSortOption.progressAsc,
        progressMap: progressMap,
      );
      expect(sortedProgAsc.map((b) => b.id).toList(), [
        'book-b', // 10%
        'book-c', // 50%
        'book-a', // 85%
      ]);
    });
  });

  group('DatabaseService Phase 1 Functionality', () {
    late AppDatabase db;
    late DatabaseService dbService;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dbService = DatabaseService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Metadata editing updates title, author, description, and timestamp',
      () async {
        final t0 = DateTime(2026, 1, 1);
        const bookId = 'meta-test-book';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Initial Title'),
            author: const drift.Value('Initial Author'),
            description: const drift.Value('Initial Description'),
            originalPdfPath: const drift.Value('/path/original.pdf'),
            totalPages: const drift.Value(120),
            createdAt: drift.Value(t0),
            updatedAt: drift.Value(t0),
          ),
        );

        final bookBefore = await dbService.getBookById(bookId);
        expect(bookBefore!.title, 'Initial Title');
        expect(bookBefore.author, 'Initial Author');

        await dbService.updateBookMetadata(
          bookId,
          title: 'Refined Title',
          author: 'Renowned Author',
          description: 'New detailed notes and summary.',
        );

        final bookAfter = await dbService.getBookById(bookId);
        expect(bookAfter!.title, 'Refined Title');
        expect(bookAfter.author, 'Renowned Author');
        expect(bookAfter.description, 'New detailed notes and summary.');
        expect(bookAfter.updatedAt.isAfter(t0), isTrue);
      },
    );

    test(
      'Duplicate book detection detects existing titles and authors',
      () async {
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('dup-001'),
            title: const drift.Value('The 48 Laws Of Power'),
            author: const drift.Value('Robert Greene'),
            originalPdfPath: const drift.Value('/path/power.pdf'),
            totalPages: const drift.Value(452),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Exact case match
        final match1 = await dbService.findDuplicateBook(
          title: 'The 48 Laws Of Power',
          author: 'Robert Greene',
        );
        expect(match1, isNotNull);
        expect(match1!.id, 'dup-001');

        // Case-insensitive match with extra whitespace
        final match2 = await dbService.findDuplicateBook(
          title: '  the 48 laws of power  ',
          author: 'robert greene',
        );
        expect(match2, isNotNull);
        expect(match2!.id, 'dup-001');

        // Match by title when author is unknown
        final match3 = await dbService.findDuplicateBook(
          title: 'The 48 Laws of Power',
          author: 'Unknown Author',
        );
        expect(match3, isNotNull);
        expect(match3!.id, 'dup-001');

        // Unrelated book returns null
        final matchNone = await dbService.findDuplicateBook(
          title: 'Clean Code',
          author: 'Robert C. Martin',
        );
        expect(matchNone, isNull);
      },
    );

    test('Collections management full lifecycle', () async {
      final now = DateTime.now();
      const colId = 'col-philosophy';
      const book1 = 'book-stoic';
      const book2 = 'book-logic';

      // Insert 2 books
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(book1),
          title: const drift.Value('Meditations'),
          author: const drift.Value('Marcus Aurelius'),
          originalPdfPath: const drift.Value('/path/1.pdf'),
          totalPages: const drift.Value(200),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(book2),
          title: const drift.Value('Tractatus'),
          author: const drift.Value('Ludwig Wittgenstein'),
          originalPdfPath: const drift.Value('/path/2.pdf'),
          totalPages: const drift.Value(150),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // 1. Create Collection
      await dbService.createCollection(
        CollectionsCompanion(
          id: const drift.Value(colId),
          name: const drift.Value('Philosophy'),
          description: const drift.Value('Classical and modern philosophy'),
          createdAt: drift.Value(now),
        ),
      );

      var collections = await dbService.watchCollections().first;
      expect(collections.length, 1);
      expect(collections.first.name, 'Philosophy');

      // 2. Add books to collection
      await dbService.addBookToCollection(book1, colId);
      await dbService.addBookToCollection(book2, colId);

      var booksInCol = await dbService.watchBooksInCollection(colId).first;
      expect(booksInCol.length, 2);
      expect(booksInCol.map((b) => b.id).toSet(), {book1, book2});

      var counts = await dbService.watchCollectionBookCounts().first;
      expect(counts[colId], 2);

      var colIdsForBook1 = await dbService.getCollectionIdsForBook(book1);
      expect(colIdsForBook1, [colId]);

      // 3. Rename Collection
      await dbService.updateCollection(
        colId,
        name: 'Philosophy & Logic',
        description: 'Updated description',
      );
      collections = await dbService.watchCollections().first;
      expect(collections.first.name, 'Philosophy & Logic');

      // 4. Remove one book from collection
      await dbService.removeBookFromCollection(book2, colId);
      booksInCol = await dbService.watchBooksInCollection(colId).first;
      expect(booksInCol.length, 1);
      expect(booksInCol.first.id, book1);

      // 5. Delete collection
      await dbService.deleteCollection(colId);
      collections = await dbService.watchCollections().first;
      expect(collections, isEmpty);

      // Books still exist in library!
      final preservedBook = await dbService.getBookById(book1);
      expect(preservedBook, isNotNull);
    });

    test('Cross-book Bookmarks and Highlights aggregation', () async {
      final now = DateTime.now();
      const book1 = 'book-ann-1';
      const book2 = 'book-ann-2';

      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(book1),
          title: const drift.Value('Book One'),
          author: const drift.Value('Author One'),
          originalPdfPath: const drift.Value('/path/1.pdf'),
          totalPages: const drift.Value(100),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(book2),
          title: const drift.Value('Book Two'),
          author: const drift.Value('Author Two'),
          originalPdfPath: const drift.Value('/path/2.pdf'),
          totalPages: const drift.Value(200),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Add bookmarks across books
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const drift.Value('bm-1'),
          bookId: const drift.Value(book1),
          position: const drift.Value(14),
          label: const drift.Value('Key formula'),
          createdAt: drift.Value(now),
        ),
      );
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const drift.Value('bm-2'),
          bookId: const drift.Value(book2),
          position: const drift.Value(88),
          label: const drift.Value('Crucial proof'),
          createdAt: drift.Value(now.add(const Duration(minutes: 5))),
        ),
      );

      final allBookmarks = await dbService.watchAllBookmarks().first;
      expect(allBookmarks.length, 2);
      expect(allBookmarks.first.bookmark.label, 'Crucial proof'); // newer first
      expect(allBookmarks.first.book.title, 'Book Two');
      expect(allBookmarks[1].book.title, 'Book One');

      // Add highlights across books
      await dbService.addHighlight(
        HighlightsCompanion(
          id: const drift.Value('hl-1'),
          bookId: const drift.Value(book1),
          startPosition: const drift.Value(14),
          endPosition: const drift.Value(14),
          selectedText: const drift.Value(
            'Simplicity is prerequisite for reliability.',
          ),
          color: const drift.Value('yellow'),
          note: const drift.Value('Edsger Dijkstra quote'),
          createdAt: drift.Value(now),
        ),
      );

      final allHighlights = await dbService.watchAllHighlights().first;
      expect(allHighlights.length, 1);
      expect(
        allHighlights.first.highlight.selectedText,
        'Simplicity is prerequisite for reliability.',
      );
      expect(allHighlights.first.book.title, 'Book One');
    });
  });

  group('Phase 1 Widget Tests', () {
    final sampleBook = Book(
      id: 'ui-test-book',
      title: 'Design Patterns',
      author: 'Gang of Four',
      originalPdfPath: '/path/dp.pdf',
      totalPages: 395,
      isScanned: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    testWidgets('BookListTile displays metadata, format, and progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookProgressStreamProvider('ui-test-book').overrideWith(
              (ref) => Stream.value(
                ReadingProgress(
                  id: 'prog-1',
                  bookId: 'ui-test-book',
                  currentChapter: 1,
                  currentPosition: 50,
                  progressPercentage: 0.25,
                  lastReadAt: DateTime.now(),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BookListTile(book: sampleBook, progressPercentage: 0.25),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Design Patterns'), findsOneWidget);
      expect(find.text('Gang of Four'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.textContaining('25% Selesai'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('BookDetailsDialog renders info and supports edit mode', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);
      addTearDown(() => db.close());

      await dbService.insertBook(
        BooksCompanion(
          id: drift.Value(sampleBook.id),
          title: drift.Value(sampleBook.title),
          author: drift.Value(sampleBook.author),
          originalPdfPath: drift.Value(sampleBook.originalPdfPath),
          totalPages: drift.Value(sampleBook.totalPages),
          createdAt: drift.Value(sampleBook.createdAt),
          updatedAt: drift.Value(sampleBook.updatedAt),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseServiceProvider.overrideWithValue(dbService),
            bookProgressStreamProvider(
              'ui-test-book',
            ).overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp(
            home: Scaffold(body: BookDetailsDialog(book: sampleBook)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('BOOK INFO'), findsOneWidget);
      expect(find.text('Design Patterns'), findsOneWidget);
      expect(find.text('Gang of Four'), findsOneWidget);
      expect(find.text('395 pages'), findsOneWidget);

      // Tap Edit Icon
      final editIcon = find.byTooltip('Edit Metadata');
      expect(editIcon, findsOneWidget);
      await tester.tap(editIcon);
      await tester.pumpAndSettle();

      expect(find.text('EDIT BOOK DETAILS'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Enter new title
      final titleField = find.widgetWithText(TextField, 'Design Patterns');
      await tester.enterText(
        titleField,
        'Design Patterns: Elements of Reusable OO Software',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Check in-memory DB got updated
      final updatedDbBook = await dbService.getBookById(sampleBook.id);
      expect(
        updatedDbBook!.title,
        'Design Patterns: Elements of Reusable OO Software',
      );
    });

    testWidgets('LibraryScreen renders desktop sidebar and toggles view mode', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);
      addTearDown(() => db.close());

      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseServiceProvider.overrideWithValue(dbService),
            allBooksStreamProvider.overrideWith(
              (ref) => Stream.value([sampleBook]),
            ),
            recentlyAddedStreamProvider.overrideWith(
              (ref) => Stream.value([sampleBook]),
            ),
            currentlyReadingStreamProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            finishedBooksStreamProvider.overrideWith((ref) => Stream.value([])),
            collectionsStreamProvider.overrideWith((ref) => Stream.value([])),
            collectionBookCountsStreamProvider.overrideWith(
              (ref) => Stream.value({}),
            ),
            allBookmarksStreamProvider.overrideWith((ref) => Stream.value([])),
            allHighlightsStreamProvider.overrideWith((ref) => Stream.value([])),
            searchBooksStreamProvider.overrideWith((ref) => Stream.value([])),
            bookProgressStreamProvider(
              sampleBook.id,
            ).overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Sidebar items exist with consistent Indonesian terminology
      expect(find.text(AppStrings.categoryPustaka), findsOneWidget);
      expect(find.text(AppStrings.categoryKoleksi), findsOneWidget);
      expect(find.text(AppStrings.categoryCatatan), findsOneWidget);
      expect(find.text(AppStrings.navSedangDibaca), findsWidgets);
      expect(find.text(AppStrings.navSemuaBuku), findsOneWidget);
      expect(find.text(AppStrings.navPenanda), findsOneWidget);
      expect(find.text(AppStrings.navSorotanCatatan), findsOneWidget);

      // Navigate to 'Semua Buku' where grid and list controls are placed
      await tester.tap(find.text(AppStrings.navSemuaBuku));
      await tester.pumpAndSettle();

      // View mode buttons exist (Grid and List)
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);

      // Initially in Grid Mode, BookCard is displayed
      expect(find.byType(BookCard), findsWidgets);

      // Switch to List View Mode
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      // BookListTile is now rendered!
      expect(find.byType(BookListTile), findsWidgets);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
