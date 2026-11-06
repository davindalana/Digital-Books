import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:pdfrx/pdfrx.dart';
import '../models/ocr_page_result.dart';

/// Local-first Apple Vision OCR Service on macOS.
/// Leverages Apple's Neural Engine via the native `bin/vision_ocr` tool
/// to recognize text lines, bounding boxes, and confidence scores offline.
class AppleVisionOcrService {
  final String? customBinaryPath;

  const AppleVisionOcrService({this.customBinaryPath});

  /// Path to the compiled native Vision OCR helper executable.
  String get binaryPath {
    if (customBinaryPath != null && File(customBinaryPath!).existsSync()) {
      return customBinaryPath!;
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final bundleBin = File('${exeDir.path}/vision_ocr');
      if (bundleBin.existsSync()) return bundleBin.path;
      final resourceBin = File('${exeDir.parent.path}/Resources/vision_ocr');
      if (resourceBin.existsSync()) return resourceBin.path;
    } catch (_) {}

    final relativeBin = File('bin/vision_ocr');
    if (relativeBin.existsSync()) {
      return relativeBin.absolute.path;
    }
    final rootBin = File('${Directory.current.path}/bin/vision_ocr');
    if (rootBin.existsSync()) {
      return rootBin.path;
    }
    const knownProjectBin =
        '/Users/davindalana/Documents/Project/Digital Books/bin/vision_ocr';
    if (File(knownProjectBin).existsSync()) {
      return knownProjectBin;
    }
    return 'bin/vision_ocr';
  }

  /// Path to the Swift source file if compilation is needed.
  String get swiftSourcePath {
    final rel = File('macos/tools/vision_ocr.swift');
    if (rel.existsSync()) return rel.absolute.path;
    final rootSrc = File(
      '${Directory.current.path}/macos/tools/vision_ocr.swift',
    );
    if (rootSrc.existsSync()) return rootSrc.path;
    const knownSrc =
        '/Users/davindalana/Documents/Project/Digital Books/macos/tools/vision_ocr.swift';
    if (File(knownSrc).existsSync()) return knownSrc;
    return '${Directory.current.path}/macos/tools/vision_ocr.swift';
  }

  /// Checks whether local Apple Vision OCR is supported and executable.
  bool get isAvailable {
    if (!Platform.isMacOS) return false;
    final file = File(binaryPath);
    if (file.existsSync()) return true;
    return File(swiftSourcePath).existsSync();
  }

  /// Ensures the native helper binary is present, compiling from source if necessary.
  Future<bool> ensureBinaryAvailable() async {
    if (!Platform.isMacOS) return false;
    final bin = File(binaryPath);
    if (bin.existsSync()) return true;

    final src = File(swiftSourcePath);
    if (!src.existsSync()) return false;

    try {
      final binDir = bin.parent;
      if (!binDir.existsSync()) {
        binDir.createSync(recursive: true);
      }
      final result = await Process.run('swiftc', [
        '-O',
        src.absolute.path,
        '-o',
        bin.absolute.path,
      ]);
      return result.exitCode == 0 && bin.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Performs local OCR on an image file at [imagePath].
  Future<OcrPageResult> processImage(
    String imagePath, {
    List<String> languages = const ['id-ID', 'en-US'],
    bool accurate = true,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return OcrPageResult(
        imagePath: imagePath,
        width: 0,
        height: 0,
        durationMs: 0,
        lines: const [],
        error: 'Image file does not exist at $imagePath',
      );
    }

    if (!File(binaryPath).existsSync()) {
      final compiled = await ensureBinaryAvailable();
      if (!compiled || !File(binaryPath).existsSync()) {
        return OcrPageResult(
          imagePath: imagePath,
          width: 0,
          height: 0,
          durationMs: 0,
          lines: const [],
          error:
              'Apple Vision OCR binary not found and failed to compile from $swiftSourcePath',
        );
      }
    }

    final args = [
      '--image',
      file.absolute.path,
      '--languages',
      languages.join(','),
      if (accurate) '--accurate' else '--fast',
    ];

    try {
      final res = await Process.run(binaryPath, args);
      if (res.exitCode != 0) {
        return OcrPageResult(
          imagePath: imagePath,
          width: 0,
          height: 0,
          durationMs: 0,
          lines: const [],
          error:
              'Vision OCR process exited with code ${res.exitCode}: ${res.stderr}',
        );
      }

      final jsonOutput = res.stdout.toString().trim();
      if (jsonOutput.isEmpty) {
        return OcrPageResult(
          imagePath: imagePath,
          width: 0,
          height: 0,
          durationMs: 0,
          lines: const [],
          error: 'Vision OCR returned empty output',
        );
      }

      final parsed = jsonDecode(jsonOutput) as Map<String, dynamic>;
      return OcrPageResult.fromJson(parsed);
    } catch (e) {
      return OcrPageResult(
        imagePath: imagePath,
        width: 0,
        height: 0,
        durationMs: 0,
        lines: const [],
        error: 'Failed to execute Apple Vision OCR: $e',
      );
    }
  }

  /// Renders a [PdfPage] to a temporary high-resolution PNG, runs Apple Vision OCR,
  /// and automatically cleans up the temporary render artifact.
  Future<OcrPageResult> processPdfPage(
    PdfPage page, {
    double scale = 1.5,
    List<String> languages = const ['id-ID', 'en-US'],
    bool accurate = true,
  }) async {
    final renderW = (page.width * scale).round();
    final renderH = (page.height * scale).round();

    // NOTE: pdfrx `width`/`height` are a *clip rectangle* in page coordinates,
    // not an output size. Passing them alone renders the top-left corner at
    // native scale inside a stretched canvas, which shifts and compresses every
    // normalised OCR box. `fullWidth`/`fullHeight` scale the whole page instead.
    final pdfImage = await page.render(
      fullWidth: renderW.toDouble(),
      fullHeight: renderH.toDouble(),
    );
    if (pdfImage == null) {
      return OcrPageResult(
        imagePath: '',
        width: renderW,
        height: renderH,
        durationMs: 0,
        lines: const [],
        error: 'Failed to render PDF page ${page.pageNumber}',
      );
    }

    // Convert raw BGRA pixels to PNG file
    final tempDir = Directory.systemTemp.createTempSync('digital_books_ocr_');
    final tempImgFile = File('${tempDir.path}/page_${page.pageNumber}.png');

    try {
      final pngBytes = await _bgraToPng(
        pdfImage.pixels,
        pdfImage.width,
        pdfImage.height,
      );
      pdfImage.dispose();
      await tempImgFile.writeAsBytes(pngBytes);

      final result = await processImage(
        tempImgFile.path,
        languages: languages,
        accurate: accurate,
      );
      return result;
    } finally {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<Uint8List> _bgraToPng(
    Uint8List bgra,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bgra,
      width,
      height,
      ui.PixelFormat.bgra8888,
      (img) => completer.complete(img),
    );
    final img = await completer.future;
    canvas.drawImage(img, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    rendered.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }
}
