import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/library/presentation/screens/library_screen.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    try {
      File('/tmp/flutter_crash.log').writeAsStringSync(
        '=== FLUTTER ERROR ===\n${details.exceptionAsString()}\nSTACK:\n${details.stack}\n\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      File('/tmp/flutter_crash.log').writeAsStringSync(
        '=== ASYNC ERROR ===\n$error\nSTACK:\n$stack\n\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    return true;
  };

  final initialSection =
      args.contains('--semua-buku') ||
          Platform.environment['DIGITAL_BOOKS_SECTION'] == 'allBooks'
      ? LibraryNavigationSection.allBooks
      : LibraryNavigationSection.home;

  runApp(ProviderScope(child: DigitalBooksApp(initialSection: initialSection)));
}

class DigitalBooksApp extends StatelessWidget {
  final LibraryNavigationSection initialSection;
  const DigitalBooksApp({
    super.key,
    this.initialSection = LibraryNavigationSection.home,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Books',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Default to Apple Books Dark experience
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF2F2F7),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(
          0xFF000000,
        ), // Apple Books OLED black background
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF1C1C1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: LibraryScreen(initialSection: initialSection),
    );
  }
}
