# ARCHIVE: Scanned PDF & OCR Intelligence Spike

**Archive Date**: 2026-11-02
**Status**: ARCHIVED (Historical Research & Benchmark Data)
**Origin Milestone**: Phase 3.0 Scanned PDF Intelligence Spike

## 1. Overview
This directory preserves the experimental research scripts and raw benchmark result datasets generated during the exploration of macOS Vision OCR and Core Image image enhancement for Digital Books.

## 2. Directory Contents
- `benchmark_ocr_results.json`: Empirical benchmark measurements (confidence scores, line detection counts, page numbers, line-by-line category classifications, and inference duration) on scanned test documents including *Laut Bercerita*.
- `benchmark_enhancement_results.json`: Empirical execution latencies and filter parameters evaluated for Core Image contrast, exposure, and edge sharpening presets.
- `vision_ocr_benchmark.swift`: Standalone Swift test harness used to profile Apple Vision framework (`VNRecognizeTextRequest`) against multi-page PDFs.
- `core_image_enhancer.swift`: Standalone Swift test harness used to evaluate `CIColorControls`, `CIExposureAdjust`, and `CIUnsharpMask` filters.

## 3. Production Supersession
These experimental spike files have been superseded by production components:
1. Native OCR binary & runner:
   - Source: [`macos/tools/vision_ocr.swift`](file:///Users/davindalana/Documents/Project/Digital%20Books/macos/tools/vision_ocr.swift)
   - Executable: [`bin/vision_ocr`](file:///Users/davindalana/Documents/Project/Digital%20Books/bin/vision_ocr)
   - Service: [`lib/features/processing/services/apple_vision_ocr_service.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/lib/features/processing/services/apple_vision_ocr_service.dart)
2. Image Enhancement Service:
   - Implementation: [`lib/features/processing/services/scanned_image_enhancer.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/lib/features/processing/services/scanned_image_enhancer.dart)
