import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global test configuration hook executed before any test in test/ directory.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Strict offline guarantee: disallow any background runtime fetching
  GoogleFonts.config.allowRuntimeFetching = false;

  // Pre-load bundled fonts into Flutter FontLoader so headless WidgetTester
  // renders actual typographical glyphs rather than fallback Ahem blocks.
  final fontsToLoad = <String, String>{
    'Inter': 'assets/fonts/Inter-Regular.ttf',
    'Literata': 'assets/fonts/Literata-Regular.ttf',
    'Merriweather': 'assets/fonts/Merriweather-Regular.ttf',
    'NotoSerif': 'assets/fonts/NotoSerif-Regular.ttf',
  };

  for (final entry in fontsToLoad.entries) {
    final file = File(entry.value);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }

  await testMain();
}

