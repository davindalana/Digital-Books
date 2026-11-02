import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/utils/file_storage_service.dart';
import '../../../processing/models/processing_status.dart';
import '../../../processing/providers/import_provider.dart';
import '../../../processing/services/pdf_processing_pipeline.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/providers/reader_settings_provider.dart';

enum _DuplicatePromptAction { openExisting, importAnyway, cancel }

class ImportPdfHelper {
  static Future<void> pickAndImportPdf(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isEmpty) {
        return;
      }

      final platformFile = files.first;
      File selectedFile;

      try {
        if (platformFile.path != null) {
          final testFile = File(platformFile.path!);
          await testFile.length();
          selectedFile = testFile;
        } else {
          throw Exception('No path');
        }
      } catch (_) {
        // Fallback: Read bytes via security-scoped PlatformFile
        final bytes = await platformFile.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(p.join(tempDir.path, platformFile.name));
        await tempFile.writeAsBytes(bytes);
        selectedFile = tempFile;
      }

      if (!context.mounted) return;

      // Duplicate Check: 1. SHA-256 Exact Check, 2. Title/Author Edition Check
      final fileHash = await FileStorageService.computeFileSha256(selectedFile);
      final exactMatch = await ref
          .read(databaseServiceProvider)
          .findBookByFileHash(fileHash);

      if (exactMatch != null && context.mounted) {
        final action = await showDialog<_DuplicatePromptAction>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withAlpha(25)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Exact File Already in Library',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'An identical file of "${exactMatch.title}" is already in your library (matching SHA-256 checksum).\n\nWould you like to open the existing book, import a duplicate copy, or cancel?',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white70,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicatePromptAction.cancel),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withAlpha(40)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicatePromptAction.importAnyway),
                child: const Text(
                  'Import Duplicate Copy',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicatePromptAction.openExisting),
                child: const Text('Open Existing Book'),
              ),
            ],
          ),
        );

        if (action == null || action == _DuplicatePromptAction.cancel) {
          return;
        }
        if (action == _DuplicatePromptAction.openExisting) {
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReadingScreen(
                  book: exactMatch,
                  initialMode: exactMatch.isScanned
                      ? ReadingMode.originalPdf
                      : ReadingMode.reflowable,
                ),
              ),
            );
          }
          return;
        }
      } else {
        // 2. Different Edition / Title & Author Match Check
        final peek = await PdfProcessingPipeline.peekPdfMetadata(selectedFile);
        final editionMatch = await ref
            .read(databaseServiceProvider)
            .findDuplicateBook(title: peek.title, author: peek.author);

        if (editionMatch != null && context.mounted) {
          final action = await showDialog<_DuplicatePromptAction>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withAlpha(25)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_stories_rounded,
                      color: Color(0xFF007AFF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Different Edition Detected',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'A book with the title "${editionMatch.title}" by ${editionMatch.author} is already in your library, but this file has different contents.\n\nWould you like to import this as a new edition, or open your existing copy?',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.white70,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(_DuplicatePromptAction.cancel),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withAlpha(40)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(
                    ctx,
                  ).pop(_DuplicatePromptAction.importAnyway),
                  child: const Text(
                    'Import as New Edition',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(
                    ctx,
                  ).pop(_DuplicatePromptAction.openExisting),
                  child: const Text('Open Existing Book'),
                ),
              ],
            ),
          );

          if (action == null || action == _DuplicatePromptAction.cancel) {
            return;
          }
          if (action == _DuplicatePromptAction.openExisting) {
            if (context.mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReadingScreen(
                    book: editionMatch,
                    initialMode: editionMatch.isScanned
                        ? ReadingMode.originalPdf
                        : ReadingMode.reflowable,
                  ),
                ),
              );
            }
            return;
          }
        }
      }

      if (!context.mounted) return;

      // Show Import Progress Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ImportProgressDialog(),
      );

      // Start import pipeline
      final importedBook = await ref
          .read(importNotifierProvider.notifier)
          .importFile(selectedFile);

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Cleanly close progress dialog

        if (importedBook != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReadingScreen(
                    book: importedBook,
                    initialMode: importedBook.isScanned
                        ? ReadingMode.originalPdf
                        : ReadingMode.reflowable,
                  ),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}

class ImportProgressDialog extends ConsumerWidget {
  const ImportProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(importNotifierProvider);
    final progress = importState.progress;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E1E22).withAlpha(240)
                  : const Color(0xFFF9F9FB).withAlpha(245),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_stories,
                      color: Color(0xFF007AFF),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  progress.stage.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  progress.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 24),

                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.stage == ProcessingStage.failed
                        ? 0.0
                        : progress.progress.clamp(0.05, 1.0),
                    backgroundColor: Colors.grey.withAlpha(50),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress.stage == ProcessingStage.failed
                          ? Colors.redAccent
                          : const Color(0xFF007AFF),
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  '${(progress.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 16),

                if (importState.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      importState.errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (importState.isProcessing) {
                          ref.read(importNotifierProvider.notifier).cancel();
                        }
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        importState.isProcessing ? 'Cancel' : 'Close',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
