import 'dart:math' as math;
import 'dart:ui' show Rect, Size;
import '../models/extracted_page_geometry.dart';
import '../models/semantic_reconstruction_models.dart';

/// Role and display presentation of an embedded image asset.
enum ImageSemanticRole {
  coverImage,
  fullPageIllustration,
  diagram,
  inlineFigure,
  unresolved,
}

/// D4: Places extracted images at their precise spatial context and binds proximate captions.
class ImagePlacementResolver {
  /// Resolves image placement and binds proximate captions across all pages.
  static List<SemanticReconstructedBlock> integrateImages({
    required List<SemanticReconstructedBlock> blocks,
    required List<ExtractedImage> images,
    required List<ExtractedPageGeometry> pages,
  }) {
    if (images.isEmpty) return blocks;

    final result = <SemanticReconstructedBlock>[];
    final imagesByPage = <int, List<ExtractedImage>>{};

    for (final img in images) {
      final normalizedPage =
          (img.sourcePage > 0 &&
              !pages.any((p) => p.pageIndex == img.sourcePage))
          ? img.sourcePage - 1
          : img.sourcePage;
      imagesByPage.putIfAbsent(normalizedPage, () => []).add(img);
    }

    final blocksByPage = <int, List<SemanticReconstructedBlock>>{};
    for (final b in blocks) {
      blocksByPage.putIfAbsent(b.sourcePageIndex, () => []).add(b);
    }

    final allPageIndices = {
      ...pages.map((p) => p.pageIndex),
      ...blocks.map((b) => b.sourcePageIndex),
      ...images.map((img) => img.sourcePage),
    }.toList()..sort();

    for (final pIdx in allPageIndices) {
      final pageBlocks = blocksByPage[pIdx] ?? [];
      final pageImages = imagesByPage[pIdx] ?? [];

      if (pageImages.isEmpty) {
        result.addAll(pageBlocks);
        continue;
      }

      final pageGeometry = pages.firstWhere(
        (p) => p.pageIndex == pIdx,
        orElse: () => ExtractedPageGeometry(
          pageIndex: pIdx,
          pageSize: const Size(612, 792),
          lines: const [],
          images: const [],
          layerType: PageLayerType.nativeText,
          charCount: 0,
        ),
      );

      final integratedPage = _integratePageImages(
        pageBlocks: pageBlocks,
        pageImages: pageImages,
        pageGeometry: pageGeometry,
      );

      result.addAll(integratedPage);
    }

    return result;
  }

  /// Integrates images and binds captions for a single page.
  static List<SemanticReconstructedBlock> _integratePageImages({
    required List<SemanticReconstructedBlock> pageBlocks,
    required List<ExtractedImage> pageImages,
    required ExtractedPageGeometry pageGeometry,
  }) {
    final remainingBlocks = List<SemanticReconstructedBlock>.from(pageBlocks);
    final imageBlocks = <SemanticReconstructedBlock>[];

    final pageArea = pageGeometry.pageSize.width * pageGeometry.pageSize.height;

    // Identify candidate caption blocks on this page
    final candidateCaptions = remainingBlocks.where((b) {
      if (b.type == SemanticBlockType.caption) return true;
      return RegExp(
        r'^(figure|fig\.|diagram|gambar|denah|map|chart|tabel|table)\s+([0-9ivxlcdm\.]+)?:?',
        caseSensitive: false,
      ).hasMatch(b.text.trim());
    }).toList();

    for (int i = 0; i < pageImages.length; i++) {
      final img = pageImages[i];
      final imgArea = img.dimensions.width * img.dimensions.height;

      // 1. Detect candidate caption for this image
      SemanticReconstructedBlock? boundCaptionBlock;

      if (candidateCaptions.isNotEmpty) {
        if (pageImages.length == 1) {
          // Exactly one image and one or more captions on page: associate the first caption
          boundCaptionBlock = candidateCaptions.first;
        } else {
          // Multiple images: find closest caption by vertical proximity
          double minDistance = double.infinity;
          for (final c in candidateCaptions) {
            final cTop = c.sourceBounds?.top ?? 0.0;
            final imgY =
                img.bounds?.top ??
                (pageGeometry.pageSize.height *
                    (i + 1) /
                    (pageImages.length + 1));
            final dist = (cTop - imgY).abs();
            if (dist < minDistance) {
              minDistance = dist;
              boundCaptionBlock = c;
            }
          }
        }
      }

      final captionText = boundCaptionBlock?.text;
      if (boundCaptionBlock != null) {
        remainingBlocks.remove(boundCaptionBlock);
        candidateCaptions.remove(boundCaptionBlock);
      }

      // 2. Classify semantic role
      ImageSemanticRole role;
      if (captionText != null &&
          RegExp(
            r'(diagram|denah|blueprint|map|peta|chart)',
            caseSensitive: false,
          ).hasMatch(captionText)) {
        role = ImageSemanticRole.diagram;
      } else if ((img.isCover || img.sourcePage == 0) &&
          captionText == null &&
          imgArea > pageArea * 0.4) {
        role = ImageSemanticRole.coverImage;
      } else if (imgArea > pageArea * 0.65) {
        role = ImageSemanticRole.fullPageIllustration;
      } else {
        role = ImageSemanticRole.inlineFigure;
      }

      // Position: if caption exists, place image directly preceding the caption
      Rect? placementBounds = img.bounds;
      if (placementBounds == null && boundCaptionBlock?.sourceBounds != null) {
        final cBounds = boundCaptionBlock!.sourceBounds!;
        placementBounds = Rect.fromLTWH(
          cBounds.left,
          math.max(0.0, cBounds.top - 120.0),
          cBounds.width,
          100.0,
        );
      }
      placementBounds ??= _estimateImageBounds(img, pageGeometry);

      final imageBlock = SemanticReconstructedBlock(
        type: SemanticBlockType.image,
        text: captionText ?? '',
        sourcePageIndex: img.sourcePage,
        sourceBounds: placementBounds,
        image: img,
        captionText: captionText,
        confidence: captionText != null ? 0.98 : 0.85,
        metadata: {
          'role': role.name,
          'dimensions': [img.dimensions.width, img.dimensions.height],
          'aspectRatio': img.aspectRatio,
          'filter': img.filter,
        },
      );

      imageBlocks.add(imageBlock);
    }

    // 3. Merge image blocks and text blocks in vertical coordinate order
    final combined = <SemanticReconstructedBlock>[
      ...remainingBlocks,
      ...imageBlocks,
    ];
    combined.sort((a, b) {
      final aTop = a.sourceBounds?.top ?? 9999.0;
      final bTop = b.sourceBounds?.top ?? 9999.0;
      return aTop.compareTo(bTop);
    });

    return combined;
  }

  /// Estimates approximate bounding box if explicit coordinates were omitted by the PDF stream.
  static Rect? _estimateImageBounds(
    ExtractedImage img,
    ExtractedPageGeometry page,
  ) {
    if (page.pageSize.width <= 0 || page.pageSize.height <= 0) return null;

    final w = page.pageSize.width * 0.75;
    final h = 180.0;
    final left = (page.pageSize.width - w) / 2.0;

    return Rect.fromLTWH(left, page.pageSize.height * 0.25, w, h);
  }
}
