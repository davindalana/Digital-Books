import 'dart:ui' show Rect, Size;
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfFontStyle;

/// Classification of a PDF page's content layer.
enum PageLayerType {
  /// Page contains rich, selectable vector text with font metrics and coordinates.
  nativeText,

  /// Page contains only bitmap raster scans without an underlying selectable text layer.
  scannedImage,

  /// Page contains both native vector text and embedded images/figures.
  hybrid,

  /// Page contains neither text nor images (e.g. blank page or unsupported format).
  emptyOrUnsupported,
}

/// Represents an individual extracted word with its exact bounding box coordinates.
class ExtractedTextWord {
  final Rect bounds;
  final String text;

  const ExtractedTextWord({required this.bounds, required this.text});

  Map<String, dynamic> toJson() => {
    'bounds': [bounds.left, bounds.top, bounds.width, bounds.height],
    'text': text,
  };

  factory ExtractedTextWord.fromJson(Map<String, dynamic> json) {
    final b = (json['bounds'] as List<dynamic>).cast<num>();
    return ExtractedTextWord(
      bounds: Rect.fromLTWH(
        b[0].toDouble(),
        b[1].toDouble(),
        b[2].toDouble(),
        b[3].toDouble(),
      ),
      text: json['text'] as String? ?? '',
    );
  }
}

/// Represents an extracted line of text with geometric bounds, font metrics, and word details.
class ExtractedTextLine {
  final Rect bounds;
  final String text;
  final double fontSize;
  final List<PdfFontStyle> fontStyle;
  final String fontName;
  final List<ExtractedTextWord> words;
  final int lineIndex;
  final int pageIndex;

  const ExtractedTextLine({
    required this.bounds,
    required this.text,
    required this.fontSize,
    this.fontStyle = const [],
    this.fontName = '',
    this.words = const [],
    required this.lineIndex,
    required this.pageIndex,
  });

  bool get isBold => fontStyle.contains(PdfFontStyle.bold);
  bool get isItalic => fontStyle.contains(PdfFontStyle.italic);

  Map<String, dynamic> toJson() => {
    'bounds': [bounds.left, bounds.top, bounds.width, bounds.height],
    'text': text,
    'fontSize': fontSize,
    'fontStyle': fontStyle.map((s) => s.name).toList(),
    'fontName': fontName,
    'words': words.map((w) => w.toJson()).toList(),
    'lineIndex': lineIndex,
    'pageIndex': pageIndex,
  };
}

/// Represents an extracted image asset with physical dimensions, aspect ratio, and disk location.
class ExtractedImage {
  final String id;
  final String name;
  final int sourcePage;
  final Size dimensions;
  final double aspectRatio;
  final String filter;
  final String? imagePath;
  final int bytesLength;
  final Rect? bounds;
  final bool isCover;

  const ExtractedImage({
    required this.id,
    required this.name,
    required this.sourcePage,
    required this.dimensions,
    required this.aspectRatio,
    required this.filter,
    this.imagePath,
    required this.bytesLength,
    this.bounds,
    this.isCover = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourcePage': sourcePage,
    'width': dimensions.width,
    'height': dimensions.height,
    'aspectRatio': aspectRatio,
    'filter': filter,
    'imagePath': imagePath,
    'bytesLength': bytesLength,
    'bounds': bounds != null
        ? [bounds!.left, bounds!.top, bounds!.width, bounds!.height]
        : null,
    'isCover': isCover,
  };
}

/// Geometry and layer information for an individual PDF page.
class ExtractedPageGeometry {
  final int pageIndex;
  final Size pageSize;
  final List<ExtractedTextLine> lines;
  final List<ExtractedImage> images;
  final PageLayerType layerType;
  final int charCount;

  const ExtractedPageGeometry({
    required this.pageIndex,
    required this.pageSize,
    required this.lines,
    required this.images,
    required this.layerType,
    required this.charCount,
  });

  bool get hasTextLayer =>
      layerType == PageLayerType.nativeText ||
      layerType == PageLayerType.hybrid;

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'pageSize': [pageSize.width, pageSize.height],
    'lines': lines.map((l) => l.toJson()).toList(),
    'images': images.map((img) => img.toJson()).toList(),
    'layerType': layerType.name,
    'charCount': charCount,
  };
}

/// The complete intermediate extraction result across an entire document.
class DocumentExtractionResult {
  final String bookId;
  final int totalPages;
  final List<ExtractedPageGeometry> pages;
  final int totalTextLines;
  final int totalImages;
  final Map<PageLayerType, int> layerBreakdown;
  final bool hasUsableTextLayer;
  final List<String> warnings;
  final double durationMs;

  const DocumentExtractionResult({
    required this.bookId,
    required this.totalPages,
    required this.pages,
    required this.totalTextLines,
    required this.totalImages,
    required this.layerBreakdown,
    required this.hasUsableTextLayer,
    required this.warnings,
    required this.durationMs,
  });

  /// Recommendation on whether this document is suitable for Reflowable reading or Original PDF.
  String get recommendedReaderTier {
    if (!hasUsableTextLayer) {
      return 'Original PDF Reader (Document is scanned or lacks selectable text)';
    }
    if (layerBreakdown[PageLayerType.scannedImage] != null &&
        layerBreakdown[PageLayerType.scannedImage]! > 0) {
      return 'Original PDF Reader (Contains mixed scanned pages)';
    }
    return 'Smart Reflowable Reader (Native text layer verified)';
  }

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'totalPages': totalPages,
    'totalTextLines': totalTextLines,
    'totalImages': totalImages,
    'layerBreakdown': layerBreakdown.map((k, v) => MapEntry(k.name, v)),
    'hasUsableTextLayer': hasUsableTextLayer,
    'recommendedReaderTier': recommendedReaderTier,
    'warnings': warnings,
    'durationMs': durationMs,
    'pages': pages.map((p) => p.toJson()).toList(),
  };
}
