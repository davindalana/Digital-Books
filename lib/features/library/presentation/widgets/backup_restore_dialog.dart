import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/services/backup_restore_service.dart';
import '../../../reader/providers/reader_settings_provider.dart';

class BackupRestoreDialog extends ConsumerStatefulWidget {
  const BackupRestoreDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const BackupRestoreDialog(),
    );
  }

  @override
  ConsumerState<BackupRestoreDialog> createState() =>
      _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends ConsumerState<BackupRestoreDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _statusMessage;

  // Restore State
  String? _selectedBackupJson;
  String? _selectedBackupFileName;
  RestorePreview? _restorePreview;
  RestoreConflictPolicy _conflictPolicy = RestoreConflictPolicy.skipExisting;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Generating backup file...';
    });

    try {
      final dbService = ref.read(databaseServiceProvider);
      final activeTheme = ref.read(readingThemeStateProvider);
      final typography = ref.read(typographySettingsStateProvider);

      final preferences = {
        'defaultTheme': activeTheme.name,
        'fontFamily': typography.fontFamily.name,
        'twoPageSpread': typography.twoPageSpread,
      };

      final backupFile = await BackupRestoreService.exportBackupToFile(
        dbService: dbService,
        preferences: preferences,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Backup saved successfully to:\n${backupFile.path}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved: ${backupFile.path.split('/').last}'),
            backgroundColor: const Color(0xFF2C2C2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Export failed: $e';
        });
      }
    }
  }

  Future<void> _handleExportFullBundle() async {
    try {
      final selectedDir = await FilePicker.getDirectoryPath();
      if (selectedDir == null) return;

      setState(() {
        _isLoading = true;
        _statusMessage =
            'Copying PDFs and generating complete library bundle...';
      });

      final dbService = ref.read(databaseServiceProvider);
      final activeTheme = ref.read(readingThemeStateProvider);
      final typography = ref.read(typographySettingsStateProvider);

      final preferences = {
        'defaultTheme': activeTheme.name,
        'fontFamily': typography.fontFamily.name,
        'twoPageSpread': typography.twoPageSpread,
      };

      final result = await BackupRestoreService.exportFullLibraryBundle(
        dbService: dbService,
        targetDirectoryPath: selectedDir,
        preferences: preferences,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Full Library Bundle exported successfully!\nLocation:\n${result.bundleDirectory.path}\n• Copied ${result.copiedPdfsCount} book PDFs\n• Total size: ${(result.totalBytes / 1024.0 / 1024.0).toStringAsFixed(2)} MB';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Full Library Bundle saved (${result.copiedPdfsCount} PDFs copied)',
            ),
            backgroundColor: const Color(0xFF2C2C2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Bundle export failed: $e';
        });
      }
    }
  }

  Future<void> _handlePickBackupFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result.isEmpty || result.first.path == null) return;

      final file = File(result.first.path!);
      if (!await file.exists()) return;

      final jsonContent = await file.readAsString();
      final dbService = ref.read(databaseServiceProvider);

      final preview = await BackupRestoreService.previewBackup(
        jsonContent,
        dbService: dbService,
      );

      if (mounted) {
        setState(() {
          _selectedBackupJson = jsonContent;
          _selectedBackupFileName = file.path.split('/').last;
          _restorePreview = preview;
          _statusMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Invalid backup file: $e';
        });
      }
    }
  }

  Future<void> _handleExecuteRestore() async {
    if (_selectedBackupJson == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Restoring library data safely...';
    });

    try {
      final dbService = ref.read(databaseServiceProvider);
      final result = await BackupRestoreService.executeRestore(
        backupJson: _selectedBackupJson!,
        dbService: dbService,
        policy: _conflictPolicy,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedBackupJson = null;
          _restorePreview = null;
          _statusMessage =
              'Restore completed!\n• Books added: ${result.booksRestored}\n• Books updated: ${result.booksUpdated}\n• Bookmarks: ${result.bookmarksRestored}\n• Highlights & Notes: ${result.highlightsRestored}\n• Collections: ${result.collectionsRestored}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Library restored successfully!'),
            backgroundColor: Color(0xFF2C2C2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Restore failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.settings_backup_restore_rounded,
                      color: Color(0xFF007AFF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Backup & Restore Library',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF007AFF),
                labelColor: const Color(0xFF007AFF),
                unselectedLabelColor: Colors.grey,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.upload_file, size: 18),
                    text: 'Export Backup',
                  ),
                  Tab(
                    icon: Icon(Icons.download, size: 18),
                    text: 'Restore Data',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Content Area
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildExportTab(isDark), _buildRestoreTab(isDark)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportTab(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withAlpha(10)
                  : Colors.black.withAlpha(5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF007AFF),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Exporting creates a standardized JSON backup file containing all book metadata, chapters, reading progress, bookmarks, highlights, notes, collections, and preferences.\n\nNote: Original PDF files stay safely in your local directory.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _statusMessage!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF007AFF)),
              ),
            ),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleExport,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.description_outlined, size: 18),
              label: const Text('Export Library Metadata (.json)'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _handleExportFullBundle,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.folder_zip_outlined, size: 18),
              label: const Text(
                'Export Full Library Bundle (with original PDFs)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestoreTab(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _handlePickBackupFile,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(
              _selectedBackupFileName != null
                  ? 'Selected: $_selectedBackupFileName'
                  : 'Select Backup JSON File',
            ),
          ),
          const SizedBox(height: 16),

          if (_restorePreview != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(12)
                    : Colors.black.withAlpha(5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF007AFF).withAlpha(50),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Backup Contents Preview',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'v${_restorePreview!.appVersion} • ${DateFormat.yMMMd().format(_restorePreview!.exportedAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    '• Total Books: ${_restorePreview!.totalBooks} (${_restorePreview!.newBooks} new, ${_restorePreview!.existingBooks} already present)',
                  ),
                  const SizedBox(height: 4),
                  Text('• Bookmarks: ${_restorePreview!.totalBookmarks}'),
                  const SizedBox(height: 4),
                  Text(
                    '• Highlights & Notes: ${_restorePreview!.totalHighlights}',
                  ),
                  const SizedBox(height: 4),
                  Text('• Collections: ${_restorePreview!.totalCollections}'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Conflict Resolution Policy:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(
                () => _conflictPolicy = RestoreConflictPolicy.skipExisting,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _conflictPolicy == RestoreConflictPolicy.skipExisting
                        ? const Color(0xFF007AFF)
                        : Colors.grey.withAlpha(50),
                    width: _conflictPolicy == RestoreConflictPolicy.skipExisting
                        ? 1.5
                        : 1,
                  ),
                  color: _conflictPolicy == RestoreConflictPolicy.skipExisting
                      ? const Color(0xFF007AFF).withAlpha(15)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      _conflictPolicy == RestoreConflictPolicy.skipExisting
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color:
                          _conflictPolicy == RestoreConflictPolicy.skipExisting
                          ? const Color(0xFF007AFF)
                          : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skip Existing Books (Recommended)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Keeps existing books intact; merges non-duplicate bookmarks & notes',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(
                () =>
                    _conflictPolicy = RestoreConflictPolicy.mergeUpdateExisting,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        _conflictPolicy ==
                            RestoreConflictPolicy.mergeUpdateExisting
                        ? const Color(0xFF007AFF)
                        : Colors.grey.withAlpha(50),
                    width:
                        _conflictPolicy ==
                            RestoreConflictPolicy.mergeUpdateExisting
                        ? 1.5
                        : 1,
                  ),
                  color:
                      _conflictPolicy ==
                          RestoreConflictPolicy.mergeUpdateExisting
                      ? const Color(0xFF007AFF).withAlpha(15)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      _conflictPolicy ==
                              RestoreConflictPolicy.mergeUpdateExisting
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color:
                          _conflictPolicy ==
                              RestoreConflictPolicy.mergeUpdateExisting
                          ? const Color(0xFF007AFF)
                          : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update Existing Books',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Updates metadata & progress; merges all annotations',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleExecuteRestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF34C759),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  _isLoading ? 'Restoring...' : 'Confirm & Restore Library',
                ),
              ),
            ),
          ],

          if (_statusMessage != null && _restorePreview == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
