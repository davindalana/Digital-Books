import 'dart:io';

import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/services/book_document_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('book_document_loader_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  BookDocument sampleDocument() => const BookDocument(
    id: 'loader-book',
    title: 'Loader Book',
    author: 'Tester',
    totalPages: 2,
    chapters: [
      BookChapter(
        id: 'chapter-1',
        index: 0,
        title: 'Bab 1',
        blocks: [
          BookBlock(
            id: 'block-1',
            type: BlockType.paragraph,
            text: 'Isi bacaan.',
          ),
        ],
      ),
    ],
    metadata: {
      'reconstructionQuality': {'status': 'good'},
    },
  );

  test('loads and normalises a valid processed document', () async {
    final file = File(p.join(tempDir.path, 'valid.json'));
    await file.writeAsString(sampleDocument().toJsonString());

    final result = await BookDocumentLoader.load(file.path);

    expect(result.isSuccess, isTrue);
    expect(result.error, isNull);
    expect(result.document!.title, 'Loader Book');
    expect(result.readerDocument!.chapters, isNotEmpty);
  });

  test('missing processed file returns an explicit error', () async {
    final result = await BookDocumentLoader.load(
      p.join(tempDir.path, 'missing.json'),
    );

    expect(result.isSuccess, isFalse);
    expect(result.document, isNull);
    expect(result.error, contains('empty or missing'));
  });

  test('corrupt processed file returns an explicit error', () async {
    final file = File(p.join(tempDir.path, 'corrupt.json'));
    await file.writeAsString('{not valid json');

    final result = await BookDocumentLoader.load(file.path);

    expect(result.isSuccess, isFalse);
    expect(result.document, isNull);
    expect(result.error, contains('could not be loaded'));
  });

  test(
    'null path is reported as unavailable instead of silently passing',
    () async {
      final result = await BookDocumentLoader.load(null);

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('not available'));
    },
  );
}
