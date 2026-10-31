import 'package:flutter/material.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/models/highlight_palette.dart';

class HighlightInteractionSheet extends StatefulWidget {
  final Highlight? existingHighlight;
  final String selectedText;
  final String initialColor;
  final String? initialNote;
  final ReadingThemeType theme;
  final Function(String color, String? note) onSave;
  final VoidCallback? onDelete;

  const HighlightInteractionSheet({
    super.key,
    this.existingHighlight,
    required this.selectedText,
    this.initialColor = 'yellow',
    this.initialNote,
    required this.theme,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Highlight? existingHighlight,
    required String selectedText,
    String initialColor = 'yellow',
    String? initialNote,
    required ReadingThemeType theme,
    required Function(String color, String? note) onSave,
    VoidCallback? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => HighlightInteractionSheet(
        existingHighlight: existingHighlight,
        selectedText: selectedText,
        initialColor: initialColor,
        initialNote: initialNote,
        theme: theme,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<HighlightInteractionSheet> createState() =>
      _HighlightInteractionSheetState();
}

class _HighlightInteractionSheetState extends State<HighlightInteractionSheet> {
  late String _selectedColor;
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.existingHighlight?.color ?? widget.initialColor;
    _noteController = TextEditingController(
      text: widget.existingHighlight?.note ?? widget.initialNote ?? '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.isDark;
    final bgColor = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = isDark ? Colors.white60 : Colors.black54;

    final currentColorType = HighlightColorType.fromKey(_selectedColor);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with title and close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.border_color,
                        size: 18,
                        color: currentColorType.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.existingHighlight != null
                            ? 'Edit Sorotan & Catatan'
                            : 'Buat Sorotan Baru',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: secondaryColor,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. Selected Text Quote Preview
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: currentColorType.getBackgroundColor(widget.theme),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: currentColorType.primaryColor,
                      width: 4,
                    ),
                  ),
                ),
                child: Text(
                  '"${widget.selectedText}"',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Color Picker Row
              Text(
                'PILIH WARNA',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: HighlightColorType.values.map((c) {
                  final isSelected = c.key == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = c.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.primaryColor,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: textColor, width: 3)
                            : Border.all(color: Colors.black12, width: 1),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: c.primaryColor.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 20,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 4. Note Input Field
              Text(
                'CATATAN PRIBADI (OPSIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 3,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText:
                      'Tulis pemikiran atau referensi untuk kutipan ini...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: secondaryColor.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF2A2A2E)
                      : const Color(0xFFF3F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 18),

              // 5. Actions Footer
              Row(
                children: [
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Hapus Sorotan',
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDelete!();
                      },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Batal',
                      style: TextStyle(color: secondaryColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      widget.existingHighlight != null ? 'Perbarui' : 'Simpan',
                    ),
                    onPressed: () {
                      final noteText = _noteController.text.trim();
                      widget.onSave(
                        _selectedColor,
                        noteText.isEmpty ? null : noteText,
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
