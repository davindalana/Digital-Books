import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';

class ManageBookCollectionsDialog extends ConsumerWidget {
  final Book book;

  const ManageBookCollectionsDialog({super.key, required this.book});

  static Future<void> show(BuildContext context, Book book) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => ManageBookCollectionsDialog(book: book),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsStreamProvider);
    final bookCollectionIdsAsync =
        ref.watch(bookCollectionIdsStreamProvider(book.id));
    final dbService = ref.read(databaseServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor:
          isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9F9FB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(20),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.folder_special_rounded,
                color: Color(0xFF007AFF), size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Manage Collections',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'New Collection',
            onPressed: () => _showCreateCollectionDialog(context, ref),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: collectionsAsync.when(
          data: (collections) {
            if (collections.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'No Collections Created Yet',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Organize books into custom reading lists or genres.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Create Collection'),
                      onPressed: () =>
                          _showCreateCollectionDialog(context, ref),
                    ),
                  ],
                ),
              );
            }

            final assignedIds = bookCollectionIdsAsync.asData?.value ?? [];

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: collections.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final col = collections[index];
                  final isAssigned = assignedIds.contains(col.id);

                  return CheckboxListTile(
                    dense: true,
                    title: Text(
                      col.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    secondary: Icon(
                      Icons.folder_rounded,
                      color: isAssigned
                          ? const Color(0xFF007AFF)
                          : Colors.grey.shade400,
                      size: 20,
                    ),
                    value: isAssigned,
                    activeColor: const Color(0xFF007AFF),
                    onChanged: (checked) async {
                      if (checked == true) {
                        await dbService.addBookToCollection(book.id, col.id);
                      } else {
                        await dbService.removeBookFromCollection(
                            book.id, col.id);
                      }
                    },
                  );
                },
              ),
            );
          },
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error loading collections: $e'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  static Future<void> _showCreateCollectionDialog(
      BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9F9FB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(20),
          ),
        ),
        title: const Text('New Collection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Collection Name (e.g., Favorites, Psychology)',
            isDense: true,
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              Navigator.of(ctx).pop(val.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (createdName != null && createdName.isNotEmpty) {
      final db = ref.read(databaseServiceProvider);
      await db.createCollection(
        CollectionsCompanion(
          id: drift.Value(const Uuid().v4()),
          name: drift.Value(createdName),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
    }
  }
}
