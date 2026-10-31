// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/corpus_pdf_generator.dart';

void main() {
  test('Generate 10-category representative PDF test corpus', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final corpusDir = Directory('test/fixtures/corpus');
    await CorpusPdfGenerator.generateAllCorpusFiles(corpusDir);

    final generatedFiles = corpusDir.listSync().whereType<File>().toList();
    expect(generatedFiles.length, equals(10));
    for (final f in generatedFiles) {
      expect(await f.length(), greaterThan(500));
      print('Generated: ${f.path} (${await f.length()} bytes)');
    }
  });
}
