import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';
import '../database/database_service.dart';

enum RestoreConflictPolicy {
  /// Keep existing books and reading progress; add new books and merge non-duplicate annotations
  skipExisting,

  /// Update metadata of existing books; update progress only if backup is newer; merge annotations
  mergeUpdateExisting,
}

class FullBackupResult {
  final Directory bundleDirectory;
  final File manifestFile;
  final int copiedPdfsCount;
  final int totalBytes;

  const FullBackupResult({
    required this.bundleDirectory,
    required this.manifestFile,
    required this.copiedPdfsCount,
    required this.totalBytes,
  });
}

class RestorePreview {
  final int totalBooks;
  final int newBooks;
  final int existingBooks;
  final int totalBookmarks;
  final int totalHighlights;
  final int totalCollections;
  final DateTime exportedAt;
  final String appVersion;
  final List<String> bookTitles;

  const RestorePreview({
    required this.totalBooks,
    required this.newBooks,
    required this.existingBooks,
    required this.totalBookmarks,
    required this.totalHighlights,
    required this.totalCollections,
    required this.exportedAt,
    required this.appVersion,
    required this.bookTitles,
  });
}

class RestoreResult {
  final int booksRestored;
  final int booksUpdated;
  final int booksSkipped;
  final int bookmarksRestored;
  final int highlightsRestored;
  final int collectionsRestored;
  final Map<String, dynamic>? preferencesRestored;

  const RestoreResult({
    required this.booksRestored,
    required this.booksUpdated,
    required this.booksSkipped,
    required this.bookmarksRestored,
    required this.highlightsRestored,
    required this.collectionsRestored,
    this.preferencesRestored,
  });
}

class BackupRestoreService {
  static const String currentBackupVersion = '1.0';
  static const String defaultAppVersion = '1.0.0';

  /// Generates a comprehensive JSON backup string of the database
  static Future<String> generateBackupJson({
    required DatabaseService dbService,
    Map<String, dynamic>? preferences,
  }) async {
    final books = await dbService.getAllBooks();
    final collections = await dbService.getAllCollections();
    final allBookCollections = await dbService.getAllBookCollections();

    final booksData = <Map<String, dynamic>>[];

    for (final book in books) {
      final chapters = await dbService.getChaptersForBook(book.id);
      final progress = await dbService.getProgress(book.id);
      final bookmarks = await dbService.getBookmarksForBook(book.id);
      final highlights = await dbService.getHighlightsForBook(book.id);

      final bookCollectionIds = allBookCollections
          .where((bc) => bc.bookId == book.id)
          .map((bc) => bc.collectionId)
          .toList();

      booksData.add({
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'publisher': book.publisher,
        'description': book.description,
        'coverPath': book.coverPath,
        'originalPdfPath': book.originalPdfPath,
        'processedBookPath': book.processedBookPath,
        'fileHash': book.fileHash,
        'totalPages': book.totalPages,
        'isScanned': book.isScanned,
        'createdAt': book.createdAt.toIso8601String(),
        'updatedAt': book.updatedAt.toIso8601String(),
        'collectionIds': bookCollectionIds,
        'chapters': chapters
            .map(
              (c) => {
                'id': c.id,
                'title': c.title,
                'chapterIndex': c.chapterIndex,
                'startPosition': c.startPosition,
                'endPosition': c.endPosition,
              },
            )
            .toList(),
        'readingProgress': progress != null
            ? {
                'currentChapter': progress.currentChapter,
                'currentPosition': progress.currentPosition,
                'progressPercentage': progress.progressPercentage,
                'lastReadingMode': progress.lastReadingMode,
                'lastReadAt': progress.lastReadAt.toIso8601String(),
              }
            : null,
        'bookmarks': bookmarks
            .map(
              (b) => {
                'id': b.id,
                'chapterId': b.chapterId,
                'position': b.position,
                'label': b.label,
                'anchorNodeId': b.anchorNodeId,
                'characterOffset': b.characterOffset,
                'progressPercentage': b.progressPercentage,
                'createdAt': b.createdAt.toIso8601String(),
              },
            )
            .toList(),
        'highlights': highlights
            .map(
              (h) => {
                'id': h.id,
                'chapterId': h.chapterId,
                'selectedText': h.selectedText,
                'startPosition': h.startPosition,
                'endPosition': h.endPosition,
                'color': h.color,
                'note': h.note,
                'anchorNodeId': h.anchorNodeId,
                'startOffset': h.startOffset,
                'endOffset': h.endOffset,
                'prefixContext': h.prefixContext,
                'suffixContext': h.suffixContext,
                'anchorVersion': h.anchorVersion,
                'createdAt': h.createdAt.toIso8601String(),
              },
            )
            .toList(),
      });
    }

    final backupPayload = {
      'metadata': {
        'formatVersion': currentBackupVersion,
        'appVersion': defaultAppVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'type': 'digital_books_metadata_backup',
        'databaseOnly': true,
        'note':
            'This backup includes library metadata, reading progress, collections, bookmarks, and highlights. Original book PDFs should be kept in your storage.',
      },
      'preferences': preferences ?? {},
      'collections': collections
          .map(
            (c) => {
              'id': c.id,
              'name': c.name,
              'description': c.description,
              'createdAt': c.createdAt.toIso8601String(),
            },
          )
          .toList(),
      'books': booksData,
    };

    return const JsonEncoder.withIndent('  ').convert(backupPayload);
  }

  /// Exports backup to a default or specified file location
  static Future<File> exportBackupToFile({
    required DatabaseService dbService,
    String? customFilePath,
    Map<String, dynamic>? preferences,
  }) async {
    final jsonString = await generateBackupJson(
      dbService: dbService,
      preferences: preferences,
    );

    final targetPath = customFilePath ?? await _generateDefaultBackupPath();
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    return file.writeAsString(jsonString);
  }

  static Future<String> _generateDefaultBackupPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return p.join(
      docsDir.path,
      'DigitalBooks',
      'backups',
      'digital_books_backup_$timestamp.json',
    );
  }

  /// Exports a Full Library Bundle: copies metadata manifest.json and all original PDF files
  /// into an organized, self-contained backup folder.
  static Future<FullBackupResult> exportFullLibraryBundle({
    required DatabaseService dbService,
    required String targetDirectoryPath,
    Map<String, dynamic>? preferences,
  }) async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final bundleDir = Directory(
      p.join(targetDirectoryPath, 'DigitalBooks_Full_Backup_$timestamp'),
    );
    await bundleDir.create(recursive: true);

    // 1. Generate and save manifest.json
    final jsonString = await generateBackupJson(
      dbService: dbService,
      preferences: preferences,
    );
    final manifestFile = File(p.join(bundleDir.path, 'manifest.json'));
    await manifestFile.writeAsString(jsonString);

    // 2. Copy original PDFs to originals/ folder
    final originalsDir = Directory(p.join(bundleDir.path, 'originals'));
    await originalsDir.create(recursive: true);

    final allBooks = await dbService.getAllBooks();
    int copiedPdfs = 0;
    int totalBytes = manifestFile.lengthSync();

    for (final book in allBooks) {
      final srcFile = File(book.originalPdfPath);
      if (await srcFile.exists()) {
        final ext = p.extension(srcFile.path).isEmpty
            ? '.pdf'
            : p.extension(srcFile.path);
        final dest = File(p.join(originalsDir.path, '${book.id}$ext'));
        await srcFile.copy(dest.path);
        copiedPdfs++;
        totalBytes += await dest.length();
      }
    }

    return FullBackupResult(
      bundleDirectory: bundleDir,
      manifestFile: manifestFile,
      copiedPdfsCount: copiedPdfs,
      totalBytes: totalBytes,
    );
  }

  /// Validates the integrity and schema version of the backup data
  static void validateBackupData(Map<String, dynamic> data) {
    if (!data.containsKey('metadata') ||
        data['metadata'] is! Map<String, dynamic>) {
      throw const FormatException(
        'Corrupted backup file: missing or invalid "metadata" header.',
      );
    }
    final metadata = data['metadata'] as Map<String, dynamic>;
    final formatVersion = metadata['formatVersion'] as String?;
    if (formatVersion == null || formatVersion != currentBackupVersion) {
      throw FormatException(
        'Unsupported backup format version: "${formatVersion ?? "unknown"}". '
        'This version of Digital Books supports format version "$currentBackupVersion".',
      );
    }
    if (!data.containsKey('books') || data['books'] is! List) {
      throw const FormatException(
        'Corrupted backup file: missing or invalid "books" array.',
      );
    }
  }

  /// Parses and inspects backup JSON without modifying any database records
  static Future<RestorePreview> previewBackup(
    String backupJson, {
    required DatabaseService dbService,
  }) async {
    final dynamic rawDecoded = jsonDecode(backupJson);
    if (rawDecoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid backup: Root JSON is not an object.',
      );
    }
    validateBackupData(rawDecoded);
    final data = rawDecoded;

    final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
    final exportedAtStr = metadata['exportedAt'] as String?;
    final exportedAt = exportedAtStr != null
        ? DateTime.tryParse(exportedAtStr) ?? DateTime.now()
        : DateTime.now();
    final appVersion = (metadata['appVersion'] as String?) ?? 'Unknown';

    final rawCollections = (data['collections'] as List?) ?? [];
    final rawBooks = (data['books'] as List?) ?? [];

    int totalBookmarks = 0;
    int totalHighlights = 0;
    final bookTitles = <String>[];

    final existingBooks = await dbService.getAllBooks();
    final existingIds = existingBooks.map((b) => b.id).toSet();
    final existingHashes = existingBooks
        .where((b) => b.fileHash != null)
        .map((b) => b.fileHash!)
        .toSet();

    int existingCount = 0;
    int newCount = 0;

    for (final raw in rawBooks) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'] as String? ?? '';
      final title = raw['title'] as String? ?? 'Untitled';
      final fileHash = raw['fileHash'] as String?;
      bookTitles.add(title);

      final isExisting =
          existingIds.contains(id) ||
          (fileHash != null && existingHashes.contains(fileHash));

      if (isExisting) {
        existingCount++;
      } else {
        newCount++;
      }

      final bms = (raw['bookmarks'] as List?) ?? [];
      final hls = (raw['highlights'] as List?) ?? [];
      totalBookmarks += bms.length;
      totalHighlights += hls.length;
    }

    return RestorePreview(
      totalBooks: rawBooks.length,
      newBooks: newCount,
      existingBooks: existingCount,
      totalBookmarks: totalBookmarks,
      totalHighlights: totalHighlights,
      totalCollections: rawCollections.length,
      exportedAt: exportedAt,
      appVersion: appVersion,
      bookTitles: bookTitles,
    );
  }

  /// Executes restoration safely within a database transaction
  static Future<RestoreResult> executeRestore({
    required String backupJson,
    required DatabaseService dbService,
    RestoreConflictPolicy policy = RestoreConflictPolicy.skipExisting,
  }) async {
    final dynamic rawDecoded = jsonDecode(backupJson);
    if (rawDecoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid backup: Root JSON is not an object.',
      );
    }
    validateBackupData(rawDecoded);
    final data = rawDecoded;

    final rawCollections = (data['collections'] as List?) ?? [];
    final rawBooks = (data['books'] as List?) ?? [];
    final preferences = data['preferences'] as Map<String, dynamic>?;

    int booksRestored = 0;
    int booksUpdated = 0;
    int booksSkipped = 0;
    int bookmarksRestored = 0;
    int highlightsRestored = 0;
    int collectionsRestored = 0;

    await dbService.db.transaction(() async {
      // 1. Restore Collections
      final existingCollections = await dbService.getAllCollections();
      final existingCollectionIds = existingCollections
          .map((c) => c.id)
          .toSet();

      for (final raw in rawCollections) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'] as String;
        final name = raw['name'] as String;
        final description = raw['description'] as String?;
        final createdAtStr = raw['createdAt'] as String?;
        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
            : DateTime.now();

        if (!existingCollectionIds.contains(id)) {
          await dbService.createCollection(
            CollectionsCompanion(
              id: drift.Value(id),
              name: drift.Value(name),
              description: drift.Value(description),
              createdAt: drift.Value(createdAt),
            ),
          );
          collectionsRestored++;
        }
      }

      // 2. Restore Books & Subordinate Data
      for (final raw in rawBooks) {
        if (raw is! Map<String, dynamic>) continue;
        final bookId = raw['id'] as String;
        final title = raw['title'] as String? ?? 'Untitled';
        final author = raw['author'] as String? ?? 'Unknown';
        final publisher = raw['publisher'] as String?;
        final description = raw['description'] as String?;
        final coverPath = raw['coverPath'] as String?;
        final originalPdfPath = raw['originalPdfPath'] as String? ?? '';
        final processedBookPath = raw['processedBookPath'] as String?;
        final fileHash = raw['fileHash'] as String?;
        final totalPages = (raw['totalPages'] as num?)?.toInt() ?? 0;
        final isScanned = raw['isScanned'] as bool? ?? false;
        final createdAtStr = raw['createdAt'] as String?;
        final updatedAtStr = raw['updatedAt'] as String?;

        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
            : DateTime.now();
        final updatedAt = updatedAtStr != null
            ? DateTime.tryParse(updatedAtStr) ?? DateTime.now()
            : DateTime.now();

        final existingBook = await dbService.getBookById(bookId);

        if (existingBook != null) {
          if (policy == RestoreConflictPolicy.skipExisting) {
            booksSkipped++;
          } else {
            // mergeUpdateExisting
            await (dbService.db.update(
              dbService.db.books,
            )..where((t) => t.id.equals(bookId))).write(
              BooksCompanion(
                title: drift.Value(title),
                author: drift.Value(author),
                publisher: drift.Value(publisher),
                description: drift.Value(description),
                updatedAt: drift.Value(DateTime.now()),
              ),
            );
            booksUpdated++;
          }
        } else {
          // Newly restored book
          await dbService.insertBook(
            BooksCompanion(
              id: drift.Value(bookId),
              title: drift.Value(title),
              author: drift.Value(author),
              publisher: drift.Value(publisher),
              description: drift.Value(description),
              coverPath: drift.Value(coverPath),
              originalPdfPath: drift.Value(originalPdfPath),
              processedBookPath: drift.Value(processedBookPath),
              fileHash: drift.Value(fileHash),
              totalPages: drift.Value(totalPages),
              isScanned: drift.Value(isScanned),
              createdAt: drift.Value(createdAt),
              updatedAt: drift.Value(updatedAt),
            ),
          );
          booksRestored++;
        }

        // Chapters
        final rawChapters = (raw['chapters'] as List?) ?? [];
        if (existingBook == null && rawChapters.isNotEmpty) {
          final chapters = rawChapters.map((c) {
            final cMap = c as Map<String, dynamic>;
            return ChaptersCompanion(
              id: drift.Value(cMap['id'] as String),
              bookId: drift.Value(bookId),
              title: drift.Value(cMap['title'] as String),
              chapterIndex: drift.Value((cMap['chapterIndex'] as num).toInt()),
              startPosition: drift.Value(
                (cMap['startPosition'] as num?)?.toInt() ?? 0,
              ),
              endPosition: drift.Value(
                (cMap['endPosition'] as num?)?.toInt() ?? 0,
              ),
            );
          }).toList();
          await dbService.replaceChaptersForBook(bookId, chapters);
        }

        // Reading Progress: Safely merge based on timestamp comparison
        final rawProgress = raw['readingProgress'] as Map<String, dynamic>?;
        if (rawProgress != null) {
          final currentProg = await dbService.getProgress(bookId);
          final lastReadAtStr = rawProgress['lastReadAt'] as String?;
          final lastReadAt = lastReadAtStr != null
              ? DateTime.tryParse(lastReadAtStr) ?? DateTime.now()
              : DateTime.now();

          // Only update reading progress if no local progress exists,
          // or if mergeUpdateExisting is selected AND the backup progress is strictly newer
          final shouldUpdateProgress =
              currentProg == null ||
              (policy == RestoreConflictPolicy.mergeUpdateExisting &&
                  lastReadAt.isAfter(currentProg.lastReadAt));

          if (shouldUpdateProgress) {
            await dbService.upsertProgress(
              ReadingProgressesCompanion(
                id: drift.Value(currentProg?.id ?? 'prog_$bookId'),
                bookId: drift.Value(bookId),
                currentChapter: drift.Value(
                  (rawProgress['currentChapter'] as num?)?.toInt() ?? 0,
                ),
                currentPosition: drift.Value(
                  (rawProgress['currentPosition'] as num?)?.toInt() ?? 0,
                ),
                progressPercentage: drift.Value(
                  (rawProgress['progressPercentage'] as num?)?.toDouble() ??
                      0.0,
                ),
                lastReadingMode: drift.Value(
                  rawProgress['lastReadingMode'] as String?,
                ),
                lastReadAt: drift.Value(lastReadAt),
              ),
            );
          }
        }

        // Bookmarks
        final existingBookmarks = await dbService.getBookmarksForBook(bookId);
        final existingBmPositions = existingBookmarks
            .map((b) => '${b.position}_${b.anchorNodeId}')
            .toSet();

        final rawBookmarks = (raw['bookmarks'] as List?) ?? [];
        for (final b in rawBookmarks) {
          if (b is! Map<String, dynamic>) continue;
          final pos = (b['position'] as num).toInt();
          final anchorNodeId = b['anchorNodeId'] as String?;
          final key = '${pos}_$anchorNodeId';

          if (!existingBmPositions.contains(key)) {
            final bmId = b['id'] as String;
            final label = b['label'] as String? ?? 'Bookmark';
            final charOffset = (b['characterOffset'] as num?)?.toInt() ?? 0;
            final pct = (b['progressPercentage'] as num?)?.toDouble() ?? 0.0;
            final createdAtStr = b['createdAt'] as String?;
            final createdAt = createdAtStr != null
                ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
                : DateTime.now();

            await dbService.addBookmark(
              BookmarksCompanion(
                id: drift.Value(bmId),
                bookId: drift.Value(bookId),
                chapterId: drift.Value(b['chapterId'] as String?),
                position: drift.Value(pos),
                label: drift.Value(label),
                anchorNodeId: drift.Value(anchorNodeId),
                characterOffset: drift.Value(charOffset),
                progressPercentage: drift.Value(pct),
                createdAt: drift.Value(createdAt),
              ),
            );
            bookmarksRestored++;
            existingBmPositions.add(key);
          }
        }

        // Highlights & Notes
        final existingHighlights = await dbService.getHighlightsForBook(bookId);
        final existingHlKeys = existingHighlights
            .map((h) => '${h.anchorNodeId}_${h.startOffset}_${h.selectedText}')
            .toSet();

        final rawHighlights = (raw['highlights'] as List?) ?? [];
        for (final h in rawHighlights) {
          if (h is! Map<String, dynamic>) continue;
          final anchorNodeId = h['anchorNodeId'] as String?;
          final startOffset = (h['startOffset'] as num?)?.toInt() ?? 0;
          final selectedText = h['selectedText'] as String? ?? '';
          final key = '${anchorNodeId}_${startOffset}_$selectedText';

          if (!existingHlKeys.contains(key)) {
            final hlId = h['id'] as String;
            final startPos = (h['startPosition'] as num?)?.toInt() ?? 0;
            final endPos = (h['endPosition'] as num?)?.toInt() ?? 0;
            final endOffset = (h['endOffset'] as num?)?.toInt() ?? 0;
            final color = h['color'] as String? ?? 'yellow';
            final note = h['note'] as String?;
            final prefixContext = h['prefixContext'] as String?;
            final suffixContext = h['suffixContext'] as String?;
            final anchorVersion = (h['anchorVersion'] as num?)?.toInt() ?? 1;
            final createdAtStr = h['createdAt'] as String?;
            final createdAt = createdAtStr != null
                ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
                : DateTime.now();

            await dbService.addHighlight(
              HighlightsCompanion(
                id: drift.Value(hlId),
                bookId: drift.Value(bookId),
                chapterId: drift.Value(h['chapterId'] as String?),
                selectedText: drift.Value(selectedText),
                startPosition: drift.Value(startPos),
                endPosition: drift.Value(endPos),
                color: drift.Value(color),
                note: drift.Value(note),
                anchorNodeId: drift.Value(anchorNodeId),
                startOffset: drift.Value(startOffset),
                endOffset: drift.Value(endOffset),
                prefixContext: drift.Value(prefixContext),
                suffixContext: drift.Value(suffixContext),
                anchorVersion: drift.Value(anchorVersion),
                createdAt: drift.Value(createdAt),
              ),
            );
            highlightsRestored++;
            existingHlKeys.add(key);
          }
        }

        // Collection Associations
        final rawCollectionIds = (raw['collectionIds'] as List?) ?? [];
        for (final colId in rawCollectionIds) {
          if (colId is String) {
            try {
              await dbService.addBookToCollection(bookId, colId);
            } catch (_) {}
          }
        }
      }
    });

    return RestoreResult(
      booksRestored: booksRestored,
      booksUpdated: booksUpdated,
      booksSkipped: booksSkipped,
      bookmarksRestored: bookmarksRestored,
      highlightsRestored: highlightsRestored,
      collectionsRestored: collectionsRestored,
      preferencesRestored: preferences,
    );
  }
}
