import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'file_storage_service.dart';

class CoverGenerator {
  static const List<List<Color>> _coverPalettes = [
    [Color(0xFF1E293B), Color(0xFF0F172A)], // Slate Navy
    [Color(0xFF4C0519), Color(0xFF1F020A)], // Crimson Noir
    [Color(0xFF064E3B), Color(0xFF022C22)], // Emerald Deep
    [Color(0xFF451A03), Color(0xFF1C0B02)], // Warm Walnut
    [Color(0xFF311042), Color(0xFF16041F)], // Imperial Violet
    [Color(0xFF1E3A5F), Color(0xFF0C1929)], // Nordic Blue
    [Color(0xFF3B2F2F), Color(0xFF1F1717)], // Antique Leather
  ];

  static Future<File> generateProceduralCover({
    required String bookId,
    required String title,
    required String author,
  }) async {
    const width = 600.0;
    const height = 900.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // Choose palette based on title hash
    final hash = (title + author).hashCode.abs();
    final palette = _coverPalettes[hash % _coverPalettes.length];

    // Background Gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(width, height),
        palette,
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Subtle Book Spine Shadow on left (simulating 3D book)
    final spineShadow = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(28, 0),
        [
          Colors.black.withAlpha(160),
          Colors.black.withAlpha(20),
          Colors.transparent,
        ],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, 28, height), spineShadow);

    // Spine Highlight
    final spineHighlight = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(28, 0),
        const Offset(36, 0),
        [
          Colors.white.withAlpha(40),
          Colors.transparent,
        ],
      );
    canvas.drawRect(const Rect.fromLTWH(28, 0, 8, height), spineHighlight);

    // Inner Embossed Gold/Silver Frame
    final framePaint = Paint()
      ..color = const Color(0xFFE2D8B3).withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final frameRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(50, 50, width - 100, height - 100),
      const Radius.circular(8),
    );
    canvas.drawRRect(frameRect, framePaint);

    final thinInnerFrame = Paint()
      ..color = const Color(0xFFE2D8B3).withAlpha(45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(58, 58, width - 116, height - 116),
        const Radius.circular(5),
      ),
      thinInnerFrame,
    );

    // Top Monogram / Ornament
    final ornamentPaint = Paint()
      ..color = const Color(0xFFE2D8B3).withAlpha(120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(const Offset(width / 2, 130), 20, ornamentPaint);

    // Draw Book Icon / Monogram Initial in Circle
    final initial = title.trim().isNotEmpty ? title.trim()[0].toUpperCase() : 'B';
    final initialPainter = TextPainter(
      text: TextSpan(
        text: initial,
        style: const TextStyle(
          color: Color(0xFFE2D8B3),
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFamily: 'serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    initialPainter.paint(
      canvas,
      Offset(
        (width / 2) - (initialPainter.width / 2),
        130 - (initialPainter.height / 2),
      ),
    );

    // Book Title Text
    final cleanTitle = title.trim().isEmpty ? 'Untitled Book' : title.trim();
    final titleSpan = TextSpan(
      text: cleanTitle,
      style: const TextStyle(
        color: Color(0xFFF8F4E8),
        fontSize: 34,
        fontWeight: FontWeight.bold,
        height: 1.3,
        letterSpacing: 1.2,
        fontFamily: 'serif',
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 5,
    )..layout(maxWidth: width - 160);

    final titleY = (height * 0.38) - (titlePainter.height / 2);
    titlePainter.paint(
      canvas,
      Offset((width / 2) - (titlePainter.width / 2), titleY),
    );

    // Horizontal Divider
    final dividerY = titleY + titlePainter.height + 36;
    final dividerPaint = Paint()
      ..color = const Color(0xFFE2D8B3).withAlpha(100)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset((width / 2) - 60, dividerY),
      Offset((width / 2) + 60, dividerY),
      dividerPaint,
    );

    // Author Text
    final cleanAuthor =
        author.trim().isEmpty ? 'Digital Edition' : author.trim();
    final authorSpan = TextSpan(
      text: cleanAuthor.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFFD4C8A6),
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 3.5,
        fontFamily: 'serif',
      ),
    );
    final authorPainter = TextPainter(
      text: authorSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: width - 160);

    authorPainter.paint(
      canvas,
      Offset((width / 2) - (authorPainter.width / 2), dividerY + 28),
    );

    // Bottom "CLASSICS & ARCHIVE" Label
    final bottomSpan = TextSpan(
      text: 'PERSONAL DIGITAL LIBRARY',
      style: TextStyle(
        color: Colors.white.withAlpha(100),
        fontSize: 11,
        letterSpacing: 3.0,
        fontWeight: FontWeight.w600,
      ),
    );
    final bottomPainter = TextPainter(
      text: bottomSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    bottomPainter.paint(
      canvas,
      Offset((width / 2) - (bottomPainter.width / 2), height - 100),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final coversDir = await FileStorageService.getCoversDirectory();
    final coverFile = File(p.join(coversDir.path, '$bookId.png'));
    await coverFile.writeAsBytes(pngBytes);

    return coverFile;
  }
}

