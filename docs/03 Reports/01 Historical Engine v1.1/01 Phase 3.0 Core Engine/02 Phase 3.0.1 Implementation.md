# Phase 3.0.1 Implementation — Non-Destructive Scanned PDF Image Enhancement

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.0.1 Non-Destructive Scanned PDF Image Enhancement
> - **Urutan Dokumen**: Laporan 02 dari 13 pada Phase 3.0 Core Engine
> - **Tanggal**: 1 November 2026
> - **Status Verifikasi**: **PASS**

---

## Executive Summary
Phase 3.0.1 introduces a high-performance, non-destructive image enhancement pipeline for `OriginalPdfReader` in Digital Books. The implementation dramatically improves visual readability for scanned book pages (contrast boosting, paper background whitening, character stroke sharpening, and spine gutter crease shadow leveling) while strictly preserving the immutability of the original PDF document.

---

## Architecture & Design Principles

### 1. Zero-Byte Original Document Immutability
In accordance with Rule #1 and Rule #8 of `AGENTS.md`:
- The underlying PDF file on disk is never modified, rewritten, or mutated.
- Image enhancement operates dynamically at render-time on 32-bit `BGRA8888` pixel buffers decoded by `pdfrx` (`page.render()`).
- All enhancements are computed non-destructively in-memory before texture upload to `ui.Image`.

### 2. Double-Buffered Rendering & Zero White Flash
Toggling enhancements or switching pages never results in a blank or flashing white screen:
- The bitmap cache (`_bitmapCache`) retains previous page textures under composite configuration keys (`cacheKeySuffix`, e.g., `enh_balanced_R_g1_gr1`).
- When a configuration change occurs or a new page is navigated to, the current texture remains on screen (`RawImage`) while the enhanced texture renders asynchronously.
- Once the enhanced bitmap is decoded (`ui.decodeImageFromPixels`), the cache entry is updated and smoothly repainted.

### 3. High-Performance Processing Pipeline
The core enhancer `ScannedImageEnhancer` operates on raw `Uint8List` typed buffers:
1. **256-Byte S-Curve Look-Up Table (LUT):**
   - Applies non-linear contrast expansion with background whitening.
   - Pushes dark ink (`luminance < 120`) towards deep black.
   - Shifts yellowed/grayish paper background (`luminance > 185`) to clean white (`255`).
2. **Directional Spine Gutter Shadow Suppression:**
   - Detects page parity (`isLeftPage`).
   - Left page: suppresses shadow gradient on the inner right margin (rightmost 16% width).
   - Right page: suppresses shadow gradient on the inner left margin (leftmost 16% width).
3. **ITU-R BT.601 Grayscale Conversion:**
   - Integer fixed-point math: `(r * 77 + g * 150 + b * 29) >> 8`.
4. **Lightweight 3x3 Unsharp Convolution:**
   - 5-point discrete Laplacian stencil with highlight/shadow protection to avoid edge halation.

---

## Key Components

| Component | File | Responsibilities |
| :--- | :--- | :--- |
| `ScannedImageEnhancer` | `lib/features/processing/services/scanned_image_enhancer.dart` | Non-destructive pixel enhancement, LUT computation, gutter shadow leveling, unsharp masking. |
| `ScanEnhancementConfig` | `lib/features/processing/services/scanned_image_enhancer.dart` | Immutable settings model (`isEnabled`, `intensity`, `toGrayscale`, `removeGutterShadow`, `isLeftPage`). |
| `scanEnhancementConfigProvider` | `lib/features/reader/providers/reader_settings_provider.dart` | Per-book Riverpod state provider. |
| `OriginalPdfReader` | `lib/features/reader/presentation/widgets/original_pdf_reader.dart` | Integrated render-time enhancement, configuration-keyed LRU bitmap cache, fallback rendering. |
| `AppearanceSheet` | `lib/features/reader/presentation/widgets/appearance_sheet.dart` | UI controls: toggle switch, intensity chips (Lembut, Seimbang, Kuat), gutter shadow toggle, grayscale toggle. |

---

## Verification & Test Coverage
- `test/phase_3_0_1_image_enhancement_test.dart`: 7 unit & widget tests covering LUT curves, gutter leveling, grayscale vs color modes, LRU key generation, and non-blocking widget rendering.
- `test/phase_3_0_1_pdf_transition_validation_test.dart`: 10 regression tests verifying zero white flash, rapid flipping, warm cache performance, and list scrolling stability.

