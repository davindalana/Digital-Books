import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../processing/models/processing_status.dart';
import '../../../processing/providers/import_provider.dart';
import '../../../reader/presentation/screens/reading_screen.dart';

class ImportPdfHelper {
  static Future<void> pickAndImportPdf(BuildContext context, WidgetRef ref) async {
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
        Navigator.of(context).pop(); // Close import dialog

        if (importedBook != null) {
          // Open Reading Screen immediately
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReadingScreen(book: importedBook),
            ),
          );
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
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
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
                        style: TextStyle(
                          color: Colors.grey.shade400,
                        ),
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
