import 'dart:math' as math;
import 'dart:typed_data';

enum ScanEnhancementIntensity {
  gentle('Lembut', contrast: 1.25, brightness: 12, unsharpAmount: 0.35),
  balanced('Seimbang', contrast: 1.45, brightness: 22, unsharpAmount: 0.55),
  strong('Kuat', contrast: 1.70, brightness: 32, unsharpAmount: 0.75);

  final String label;
  final double contrast;
  final int brightness;
  final double unsharpAmount;

  const ScanEnhancementIntensity(
    this.label, {
    required this.contrast,
    required this.brightness,
    required this.unsharpAmount,
  });
}

class ScanEnhancementConfig {
  final bool isEnabled;
  final ScanEnhancementIntensity intensity;
  final bool toGrayscale;
  final bool removeGutterShadow;
  final bool isLeftPage;

  const ScanEnhancementConfig({
    this.isEnabled = false,
    this.intensity = ScanEnhancementIntensity.balanced,
    this.toGrayscale = true,
    this.removeGutterShadow = true,
    this.isLeftPage = false,
  });

  ScanEnhancementConfig copyWith({
    bool? isEnabled,
    ScanEnhancementIntensity? intensity,
    bool? toGrayscale,
    bool? removeGutterShadow,
    bool? isLeftPage,
  }) {
    return ScanEnhancementConfig(
      isEnabled: isEnabled ?? this.isEnabled,
      intensity: intensity ?? this.intensity,
      toGrayscale: toGrayscale ?? this.toGrayscale,
      removeGutterShadow: removeGutterShadow ?? this.removeGutterShadow,
      isLeftPage: isLeftPage ?? this.isLeftPage,
    );
  }

  String get cacheKeySuffix {
    if (!isEnabled) return 'raw';
    final side = isLeftPage ? 'L' : 'R';
    final gut = removeGutterShadow ? '1' : '0';
    final gray = toGrayscale ? '1' : '0';
    return 'enh_${intensity.name}_${side}_g${gut}_gr$gray';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanEnhancementConfig &&
          runtimeType == other.runtimeType &&
          isEnabled == other.isEnabled &&
          intensity == other.intensity &&
          toGrayscale == other.toGrayscale &&
          removeGutterShadow == other.removeGutterShadow &&
          isLeftPage == other.isLeftPage;

  @override
  int get hashCode =>
      isEnabled.hashCode ^
      intensity.hashCode ^
      toGrayscale.hashCode ^
      removeGutterShadow.hashCode ^
      isLeftPage.hashCode;
}

/// High-performance non-destructive scanned PDF page image enhancer.
/// Operates on 32-bit BGRA (Blue, Green, Red, Alpha) pixel buffers.
class ScannedImageEnhancer {
  static final Map<ScanEnhancementIntensity, Uint8List> _contrastLuts = {};

  static Uint8List _getOrCreateLut(ScanEnhancementIntensity intensity) {
    if (_contrastLuts.containsKey(intensity)) {
      return _contrastLuts[intensity]!;
    }

    final lut = Uint8List(256);
    final contrast = intensity.contrast;
    final brightness = intensity.brightness;

    for (int i = 0; i < 256; i++) {
      // S-curve contrast boost with background whitening:
      // Dark text (values < 120) is pushed towards deep black.
      // Yellowed or gray paper background (values > 175) is cleanly pushed to white (255).
      double normalized = (i - 128.0) / 128.0;
      double contrasted = normalized * contrast;
      // Apply brightness primarily to the upper half (paper background) without washing out text ink
      double brightAdjustment = normalized > 0
          ? (brightness * (normalized * normalized))
          : (brightness * normalized * 0.5);
      double shifted = (contrasted * 128.0) + 128.0 + brightAdjustment;

      // Soft non-linear highlight compression (paper whitening)
      if (i > 175) {
        final highlightBonus = (i - 175) * 1.8;
        shifted += highlightBonus;
      }

      int clamped = shifted.round().clamp(0, 255);
      lut[i] = clamped;
    }

    _contrastLuts[intensity] = lut;
    return lut;
  }

  /// Enhances a BGRA8888 image buffer non-destructively.
  /// Returns a new [Uint8List] containing enhanced pixel data.
  static Uint8List enhanceBgra({
    required Uint8List srcPixels,
    required int width,
    required int height,
    required ScanEnhancementConfig config,
  }) {
    if (!config.isEnabled || width <= 0 || height <= 0) {
      return srcPixels;
    }

    final totalBytes = width * height * 4;
    if (srcPixels.length < totalBytes) {
      return srcPixels;
    }

    final output = Uint8List(totalBytes);
    final lut = _getOrCreateLut(config.intensity);
    final toGrayscale = config.toGrayscale;
    final removeGutter = config.removeGutterShadow;
    final isLeft = config.isLeftPage;

    // Gutter gradient parameters:
    // Left page: gutter is on the RIGHT 15% of the page.
    // Right page: gutter is on the LEFT 15% of the page.
    final gutterWidth = (width * 0.16).round();

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width * 4;
      for (int x = 0; x < width; x++) {
        final idx = rowOffset + (x * 4);

        final b = srcPixels[idx];
        final g = srcPixels[idx + 1];
        final r = srcPixels[idx + 2];
        final a = srcPixels[idx + 3];

        int gutterBoost = 0;
        if (removeGutter && gutterWidth > 0) {
          if (isLeft && x > width - gutterWidth) {
            // Distance from right edge (0 = edge, 1 = inner)
            final distFromEdge = width - 1 - x;
            final factor = (gutterWidth - distFromEdge) / gutterWidth;
            gutterBoost = (factor * 38.0).round();
          } else if (!isLeft && x < gutterWidth) {
            // Distance from left edge
            final factor = (gutterWidth - x) / gutterWidth;
            gutterBoost = (factor * 38.0).round();
          }
        }

        if (toGrayscale) {
          // Standard ITU-R BT.601 integer luminance: (77R + 150G + 29B) >> 8
          int gray = (r * 77 + g * 150 + b * 29) >> 8;
          if (gutterBoost > 0) {
            gray = math.min(255, gray + gutterBoost);
          }
          final enhanced = lut[gray];
          output[idx] = enhanced;
          output[idx + 1] = enhanced;
          output[idx + 2] = enhanced;
          output[idx + 3] = a;
        } else {
          // Color-preserving contrast enhancement
          int lum = (r * 77 + g * 150 + b * 29) >> 8;
          int targetLum = lut[lum];
          if (gutterBoost > 0) {
            targetLum = math.min(255, targetLum + gutterBoost);
          }
          double ratio = lum > 0 ? (targetLum / lum) : 1.0;

          output[idx] = (b * ratio).round().clamp(0, 255);
          output[idx + 1] = (g * ratio).round().clamp(0, 255);
          output[idx + 2] = (r * ratio).round().clamp(0, 255);
          output[idx + 3] = a;
        }
      }
    }

    // Apply fast 3x3 unsharp mask sharpening if intensity demands it
    final unsharpAmount = config.intensity.unsharpAmount;
    if (unsharpAmount > 0.05 && width > 4 && height > 4) {
      _applyFastSharpen(output, width, height, unsharpAmount);
    }

    return output;
  }

  /// Fast horizontal/vertical 3x3 unsharp convolution kernel for character stroke definition.
  static void _applyFastSharpen(
    Uint8List pixels,
    int width,
    int height,
    double amount,
  ) {
    final int blendFactor = (amount * 64).round().clamp(0, 64);
    if (blendFactor <= 0) return;

    // Use a lightweight 5-point cross stencil for sharp edges without blur halo
    for (int y = 1; y < height - 1; y += 1) {
      final rowPrev = (y - 1) * width * 4;
      final rowCurr = y * width * 4;
      final rowNext = (y + 1) * width * 4;

      for (int x = 1; x < width - 1; x += 1) {
        final c = rowCurr + (x * 4);
        final val = pixels[c];

        // Only sharpen non-saturated pixels (protect pure white background and pure black)
        if (val > 15 && val < 245) {
          final top = pixels[rowPrev + (x * 4)];
          final bot = pixels[rowNext + (x * 4)];
          final left = pixels[rowCurr + ((x - 1) * 4)];
          final right = pixels[rowCurr + ((x + 1) * 4)];

          final laplacian = (val << 2) - (top + bot + left + right);
          final sharpened = val + ((laplacian * blendFactor) >> 6);
          final clamped = sharpened.clamp(0, 255);

          pixels[c] = clamped;
          pixels[c + 1] = clamped;
          pixels[c + 2] = clamped;
        }
      }
    }
  }
}
