import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/library/presentation/widgets/import_pdf_dialog.dart';
import 'package:digital_books/features/processing/models/processing_status.dart';
import 'package:digital_books/features/processing/providers/import_provider.dart';
import 'package:digital_books/features/processing/services/pdf_processing_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProcessingImportNotifier extends ImportNotifier {
  _ProcessingImportNotifier(super.pipeline);

  void markProcessing() {
    state = const ImportState(
      isProcessing: true,
      progress: ProcessingProgress(
        stage: ProcessingStage.extractingText,
        progress: 0.4,
        message: 'Extracting text...',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cancelling closes only the progress dialog, not the screen', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final notifier = _ProcessingImportNotifier(
      PdfProcessingPipeline(DatabaseService(db)),
    );
    notifier.markProcessing();
    var cancelled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [importNotifierProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) =>
                        ImportProgressDialog(onCancel: () => cancelled = true),
                  );
                },
                child: const Text('Open import dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportProgressDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(find.byType(ImportProgressDialog), findsNothing);
    expect(
      find.text('Open import dialog'),
      findsOneWidget,
      reason: 'Cancelling must not pop the underlying library screen.',
    );
  });
}
