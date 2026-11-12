import 'package:digital_books/core/constants/app_strings.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/main.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DigitalBooksApp renders library home screen', (
    WidgetTester tester,
  ) async {
    final inMemoryDb = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(inMemoryDb)],
        child: const DigitalBooksApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify presence of Books header and Sedang Dibaca section
    expect(find.text(AppStrings.appNameShort), findsOneWidget);
    expect(find.text(AppStrings.navSedangDibaca), findsWidgets);

    await inMemoryDb.close();
  });
}
