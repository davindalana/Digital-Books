import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/database_service.dart';

class OrphanScanResult {
  final List<File> orphanedFiles;
  final int totalBytes;

  const OrphanScanResult({
    required this.orphanedFiles,
    required this.totalBytes,
  });

  int get count => orphanedFiles.length;
}

class FileStorageService {
  static final Set<String> _lockedPaths = {};

  static void lockPath(String path) {
    _lockedPaths.add(p.canonicalize(path));
  }

  static void unlockPath(String path) {
    _lockedPaths.remove(p.canonicalize(path));
  }

  static Future<Directory> getAppBaseDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docsDir.path, 'DigitalBooks'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  static Future<Directory> getOriginalsDirectory() async {
    final base = await getAppBaseDirectory();
    final dir = Directory(p.join(base.path, 'originals'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> getBooksDirectory() async {
    final base = await getAppBaseDirectory();
    final dir = Directory(p.join(base.path, 'books'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> getCoversDirectory() async {
    final base = await getAppBaseDirectory();
    final dir = Directory(p.join(base.path, 'covers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> getImagesDirectory() async {
    final base = await getAppBaseDirectory();
    final dir = Directory(p.join(base.path, 'images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> copyPdfToStorage(File sourcePdf, String bookId) async {
    final originalsDir = await getOriginalsDirectory();
    final ext = p.extension(sourcePdf.path).isEmpty
        ? '.pdf'
        : p.extension(sourcePdf.path);
    final targetPath = p.join(originalsDir.path, '$bookId$ext');
    return sourcePdf.copy(targetPath);
  }

  static Future<File> saveProcessedBook(
    String bookId,
    String jsonContent,
  ) async {
    final booksDir = await getBooksDirectory();
    final targetPath = p.join(booksDir.path, '$bookId.json');
    final file = File(targetPath);
    return file.writeAsString(jsonContent);
  }

  static Future<String?> readProcessedBook(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
    return null;
  }

  static Future<String> computeFileSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  static Future<void> deleteBookFilesSafe({
    required DatabaseService dbService,
    required String bookId,
    required String? originalPdfPath,
    required String? processedBookPath,
    required String? coverPath,
  }) async {
    try {
      if (originalPdfPath != null && await File(originalPdfPath).exists()) {
        final isShared = await dbService.isPathReferencedByOtherBook(
          originalPdfPath,
          excludeBookId: bookId,
        );
        if (!isShared) {
          await File(originalPdfPath).delete();
        }
      }
      if (processedBookPath != null && await File(processedBookPath).exists()) {
        final isShared = await dbService.isPathReferencedByOtherBook(
          processedBookPath,
          excludeBookId: bookId,
        );
        if (!isShared) {
          await File(processedBookPath).delete();
        }
      }
      if (coverPath != null && await File(coverPath).exists()) {
        final isShared = await dbService.isPathReferencedByOtherBook(
          coverPath,
          excludeBookId: bookId,
        );
        if (!isShared) {
          await File(coverPath).delete();
        }
      }
      final imagesDir = await getImagesDirectory();
      final bookImages = Directory(p.join(imagesDir.path, bookId));
      if (await bookImages.exists()) {
        await bookImages.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<List<File>> detectOrphanFiles(DatabaseService dbService) async {
    final allBooks = await dbService.getAllBooks();
    final activeOriginals = allBooks
        .map((b) => p.canonicalize(b.originalPdfPath))
        .toSet();
    final activeCovers = allBooks
        .where((b) => b.coverPath != null)
        .map((b) => p.canonicalize(b.coverPath!))
        .toSet();
    final activeBooks = allBooks
        .where((b) => b.processedBookPath != null)
        .map((b) => p.canonicalize(b.processedBookPath!))
        .toSet();

    final List<File> orphans = [];
    final now = DateTime.now();

    bool isSafeOrphan(File file) {
      final canon = p.canonicalize(file.path);
      // 1. Check if path is currently locked (in-progress import or reader)
      if (_lockedPaths.contains(canon)) return false;

      // 2. Protect recently created files (created/modified within last 30 seconds)
      try {
        final stat = file.statSync();
        if (now.difference(stat.modified).inSeconds < 30) return false;
      } catch (_) {}

      return true;
    }

    final originalsDir = await getOriginalsDirectory();
    if (await originalsDir.exists()) {
      await for (final entity in originalsDir.list(followLinks: false)) {
        if (entity is File &&
            !activeOriginals.contains(p.canonicalize(entity.path))) {
          if (isSafeOrphan(entity)) {
            orphans.add(entity);
          }
        }
      }
    }

    final coversDir = await getCoversDirectory();
    if (await coversDir.exists()) {
      await for (final entity in coversDir.list(followLinks: false)) {
        if (entity is File &&
            !activeCovers.contains(p.canonicalize(entity.path))) {
          if (isSafeOrphan(entity)) {
            orphans.add(entity);
          }
        }
      }
    }

    final booksDir = await getBooksDirectory();
    if (await booksDir.exists()) {
      await for (final entity in booksDir.list(followLinks: false)) {
        if (entity is File &&
            !activeBooks.contains(p.canonicalize(entity.path))) {
          if (isSafeOrphan(entity)) {
            orphans.add(entity);
          }
        }
      }
    }

    return orphans;
  }

  static Future<OrphanScanResult> scanOrphanFiles(
    DatabaseService dbService,
  ) async {
    final orphans = await detectOrphanFiles(dbService);
    int totalBytes = 0;
    for (final file in orphans) {
      try {
        if (await file.exists()) {
          totalBytes += await file.length();
        }
      } catch (_) {}
    }
    return OrphanScanResult(orphanedFiles: orphans, totalBytes: totalBytes);
  }

  static Future<int> detectAndCleanOrphanFiles(
    DatabaseService dbService, {
    bool dryRun = false,
  }) async {
    final orphans = await detectOrphanFiles(dbService);
    if (dryRun) {
      return orphans.length;
    }
    int cleaned = 0;
    for (final file in orphans) {
      try {
        if (await file.exists()) {
          await file.delete();
          cleaned++;
        }
      } catch (_) {}
    }
    return cleaned;
  }

  static Future<void> deleteBookFiles({
    String? bookId,
    required String? originalPdfPath,
    required String? processedBookPath,
    required String? coverPath,
  }) async {
    try {
      if (originalPdfPath != null && await File(originalPdfPath).exists()) {
        await File(originalPdfPath).delete();
      }
      if (processedBookPath != null && await File(processedBookPath).exists()) {
        await File(processedBookPath).delete();
      }
      if (coverPath != null && await File(coverPath).exists()) {
        await File(coverPath).delete();
      }
      if (bookId != null) {
        final imagesDir = await getImagesDirectory();
        final bookImages = Directory(p.join(imagesDir.path, bookId));
        if (await bookImages.exists()) {
          await bookImages.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}
