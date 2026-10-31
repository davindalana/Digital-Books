import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileStorageService {
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
    final ext = p.extension(sourcePdf.path).isEmpty ? '.pdf' : p.extension(sourcePdf.path);
    final targetPath = p.join(originalsDir.path, '$bookId$ext');
    return sourcePdf.copy(targetPath);
  }

  static Future<File> saveProcessedBook(String bookId, String jsonContent) async {
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

