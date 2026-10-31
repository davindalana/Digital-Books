import 'dart:io';
import 'dart:typed_data';
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

  /// Generates a cover for a book.
  /// First attempts to extract and upscale Page 1 of the PDF in ultra-high resolution
  /// with sharpening so it looks crisp and sharp like an Apple Books cover.
  /// If the PDF cannot be rendered or has no pages, falls back to the procedural cover.
  static Future<File> generateCover({
    required String bookId,
    required String pdfPath,
    required String title,
    required String author,
  }) async {
    final coversDir = await FileStorageService.getCoversDirectory();
    final coverFile = File(p.join(coversDir.path, '$bookId.png'));

    // 1. On macOS, render Page 1 using native CoreGraphics & PDFKit with CoreImage Unsharp Mask
    if (Platform.isMacOS && File(pdfPath).existsSync()) {
      try {
        final success = await _renderPage1WithNativeMac(pdfPath, coverFile.path);
        if (success && await coverFile.exists() && await coverFile.length() > 5000) {
          return coverFile;
        }
      } catch (e) {
        debugPrint('Native Mac cover generation error: $e');
      }
    }

    // 2. Fallback to procedural typography cover
    return generateProceduralCover(
      bookId: bookId,
      title: title,
      author: author,
    );
  }

  static Future<bool> _renderPage1WithNativeMac(String pdfPath, String outPath) async {
    const swiftCode = '''
import Foundation
import PDFKit
import CoreGraphics
import CoreImage

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let pdfPath = args[1]
let outPath = args[2]

guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
      let page = doc.page(at: 0) else { exit(1) }

let pageRect = page.bounds(for: .mediaBox)
let scale: CGFloat = 3.0
let targetWidth = Int(pageRect.width * scale)
let targetHeight = Int(pageRect.height * scale)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: targetWidth,
    height: targetHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.interpolationQuality = .high
context.setShouldAntialias(true)
context.setAllowsAntialiasing(true)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

context.saveGState()
context.scaleBy(x: scale, y: scale)
page.draw(with: .mediaBox, to: context)
context.restoreGState()

guard let rawCgImage = context.makeImage() else { exit(1) }

// Apply unsharp mask for crystal clear text and artwork
let ciImage = CIImage(cgImage: rawCgImage)
let filter = CIFilter(name: "CIUnsharpMask")!
filter.setValue(ciImage, forKey: kCIInputImageKey)
filter.setValue(0.55, forKey: kCIInputIntensityKey)
filter.setValue(1.5, forKey: kCIInputRadiusKey)

let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
let finalCgImage: CGImage
if let output = filter.outputImage,
   let rendered = ciContext.createCGImage(output, from: output.extent) {
    finalCgImage = rendered
} else {
    finalCgImage = rawCgImage
}

let destUrl = URL(fileURLWithPath: outPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(destUrl, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, finalCgImage, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
''';

    final process = await Process.start('swift', ['-', pdfPath, outPath]);
    process.stdin.write(swiftCode);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    return exitCode == 0;
  }

  static Future<File> generateProceduralCover({
    required String bookId,
    required String title,
    required String author,
  }) async {
    final coversDir = await FileStorageService.getCoversDirectory();
    final coverFile = File(p.join(coversDir.path, '$bookId.png'));

    try {
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

      // Subtle Book Spine Shadow on left (with explicit colorStops!)
      final spineShadow = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(28, 0),
          [
            Colors.black.withAlpha(160),
            Colors.black.withAlpha(30),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
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
          [0.0, 1.0],
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
      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        await coverFile.writeAsBytes(pngBytes);
        return coverFile;
      }
    } catch (e) {
      debugPrint('Error generating procedural canvas cover: $e');
    }

    // Fallback minimal 1x1 image if canvas rendering encountered unexpected issues
    return _generateFallbackPng(coverFile);
  }

  static Future<File> _generateFallbackPng(File targetFile) async {
    // 1x1 dark gray PNG
    final fallbackBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x00, 0x00,
      0x00, 0x04, 0x00, 0x01, 0xA2, 0x12, 0x2A, 0x24, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    await targetFile.writeAsBytes(fallbackBytes);
    return targetFile;
  }
}
