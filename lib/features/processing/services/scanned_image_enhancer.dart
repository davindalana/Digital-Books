import 'dart:math' as math;
import 'dart:typed_data';

enum ScanEnhancementIntensity {
  gentle('Lembut', contrast: 1.20, brightness: 10, unsharpAmount: 0.25),
  balanced('Seimbang', contrast: 1.35, brightness: 16, unsharpAmount: 0.32),
  strong('Kuat', contrast: 1.50, brightness: 20, unsharpAmount: 0.40);

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

/// Adaptive gutter shadow profile derived from empirical page luminance analysis.
class GutterShadowProfile {
  final bool hasShadow;
  final int maxBoost;
  final int gutterWidth;

  const GutterShadowProfile({
    required this.hasShadow,
    required this.maxBoost,
    required this.gutterWidth,
  });

  static const none = GutterShadowProfile(
    hasShadow: false,
    maxBoost: 0,
    gutterWidth: 0,
  );
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
    final isStrong = (intensity == ScanEnhancementIntensity.strong);
    final thresh = isStrong ? 185 : 192;
    final bonus = isStrong ? 48.0 : 24.0;

    for (int i = 0; i < 256; i++) {
      // S-curve contrast boost with gentle paper background whitening:
      // Dark text (values < 110) is pushed towards deep solid black.
      // Yellowed or gray paper background is cleanly pushed to white (255).
      double normalized = (i - 128.0) / 128.0;
      double contrasted = normalized * contrast;
      // Apply brightness gently to upper tones without washing out text ink
      double brightAdjustment = normalized > 0
          ? (brightness * (normalized * normalized))
          : (brightness * normalized * 0.3);
      double shifted = (contrasted * 128.0) + 128.0 + brightAdjustment;

      // Smooth quadratic highlight compression for true paper background (i > thresh)
      // Preserves anti-aliased character edges (100-195) from being bleached to 255!
      if (i > thresh) {
        final t = (i - thresh) / (255.0 - thresh);
        shifted += t * t * bonus;
      }

      int clamped = shifted.round().clamp(0, 255);
      lut[i] = clamped;
    }

    _contrastLuts[intensity] = lut;
    return lut;
  }

  /// Adaptively measures whether an actual luminance gradient (spine shadow)
  /// is present near the gutter binding edge.
  static GutterShadowProfile _detectGutterShadow(
    Uint8List srcPixels,
    int width,
    int height,
    bool isLeftPage,
  ) {
    if (width <= 20 || height <= 20) return GutterShadowProfile.none;

    final maxGutterWidth = (width * 0.16).round();
    final coreStart = (width * 0.35).round();
    final coreEnd = (width * 0.65).round();

    // Fast sampling across 40 rows (< 0.5 ms budget)
    const rowsToSample = 40;
    final stepY = math.max(1, height ~/ rowsToSample);

    final coreSamples = <int>[];
    final edgeSamples = <int>[];

    for (int r = 1; r < rowsToSample; r++) {
      final y = r * stepY;
      if (y >= height) break;
      final rowOffset = y * width * 4;

      // Sample core background
      for (int x = coreStart; x < coreEnd; x += 16) {
        final idx = rowOffset + (x * 4);
        final lum = (srcPixels[idx + 2] * 77 + srcPixels[idx + 1] * 150 + srcPixels[idx] * 29) >> 8;
        coreSamples.add(lum);
      }

      // Sample gutter edge strip (outer 4% of page)
      final edgeXStart = isLeftPage ? (width - (maxGutterWidth * 0.25).round()) : 0;
      final edgeXEnd = isLeftPage ? width : (maxGutterWidth * 0.25).round();
      for (int x = edgeXStart; x < edgeXEnd; x += 4) {
        final idx = rowOffset + (x * 4);
        final lum = (srcPixels[idx + 2] * 77 + srcPixels[idx + 1] * 150 + srcPixels[idx] * 29) >> 8;
        edgeSamples.add(lum);
      }
    }

    if (coreSamples.isEmpty || edgeSamples.isEmpty) return GutterShadowProfile.none;

    coreSamples.sort();
    edgeSamples.sort();

    // 90th percentile gives background paper luminance (free from text/illustration pixels)
    final coreBg = coreSamples[(coreSamples.length * 0.90).round().clamp(0, coreSamples.length - 1)];
    final edgeBg = edgeSamples[(edgeSamples.length * 0.90).round().clamp(0, edgeSamples.length - 1)];

    // If edge is already clean white (>= 242) or edge is not darker than core by at least 12 luminance:
    // Page has no gutter shadow! Do not apply compensation.
    final shadowDelta = coreBg - edgeBg;
    if (shadowDelta < 12 || edgeBg >= 242) {
      return GutterShadowProfile.none;
    }

    final maxBoost = math.min(45, shadowDelta);
    return GutterShadowProfile(
      hasShadow: true,
      maxBoost: maxBoost,
      gutterWidth: maxGutterWidth,
    );
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

    // Detect actual gutter shadow gradient if enabled
    final shadowProfile = removeGutter
        ? _detectGutterShadow(srcPixels, width, height, isLeft)
        : GutterShadowProfile.none;
    final gutterWidth = shadowProfile.gutterWidth;

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width * 4;
      for (int x = 0; x < width; x++) {
        final idx = rowOffset + (x * 4);

        final b = srcPixels[idx];
        final g = srcPixels[idx + 1];
        final r = srcPixels[idx + 2];
        final a = srcPixels[idx + 3];

        int gutterBoost = 0;
        if (shadowProfile.hasShadow && gutterWidth > 0) {
          int rawBoost = 0;
          if (isLeft && x > width - gutterWidth) {
            final distFromEdge = width - 1 - x;
            final factor = (gutterWidth - distFromEdge) / gutterWidth;
            rawBoost = (factor * shadowProfile.maxBoost).round();
          } else if (!isLeft && x < gutterWidth) {
            final factor = (gutterWidth - x) / gutterWidth;
            rawBoost = (factor * shadowProfile.maxBoost).round();
          }

          if (rawBoost > 0) {
            // Text preservation: do not wash out solid dark ink (L < 90) near margin
            final lum = (r * 77 + g * 150 + b * 29) >> 8;
            final textProtection = ((lum - 90) / 130.0).clamp(0.0, 1.0);
            gutterBoost = (rawBoost * textProtection).round();
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
    final int blendFactor = (amount * 48).round().clamp(0, 48);
    if (blendFactor <= 0) return;

    // Use a lightweight 5-point cross stencil for sharp edges without blur halo
    for (int y = 1; y < height - 1; y += 1) {
      final rowPrev = (y - 1) * width * 4;
      final rowCurr = y * width * 4;
      final rowNext = (y + 1) * width * 4;

      for (int x = 1; x < width - 1; x += 1) {
        final c = rowCurr + (x * 4);
        final val = pixels[c];

        // Only sharpen non-saturated pixels, protecting anti-aliased edge boundaries
        if (val > 20 && val < 235) {
          final top = pixels[rowPrev + (x * 4)];
          final bot = pixels[rowNext + (x * 4)];
          final left = pixels[rowCurr + ((x - 1) * 4)];
          final right = pixels[rowCurr + ((x + 1) * 4)];

          final laplacian = (val << 2) - (top + bot + left + right);
          final adjustment = (laplacian * blendFactor) >> 6;

          // Edge-preserving clamp: do not push a stroke edge pixel above 220 into white!
          int sharpened;
          if (val < 200 && adjustment > 0) {
            sharpened = math.min(220, val + adjustment);
          } else {
            sharpened = val + adjustment;
          }
          final clamped = sharpened.clamp(0, 255);

          pixels[c] = clamped;
          pixels[c + 1] = clamped;
          pixels[c + 2] = clamped;
        }
      }
    }
  }
}
